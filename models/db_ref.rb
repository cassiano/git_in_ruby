class DbRef < ActiveRecord::Base
  validates_presence_of :name, :ref

  def self.sha1_referenced_by(name)
    if (head = find_by(name: name))
      if head.ref =~ /\A\h{40}\Z/ && !DbBranch.exists?(name: head.ref)   # Head contains a SHA1 which does not represent a branch name?
        head.ref
      else                                  # No, so look for a branch with that name.
        (branch = DbBranch.find_by(name: head.ref)) && branch.sha1
      end
    end
  end
end
