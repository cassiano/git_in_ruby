class CreateDbDevelopers < ActiveRecord::Migration
  def self.up
    create_table :db_developers do |t|
      t.column :name_and_email, :string, null: false
    end

    add_index :db_developers, :name_and_email, :unique => true
  end

  def self.down
    drop_table :db_developers
  end
end
