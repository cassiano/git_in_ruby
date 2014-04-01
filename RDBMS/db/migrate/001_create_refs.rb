class CreateRefs < ActiveRecord::Migration
  def self.up
    create_table :refs do |t|
      t.column :name, :string, null: false
      t.column :ref, :string, null: false
    end
  end

  def self.down
    drop_table :refs
  end
end
