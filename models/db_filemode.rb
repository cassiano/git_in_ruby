class DbFilemode < ActiveRecord::Base
  validates_presence_of :mode
end
