class CreateDbFilenames < ActiveRecord::Migration
  def self.up
    create_table :db_filenames, options: 'ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin' do |t|
      t.column :name, :string, null: false
    end

    add_index :db_filenames, :name, :unique => true
  end

  def self.down
    drop_table :db_filenames
  end
end
