class CreateDbTreeEntryNames < ActiveRecord::Migration
  def self.up
    create_table :db_tree_entry_names do |t|
      t.column :name, :string, null: false
    end

    add_index :db_tree_entry_names, :name, :unique => true
  end

  def self.down
    drop_table :db_tree_entry_names
  end
end
