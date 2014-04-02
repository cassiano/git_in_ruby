class CreateDbBranches < ActiveRecord::Migration
  def self.up
    create_table :db_branches do |t|
      t.column :name, :string, null: false
      t.column :sha1, :string, limit: 40, null: false
    end
  end

  def self.down
    drop_table :db_branches
  end
end
