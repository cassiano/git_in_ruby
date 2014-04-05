class DbObject < ActiveRecord::Base
  validates_presence_of :sha1, :type
end
