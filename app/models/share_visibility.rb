#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

class ShareVisibility < ActiveRecord::Base
  belongs_to :contact
  belongs_to :shareable, :polymorphic => :true

  # Perform a batch import, given a set of contacts and a shareable
  # @note performs a bulk insert in mySQL; performs linear insertions in postgres
  # @param contacts [Array<Contact>] Recipients
  # @param share [Shareable]
  # @return [void]
  def self.batch_import(contacts, share)
    if postgres?
      contacts.each do |contact|
        ShareVisibility.find_or_create_by_contact_id_and_shareable_id_and_shareable_type(contact.id, share.id, share.class.base_class.to_s)
      end
    else
      new_share_visibilities = contacts.map do |contact|
        ShareVisibility.new(:contact_id => contact.id, :shareable_id => share.id, :shareable_type => share.class.base_class.to_s)
      end
      ShareVisibility.import(new_share_visibilities)
    end
  end
end
