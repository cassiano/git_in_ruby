class CreateDbObjects < ActiveRecord::Migration
  def self.up
    create_table :db_objects do |t|
      t.column :sha1, :string, limit: 40, null: false
      t.column :type, :string, limit: 16, null: false      # DbBlob, DbTree or DbCommit.
      t.column :source_sha1, :string, limit: 40

      # Blobs.
      t.column :blob_data, :longblob

      # Trees (no specific columns needed!).

      # Commits.
      t.belongs_to  :commit_tree
      t.belongs_to  :commit_author
      t.column      :commit_author_date, :datetime
      t.column      :commit_author_date_gmt_offset, :string, limit: 5
      t.belongs_to  :commit_committer
      t.column      :commit_committer_date, :datetime
      t.column      :commit_committer_date_gmt_offset, :string, limit: 5
      t.column      :commit_subject, :text
    end

    add_foreign_key :db_objects, :db_objects, column: :commit_tree_id

    add_index :db_objects, :sha1,        unique: true
    add_index :db_objects, :source_sha1, unique: true
  end

  def self.down
    drop_table :db_objects
  end
end
