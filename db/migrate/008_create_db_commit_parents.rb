class CreateDbCommitParents < ActiveRecord::Migration
  def self.up
    create_table :db_commit_parents do |t|
      t.belongs_to :commit, null: false
      t.belongs_to :parent, null: false
    end

    add_index :db_commit_parents, [:commit_id, :parent_id], unique: true

    add_foreign_key :db_commit_parents, :db_objects, column: :commit_id
    add_foreign_key :db_commit_parents, :db_objects, column: :parent_id
  end

  def self.down
    drop_table :db_commit_parents
  end
end
