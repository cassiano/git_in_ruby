class CreateDbTreeEntries < ActiveRecord::Migration
  def self.up
    create_table :db_tree_entries do |t|
      t.belongs_to :tree,       null: false
      t.belongs_to :git_object, null: false
      t.belongs_to :filename,   null: false
      t.belongs_to :filemode,   null: false
    end

    add_foreign_key :db_tree_entries, :db_objects,    column: :tree_id
    add_foreign_key :db_tree_entries, :db_objects,    column: :git_object_id
    add_foreign_key :db_tree_entries, :db_filenames,  column: :filename_id
    add_foreign_key :db_tree_entries, :db_filemodes,  column: :filemode_id

    add_index :db_tree_entries, [:tree_id, :filename_id], :unique => true
  end

  def self.down
    drop_table :db_tree_entries
  end
end
