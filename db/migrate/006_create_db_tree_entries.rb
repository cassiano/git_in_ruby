class CreateDbTreeEntries < ActiveRecord::Migration
  def self.up
    create_table :db_tree_entries do |t|
      t.belongs_to :tree,             null: false
      t.belongs_to :git_object,       null: false
      t.belongs_to :tree_entry_name,  null: false

      t.column :mode, :string, limit: 6, null: false
    end

    add_foreign_key :db_tree_entries, :db_objects, column: :tree_id
    add_foreign_key :db_tree_entries, :db_objects, column: :git_object_id

    add_index :db_tree_entries, [:tree_id, :tree_entry_name_id], :unique => true
  end

  def self.down
    drop_table :db_tree_entries
  end
end
