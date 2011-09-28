  #   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

class PublicsController < ApplicationController
  require File.join(Rails.root, '/lib/diaspora/parser')
  require File.join(Rails.root, '/lib/postzord/receiver/public')
  require File.join(Rails.root, '/lib/postzord/receiver/private')
  include Diaspora::Parser #TODO: can this line be removed?

  skip_before_filter :set_header_data
  skip_before_filter :which_action_and_user
  skip_before_filter :set_grammatical_gender
  before_filter :allow_cross_origin, :only => [:hcard, :host_meta, :webfinger]
  before_filter :check_for_xml, :only => [:receive, :receive_public]

  respond_to :html
  respond_to :xml, :only => :post

  NATIVE_VERSION = '2010-11-23T00:00Z'
  SUPPORTED_VERSIONS = [
    # add new versions here at the top
    '2010-11-23T00:00Z', # release date of very first diaspora version
  ]

  def allow_cross_origin
    headers["Access-Control-Allow-Origin"] = "*"
  end

  layout false
  caches_page :host_meta

  def hcard
    @person = Person.where(:guid => params[:guid]).first
    unless @person.nil? || @person.owner.nil?
      render 'publics/hcard'
    else
      render :nothing => true, :status => 404
    end
  end

  def host_meta
    render 'host_meta', :content_type => 'application/xrd+xml'
  end

  def webfinger
    @person = Person.local_by_account_identifier(params[:q]) if params[:q]
    unless @person.nil?
      render 'webfinger', :content_type => 'application/xrd+xml'
    else
      render :nothing => true, :status => 404
    end
  end

  def hub
    render :text => params['hub.challenge'], :status => 202, :layout => false
  end

  def receive_public
    params[:version] ||= '2010-11-23T00:00Z'
    render :xml => SUPPORTED_VERSIONS, :status => 405 unless is_requested_version_supported?

    Resque.enqueue(Jobs::ReceiveUnencryptedSalmon, Pod.cast(CGI::unescape(params[:xml]), params[:version]))
    render :nothing => true, :status => :ok
  end

  def receive
    params[:version] ||= '2010-11-23T00:00Z'
    render :xml => SUPPORTED_VERSIONS, :status => 405 unless is_requested_version_supported?

    person = Person.where(:guid => params[:guid]).first

    if person.nil? || person.owner_id.nil?
      Rails.logger.error("Received post for nonexistent person #{params[:guid]}")
      render :nothing => true, :status => 404
      return
    end

    @user = person.owner
    Resque.enqueue(Jobs::ReceiveEncryptedSalmon, @user.id, Pod.cast(CGI::unescape(params[:xml]), params[:version]))

    render :nothing => true, :status => 202
  end


  private

  def is_requested_version_supported?()
    SUPPORTED_VERSIONS.include?(params[:version])
  end

  def check_for_xml
    if params[:xml].nil?
      render :nothing => true, :status => 422
      return
    end
  end
end
