class DbCommit < DbObject
  alias_attribute :author,    :commit_author
  alias_attribute :committer, :commit_committer
  alias_attribute :subject,   :commit_subject

  belongs_to              :tree, class_name: 'DbTree', foreign_key: :commit_tree_id
  has_and_belongs_to_many :parents,
                          class_name: 'DbCommit',
                          join_table: :db_commit_parents,
                          foreign_key: :commit_id,
                          association_foreign_key: :parent_id

  validates_presence_of :tree, :author, :committer, :subject

  def to_raw
    [:commit, [tree.sha1, parents.map(&:sha1), author, committer, subject]]

    # current_time                 = Time.now
    # current_time_seconds_elapsed = current_time.to_i                                  # Seconds elapsed since 01/Jan/1970 00:00:00.
    # current_time_utc_offset      = time_offset_for_commit(current_time.utc_offset)    # Should range from '-2359' to '+2359'.
    #
    # data = ""
    # data << "tree #{tree.sha1}\n"
    # data << parents.map { |parent| "parent #{parent.sha1}\n" }.join
    # data << "author #{author} #{current_time_seconds_elapsed} #{current_time_utc_offset}\n"
    # data << "committer #{committer} #{current_time_seconds_elapsed} #{current_time_utc_offset}\n"
    # data << "\n"
    # data << subject + "\n"
    #
    # "commit #{data.size}\0#{data}"
  end

  # private
  #
  # def time_offset_for_commit(seconds)
  #   sign = seconds < 0 ? '-' : '+'
  #   hour   = seconds.abs / 3600
  #   minute = (seconds.abs - hour * 3600) / 60
  #
  #   '%1s%02d%02d' % [sign, hour, minute]
  # end
end
