class AddCommentsCountToPhotos < ActiveRecord::Migration
  def self.up
    add_column :photos, :comments_count, :string
  end

  def self.down
    remove_column :photos, :comments_count
  end
end
