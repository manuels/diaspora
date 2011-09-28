#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

require 'typhoeus'
require 'active_support/base64'

class HydraWrapper

  OPTS = {:max_redirects => 3, :timeout => 5000, :method => :post}

  attr_reader :failed_people, :user, :object_xml
  attr_accessor :dispatcher_class, :people, :hydra

  def initialize(user, people, object_xml, dispatcher_class)
    @user = user
    @salmon = {}
    @failed_people = []
    @hydra = Typhoeus::Hydra.new
    @people = people
    @dispatcher_class = dispatcher_class
    @object_xml = object_xml
  end

  # Delegates run to the @hydra
  def run
    @hydra.run
  end

  # @param [String] url of pod the salmon is sent to
  # @return [Salmon]
  def salmon(url)
    if defined? Pod
      xml = ::Pod.find_or_create_by_url(url).cast(@object_xml)
    else
      xml = @object_xml
    end
    @salmon[url] ||= @dispatcher_class.salmon(@user, xml)
  end

  # Group people on their receiving_urls
  # @return [Hash] People grouped by receive_url ([String] => [Array<Person>])
  def grouped_people
    @people.group_by do |person|
      @dispatcher_class.receive_url_for(person)
    end
  end 

  # Inserts jobs for all @people
  def enqueue_batch
    grouped_people.each do |receive_url, people_for_receive_url|
      if xml = salmon(receive_url).xml_for(people_for_receive_url.first)
        self.insert_job(receive_url, xml, people_for_receive_url)
      end
    end
  end

  # Prepares and inserts job into the @hydra queue
  # @param url [String]
  # @param xml [String]
  # @params people [Array<Person>]
  def insert_job(url, xml, people)
    request = Typhoeus::Request.new(url, OPTS.merge(:params => {:xml => CGI::escape(xml)}))
    prepare_request!(request, people)
    @hydra.queue(request)
  end

  # @param request [Typhoeus::Request]
  # @param person [Person]
  def prepare_request!(request, people_for_receive_url)
    request.on_complete do |response|
      # Save the reference to the pod to the database if not already present
      pod = ::Pod.find_or_create_by_url(response.effective_url)

      if redirecting_to_https?(response) 
        Person.url_batch_update(people_for_receive_url, response.headers_hash['Location'])
      end

      if response.code == 405
        pod.supported_versions = Array.from_xml(response.body)
        pod.save!
      end

      unless response.success?
        Rails.logger.info("event=http_multi_fail sender_id=#{@user.id}  url=#{response.effective_url} response_code='#{response.code}'")
        @failed_people += people_for_receive_url.map{|i| i.id}
      end
    end
  end

  # @return [Boolean]
  def redirecting_to_https?(response)
    if response.code >= 300 && response.code < 400
      response.headers_hash['Location'] == response.request.url.sub('http://', 'https://')
    else
      false
    end
  end
end
