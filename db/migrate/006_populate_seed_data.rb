class PopulateSeedData < ActiveRecord::Migration
  class DbRef < ActiveRecord::Base
    validates_presence_of :name, :ref
  end

  class DbBranch < ActiveRecord::Base
    validates_presence_of :name
  end

  def self.up
    DbRef.create! name: 'HEAD', ref: 'master'
    DbBranch.create! name: 'master', sha1: ''
  end

  def self.down
    DbRef.delete_all name: 'HEAD'
    DbBranch.delete_all name: 'master'
  end
end
