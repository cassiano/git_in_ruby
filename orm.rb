# require 'active_record'
# require 'yaml'
# require 'logger'
#
# dbconfig = YAML::load(File.open('database.yml'))
# ActiveRecord::Base.establish_connection(dbconfig)
# ActiveRecord::Base.logger = Logger.new(File.open('database.log', 'a'))
#
# class User < ActiveRecord::Base
#   has_many :roles
# end
#
# class Role < ActiveRecord::Base
#   belongs_to :user
# end
#
# u = User.create!(name: 'Cassiano')
# r = Role.create!(name: 'Admin', user: u)
