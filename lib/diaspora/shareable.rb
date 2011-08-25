#   Copyright (c) 2010, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

module Diaspora
  module Shareable
    require File.join(Rails.root, 'lib/diaspora/web_socket')
    include Diaspora::Webhooks

    def self.included(model)
      model.instance_eval do
        include ROXML
        include Diaspora::Guid

        validates :guid, :uniqueness => true
        scope :all_public, where(:public => true, :pending => false)

        has_many :aspect_visibilities, :as => :shareable
        has_many :aspects, :through => :aspect_visibilities

        has_many :share_visibilities, :as => :shareable
        has_many :contacts, :through => :share_visibilities

        belongs_to :author, :class_name => 'Person'

        xml_attr :diaspora_handle
        xml_attr :public
        xml_attr :created_at
      end
    end

    def user_refs
      if AspectVisibility.exists?(:shareable_id => self.id, :shareable_type => self.class.base_class.to_s)
        self.share_visibilities.count + 1
      else
        self.share_visibilities.count
      end
    end

    def diaspora_handle
      read_attribute(:diaspora_handle) || self.author.diaspora_handle
    end

    def diaspora_handle= nd
      self.author = Person.where(:diaspora_handle => nd).first
      write_attribute(:diaspora_handle, nd)
    end

    # The list of people that should receive this Shareable.
    #
    # @param [User] user The context, or dispatching user.
    # @return [Array<Person>] The list of subscribers to this Shareable
    def subscribers(user)
      if self.public?
        user.contact_people
      else
        user.people_in_aspects(user.aspects_with_shareable(self))
      end
    end

    # @param [User] user The user that is receiving this shareable.
    # @param [Person] person The person who dispatched this shareable to the
    # @return [void]
    def receive(user, person)
      #exists locally, but you dont know about it
      #does not exsist locally, and you dont know about it
      #exists_locally?
      #you know about it, and it is mutable
      #you know about it, and it is not mutable

      self.class.transaction do
        local_shareable = self.class.base_class.where(:guid => self.guid).first
        if local_shareable && local_shareable.author_id == self.author_id
          known_shareable = user.find_visible_shareable_by_id(self.class.base_class, self.guid, :key => :guid)
          if known_shareable
            if known_shareable.mutable?
              known_shareable.update_attributes(self.attributes)
            else
              Rails.logger.info("event=receive payload_type=#{self.class} update=true status=abort sender=#{self.diaspora_handle} reason=immutable existing_shareable=#{known_shareable.id}")
            end
          else
            user.contact_for(person).receive_shareable(local_shareable)
            user.notify_if_mentioned(local_shareable)
            Rails.logger.info("event=receive payload_type=#{self.class} update=true status=complete sender=#{self.diaspora_handle} existing_shareable=#{local_shareable.id}")
            return local_shareable
          end
        elsif !local_shareable
          if self.save
            user.contact_for(person).receive_shareable(self)
            user.notify_if_mentioned(self)
            Rails.logger.info("event=receive payload_type=#{self.class} update=false status=complete sender=#{self.diaspora_handle}")
            return self
          else
            Rails.logger.info("event=receive payload_type=#{self.class} update=false status=abort sender=#{self.diaspora_handle} reason=#{self.errors.full_messages}")
          end
        else
          Rails.logger.info("event=receive payload_type=#{self.class} update=true status=abort sender=#{self.diaspora_handle} reason='update not from shareable owner' existing_shareable=#{self.id}")
        end
      end
    end
  end
end
