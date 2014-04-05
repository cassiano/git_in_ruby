class DbBranch < ActiveRecord::Base
  validates_presence_of :name, :sha1
end
