class CreateObjects < ActiveRecord::Migration
  def self.up
    create_table :objects do |t|
      t.column :sha1, :string, limit: 40, null: false
      t.column :type, :string, limit: 6, null: false
      t.column :size, :integer, null: false

      # BLOBs.
      t.column :blob_data, :string, limit: 40, null: false

      # Trees.
      t.column :blob_data, :string, limit: 40, null: false
    end
  end

  def self.down
    drop_table :objects
  end
end
