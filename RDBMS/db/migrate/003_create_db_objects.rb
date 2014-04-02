Foreigner.load

class CreateDbObjects < ActiveRecord::Migration
  def self.up
    create_table :db_objects do |t|
      t.column :sha1, :string, limit: 40, null: false
      t.column :type, :string, limit: 16, null: false      # DbBlob, DbTree or DbCommit.
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

    add_foreign_key :db_objects, :db_objects, column: :commit_tree_id

    add_index :db_objects, :sha1, :unique => true
  end

  def self.down
    drop_table :db_objects
  end
end
