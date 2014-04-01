class CreateCommitParents < ActiveRecord::Migration
  def self.up
    create_table :commit_parents do |t|
      t.belongs_to :commit, null: false
      t.belongs_to :parent, null: false
    end

    add_index :commit_parents, [:commit_id, :parent_id], :unique => true

    # add_foreign_key :commit_parents, :objects, column: :commit_id
    # add_foreign_key :commit_parents, :objects, column: :parent_id
  end

  def self.down
    drop_table :commit_parents
  end
end
