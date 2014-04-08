class DbCommit < DbObject
  alias_attribute :author,    :commit_author
  alias_attribute :committer, :commit_committer
  alias_attribute :subject,   :commit_subject

  belongs_to              :tree, class_name: 'DbTree', foreign_key: :commit_tree_id
  has_and_belongs_to_many :parents,
                          class_name:               'DbCommit',
                          join_table:               :db_commit_parents,
                          foreign_key:              :commit_id,
                          association_foreign_key:  :parent_id

  validates_presence_of :tree, :author, :committer, :subject

  def to_raw
    [:commit, [tree.sha1, parents.map(&:sha1), author, committer, subject]]
  end
end
