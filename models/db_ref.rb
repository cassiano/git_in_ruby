class DbRef < ActiveRecord::Base
  validates_presence_of :name, :ref
end
