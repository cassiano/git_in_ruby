class CreateDbTreeEntries < ActiveRecord::Migration
  def self.up
    create_table :db_tree_entries do |t|
      t.belongs_to :tree, null: false
      t.belongs_to :entry, null: false

      t.column :mode, :string, limit: 6, null: false
      t.column :name, :string, limit: 255, null: false
    end

    add_foreign_key :db_tree_entries, :db_objects, column: :tree_id
    add_foreign_key :db_tree_entries, :db_objects, column: :entry_id

    add_index :db_tree_entries, [:tree_id, :entry_id], :unique => true
    add_index :db_tree_entries, [:tree_id, :name], :unique => true
  end

  def self.down
    drop_table :db_tree_entries
  end
end
