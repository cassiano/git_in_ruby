class DbTreeEntry < ActiveRecord::Base
  validates_presence_of :filemode, :filename, :git_object    # Do not include :tree in this list!

  belongs_to :filemode,   class_name: 'DbFilemode'
  belongs_to :filename,   class_name: 'DbFilename'
  belongs_to :tree,       class_name: 'DbTree'
  belongs_to :git_object, class_name: 'DbObject'      # DbTree or DbBlob.

  delegate :mode, to: :filemode
  delegate :name, to: :filename
end
