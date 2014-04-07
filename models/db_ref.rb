class DbRef < ActiveRecord::Base
  validates_presence_of :name, :ref

  def self.sha1_referenced_by(name)
    head_ref = find_by_name(name)

    if head_ref.ref =~ /\A\h{40}\Z/       # Is is a SHA1?
      head_ref.ref
    else                                  # No, so look for a branch with that name.
      (branch = DbBranch.find_by_name(head_ref.ref)) && branch.sha1
    end
  end
end
