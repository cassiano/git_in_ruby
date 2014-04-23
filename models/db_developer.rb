class DbDeveloper < ActiveRecord::Base
  validates_presence_of :name_and_email
end
