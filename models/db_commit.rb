class DbCommit < DbObject
  alias_attribute :author_date,               :commit_author_date
  alias_attribute :author_date_gmt_offset,    :commit_author_date_gmt_offset
  alias_attribute :committer_date,            :commit_committer_date
  alias_attribute :committer_date_gmt_offset, :commit_committer_date_gmt_offset
  alias_attribute :subject,                   :commit_subject

  belongs_to :tree,                 class_name: 'DbTree',       foreign_key: :commit_tree_id
  belongs_to :author_developer,     class_name: 'DbDeveloper',  foreign_key: :commit_author_id
  belongs_to :committer_developer,  class_name: 'DbDeveloper',  foreign_key: :commit_committer_id

  has_and_belongs_to_many :parents,
                          -> { order 'db_commit_parents.id' },
                          class_name:               'DbCommit',
                          join_table:               :db_commit_parents,
                          foreign_key:              :commit_id,
                          association_foreign_key:  :parent_id

  validates_presence_of :tree, :author, :author_date, :author_date_gmt_offset, :committer, :committer_date, :committer_date_gmt_offset

  def to_raw
    [:commit, [tree.sha1, parents.map(&:sha1), author, committer, subject]]
  end

  # Notice here we use the "Facade" design pattern, so users of our class won't notice we have actually splitted the Author into 2 disctinct
  # pieces (name and date).
  def author
    [ActiveSupport::Multibyte::Unicode.normalize(author_developer.name_and_email), author_date, author_date_gmt_offset]
  end

  def author=(new_author)
    self.author_developer = DbDeveloper.find_or_create_by(name_and_email: new_author[0])

    self.author_date, self.author_date_gmt_offset = new_author[1..-1]
  end

  # The same comment done above for Author applies here for Committer (on using the "Facade" design pattern).
  def committer
    [ActiveSupport::Multibyte::Unicode.normalize(committer_developer.name_and_email), committer_date, committer_date_gmt_offset]
  end

  def committer=(new_committer)
    self.committer_developer = DbDeveloper.find_or_create_by(name_and_email: new_committer[0])

    self.committer_date, self.committer_date_gmt_offset = new_committer[1..-1]
  end
end
