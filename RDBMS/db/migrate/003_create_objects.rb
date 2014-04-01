class CreateObjects < ActiveRecord::Migration
  def self.up
    create_table :objects do |t|
      t.column :sha1, :string, limit: 40, null: false
      t.column :type, :string, limit: 6, null: false      # One of: ['blob', 'tree', 'commit']
      t.column :size, :integer, null: false

      # BLOBs.
      t.column :blob_data, :text

      # Trees (no more columns needed for trees).

      # Commits.
      t.belongs_to :commit_tree
      t.column :commit_author, :string
      t.column :commit_committer, :string
      t.column :commit_subject, :text
    end
  end

  def self.down
    drop_table :objects
  end
end
