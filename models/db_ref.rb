class DbRef < ActiveRecord::Base
  validates_presence_of :name, :ref

  def self.sha1_referenced_by(name)
    head_ref = find_by_name(name)

    DbBranch.find_by_name(head_ref.ref).sha1
  end
end
