class CreateDbRefs < ActiveRecord::Migration
  def self.up
    create_table :db_refs do |t|
      t.column :name, :string, null: false
      t.column :ref, :string, null: false
    end

    add_index :db_refs, :name, :unique => true
  end

  def self.down
    drop_table :db_refs
  end
end
