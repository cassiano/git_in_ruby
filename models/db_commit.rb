class DbCommit < DbObject
  alias_attribute :author_name,               :commit_author_name
  alias_attribute :author_date,               :commit_author_date
  alias_attribute :author_date_gmt_offset,    :commit_author_date_gmt_offset
  alias_attribute :committer_name,            :commit_committer_name
  alias_attribute :committer_date,            :commit_committer_date
  alias_attribute :committer_date_gmt_offset, :commit_committer_date_gmt_offset
  alias_attribute :subject,                   :commit_subject

  belongs_to              :tree, class_name: 'DbTree', foreign_key: :commit_tree_id
  has_and_belongs_to_many :parents,
                          -> { order 'sha1' },
                          class_name:               'DbCommit',
                          join_table:               :db_commit_parents,
                          foreign_key:              :commit_id,
                          association_foreign_key:  :parent_id

  validates_presence_of :tree, :author_name, :author_date

  def to_raw
    [:commit, [tree.sha1, parents.map(&:sha1).sort, author, committer, subject]]
  end

  # Notice here we use the "Facade" design pattern, so users of our class won't notice we have actually splitted the Author into 2 disctinct
  # pieces (name and date).
  def author
    [author_name, author_date, author_date_gmt_offset]
  end

  def author=(new_author)
    # PS: notice the receiver (self) must be explicitly specified in this case, otherwise local variables will be created instead.
    self.author_name, self.author_date, self.author_date_gmt_offset = new_author
  end

  # The same comment done above for Author applies here for Committer (on using the "Facade" design pattern).
  def committer
    [committer_name, committer_date, committer_date_gmt_offset]
  end

  def committer=(new_committer)
    # PS: notice the receiver (self) must be explicitly specified in this case, otherwise local variables will be created instead.
    self.committer_name, self.committer_date, self.committer_date_gmt_offset = new_committer
  end
end
