#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

module Diaspora
  module UserModules
    module Querying

      def find_visible_post_by_id( id, opts={} )
        self.find_visible_shareable_by_id(Post, id, opts)
      end

      def find_visible_photo_by_id( id, opts={} )
        self.find_visible_shareable_by_id(Photo, id, opts)
      end

      def find_visible_shareable_by_id( base_class, id, opts={} )
        key = opts.delete(:key) || :id
        shareable = base_class.where(key => id).joins(:contacts).where(:contacts => {:user_id => self.id}).where(opts).select(base_class.table_name+".*").first
        shareable ||= base_class.where(key => id, :author_id => self.person.id).where(opts).first
        shareable ||= base_class.where(key => id, :public => true).where(opts).first
      end

      def visible_posts(opts = {})
        opts[:type] ||= 'StatusMessage'
        visible_shareable(Post, opts)
      end

      def visible_photos(opts = {})
        visible_shareable(Photo, opts)
      end

      def visible_shareable(base_class, opts = {})
        defaults = {
          :order => 'updated_at DESC',
          :limit => 15,
          :hidden => false
        }
        opts = defaults.merge(opts)

        order_field = opts[:order].split.first.to_sym
        order_with_table = base_class.table_name + '.' + opts[:order]

        opts[:max_time] = Time.at(opts[:max_time]) if opts[:max_time].is_a?(Integer)
        opts[:max_time] ||= Time.now + 1

        select_clause = "DISTINCT %s.id, %s.updated_at AS updated_at, %s.created_at AS created_at" % [base_class.table_name, base_class.table_name, base_class.table_name]

        posts_from_others = base_class.joins(:contacts).where( :pending => false, :share_visibilities => {:hidden => opts[:hidden]}, :contacts => {:user_id => self.id})
        posts_from_self = self.person.send(base_class.name.tableize).where(:pending => false)
        posts_from_others = posts_from_others.where(:type => opts[:type]) if opts.has_key?(:type)
        posts_from_self = posts_from_self.where(:type => opts[:type]) if opts.has_key?(:type)

        if opts[:by_members_of]
          posts_from_others = posts_from_others.joins(:contacts => :aspect_memberships).where(
            :aspect_memberships => {:aspect_id => opts[:by_members_of]})
          posts_from_self = posts_from_self.joins(:aspect_visibilities).where(:aspect_visibilities => {:aspect_id => opts[:by_members_of]})
        end

        unless defined?(ActiveRecord::ConnectionAdapters::SQLite3Adapter) && ActiveRecord::Base.connection.class == ActiveRecord::ConnectionAdapters::SQLite3Adapter
          posts_from_others = posts_from_others.select(select_clause).limit(opts[:limit]).order(order_with_table).where(base_class.arel_table[order_field].lt(opts[:max_time]))
          posts_from_self = posts_from_self.select(select_clause).limit(opts[:limit]).order(order_with_table).where(base_class.arel_table[order_field].lt(opts[:max_time]))
          all_posts = "(#{posts_from_others.to_sql}) UNION ALL (#{posts_from_self.to_sql}) ORDER BY #{opts[:order]} LIMIT #{opts[:limit]}"
        else
          posts_from_others = posts_from_others.select(select_clause)
          posts_from_self = posts_from_self.select(select_clause)
          all_posts = "#{posts_from_others.to_sql} UNION ALL #{posts_from_self.to_sql} ORDER BY #{opts[:order]} LIMIT #{opts[:limit]}"
        end

        post_ids = base_class.connection.select_values(all_posts)

        base_class.where(:id => post_ids).select('DISTINCT '+base_class.table_name+'.*').limit(opts[:limit]).order(order_with_table)
      end

      def contact_for(person)
        return nil unless person
        contact_for_person_id(person.id)
      end
      def aspects_with_shareable(shareable)
        type = shareable.class.base_class.to_s
        self.aspects.joins(:aspect_visibilities).where(:aspect_visibilities => {:shareable_id => shareable.id, :shareable_type => type})
      end

      def contact_for_person_id(person_id)
        Contact.where(:user_id => self.id, :person_id => person_id).includes(:person => :profile).first
      end

      # @param [Person] person
      # @return [Boolean] whether person is a contact of this user
      def has_contact_for?(person)
        Contact.exists?(:user_id => self.id, :person_id => person.id)
      end

      def people_in_aspects(requested_aspects, opts={})
        allowed_aspects = self.aspects & requested_aspects
        person_ids = contacts_in_aspects(allowed_aspects).collect{|contact| contact.person_id}
        people = Person.where(:id => person_ids)

        if opts[:type] == 'remote'
          people = people.where(:owner_id => nil)
        elsif opts[:type] == 'local'
          people = people.where('people.owner_id IS NOT NULL')
        end
        people
      end

      def aspects_with_person person
        contact_for(person).aspects
      end

      def contacts_in_aspects aspects
        aspects.inject([]) do |contacts,aspect|
          contacts | aspect.contacts
        end
      end

      def posts_from(person)
        shareable_from(person, Post)
      end

      def photos_from(person)
        shareable_from(person, Photo)
      end

      def shareable_from(person, base_class)
        return self.person.send(base_class.to_s.tableize).where(:pending => false).order("created_at DESC") if person == self.person
        con = Contact.arel_table
        p = base_class.arel_table
        shareable_ids = []
        if contact = self.contact_for(person)
          shareable_ids = base_class.connection.select_values(
            contact.share_visibilities.where(:hidden => false, :shareable_type => base_class.to_s).select('share_visibilities.shareable_id').to_sql
          )
        end
        shareable_ids += base_class.connection.select_values(
          person.send(base_class.to_s.tableize).where(:public => true).select(base_class.to_s.tableize+'.id').to_sql
        )

        base_class.where(:id => shareable_ids, :pending => false).select('DISTINCT '+base_class.table_name+'.*').order(base_class.table_name+".created_at DESC")
      end
    end
  end
end
