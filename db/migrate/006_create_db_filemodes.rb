class CreateDbFilemodes < ActiveRecord::Migration
  def self.up
    create_table :db_filemodes do |t|
      t.column :mode, :string, limit: 6, null: false
    end

    add_index :db_filemodes, :mode, :unique => true
  end

  def self.down
    drop_table :db_filemodes
  end
end
