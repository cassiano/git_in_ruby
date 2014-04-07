class DbTreeEntry < ActiveRecord::Base
  validates_presence_of :mode, :name, :git_object    # Do not include :tree in this list!

  belongs_to :tree,       class_name: 'DbTree'
  belongs_to :git_object, class_name: 'DbObject'      # DbTree or DbBlob.
end
