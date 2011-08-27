class MovePhotosToTheirOwnTable < ActiveRecord::Migration
  def self.up
    create_table "photos", :force => true do |t|
      t.integer  "author_id",                                              :null => false
      t.boolean  "public",                              :default => false, :null => false
      t.string   "diaspora_handle"
      t.string   "guid",                                                   :null => false
      t.boolean  "pending",                             :default => false, :null => false
      t.string   "type",                  :limit => 40
      t.text     "text"
      t.text     "remote_photo_path"
      t.string   "remote_photo_name"
      t.string   "random_string"
      t.string   "processed_image"
      t.text     "youtube_titles"
      t.datetime "created_at"
      t.datetime "updated_at"
      t.string   "unprocessed_image"
      t.string   "object_url"
      t.string   "image_url"
      t.integer  "image_height"
      t.integer  "image_width"
      t.string   "provider_display_name"
      t.string   "actor_url"
      t.integer  "objectId"
      t.string   "root_guid",             :limit => 30
      t.string   "status_message_guid"
      t.integer  "likes_count",                         :default => 0
    end

    execute <<SQL
      INSERT INTO photos
        SELECT id, author_id, public, diaspora_handle, guid, pending, NULL AS type, text, remote_photo_path, remote_photo_name, random_string, processed_image,
               youtube_titles, created_at, updated_at, unprocessed_image, object_url, image_url, image_height, image_width, provider_display_name,
               actor_url, objectId, root_guid, status_message_guid, likes_count
          FROM posts
          WHERE type = 'Photo'
SQL
    execute <<SQL
      INSERT INTO photos
        SELECT id, author_id, public, diaspora_handle, guid, pending, type, text, remote_photo_path, remote_photo_name, random_string, processed_image,
               youtube_titles, created_at, updated_at, unprocessed_image, object_url, image_url, image_height, image_width, provider_display_name,
               actor_url, objectId, root_guid, status_message_guid, likes_count
          FROM posts
          WHERE type = 'ActivityStreams::Photo'
SQL

    execute "UPDATE aspect_visibilities AS av, photos SET av.shareable_type='Photo' WHERE av.shareable_id=photos.id"
    execute "UPDATE share_visibilities AS sv, photos SET sv.shareable_type='Photo' WHERE sv.shareable_id=photos.id"

    # all your base are belong to us!
    execute "DELETE FROM posts WHERE type='Photo' OR type='ActivityStreams::Photo'"
  end

  def self.down
    execute <<SQL
      INSERT INTO posts
        SELECT NULL AS id, author_id, public, diaspora_handle, guid, pending, 'Photo' AS type, text, remote_photo_path, remote_photo_name, random_string, 
               processed_image, youtube_titles, created_at, updated_at, unprocessed_image, object_url, image_url, image_height, image_width, provider_display_name,
               actor_url, objectId, root_guid, status_message_guid, likes_count
          FROM photos
          WHERE type IS NULL
SQL
    execute <<SQL
      INSERT INTO posts
        SELECT NULL AS id, author_id, public, diaspora_handle, guid, pending, type, text, remote_photo_path, remote_photo_name, random_string, processed_image,
               youtube_titles, created_at, updated_at, unprocessed_image, object_url, image_url, image_height, image_width, provider_display_name,
               actor_url, objectId, root_guid, status_message_guid, likes_count
          FROM photos
          WHERE type = 'ActivityStreams::Photo'
SQL

    execute <<SQL
      UPDATE aspect_visibilities, posts, photos
        SET
          aspect_visibilities.shareable_id=posts.id,
          aspect_visibilities.shareable_type='Post'
        WHERE
          posts.guid=photos.guid AND
          photos.id=aspect_visibilities.shareable_id
SQL
    execute <<SQL
      UPDATE share_visibilities, posts, photos
        SET
          share_visibilities.shareable_id=posts.id,
          share_visibilities.shareable_type='Post'
        WHERE
          posts.guid=photos.guid AND
          photos.id=share_visibilities.shareable_id
SQL

    execute "DROP TABLE photos"
  end
end
