class CreateTreeEntries < ActiveRecord::Migration
  def self.up
    create_table :tree_entries do |t|
      t.belongs_to :tree, null: false
      t.belongs_to :entry, null: false
    end

    add_index :tree_entries, [:tree_id, :entry_id], :unique => true
  end

  def self.down
    drop_table :tree_entries
  end
end
