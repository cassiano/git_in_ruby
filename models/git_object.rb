class GitObject
  attr_reader :repository, :sha1, :commit_level, :type, :size, :data, :content_sha1

  # http://stackoverflow.com/questions/737673/how-to-read-the-mode-field-of-git-ls-trees-output
  # A clear violation of the Open-Closed Principle (GitObjects should have no knowledge about Trees, Blobs etc).
  # For more details: http://cl.ly/0i182e1C1A2k
  VALID_MODES = {
    '40000'  => 'Tree',
    '100644' => 'Blob',
    '100755' => 'ExecutableFile',
    '100664' => 'GroupWritableFile',
    '120000' => 'SymLink',
    '160000' => 'GitSubModule'
  }

  class << self
    attr_accessor :filemode

    def valid_modes_by_type
      VALID_MODES.inject({}) { |acc, (mode, object_type)| acc.merge(object_type.underscore.to_sym => mode) }
    end

    def mode_for_type(type)
      valid_modes_by_type[type]
    end

    def find_or_initialize_by_sha1(repository, sha1, options = {})
      repository.instances[sha1] ||= new(repository, Sha1Util.standardized_hex_string_sha1(sha1), options)
    end

    remember :valid_modes_by_type, :mode_for_type
  end

  def initialize(repository, sha1, options = {})
    # Set default options.
    options = {
      commit_level: 1,
      load_blob_data: false
    }.merge(options)

    @repository     = repository
    @sha1           = sha1
    @commit_level   = options[:commit_level]
    @load_blob_data = !!options[:load_blob_data]

    load
  end

  def load_blob_data?
    @load_blob_data
  end

  def validate
    puts "(#{commit_level}) Validating #{self.class.name} with SHA1 #{sha1}"

    # Locate the ancestor class which is the immediate subclass of GitObject in the hierarchy chain (one of: Blob, Commit or Tree).
    expected_type = (self.class.ancestors.find { |cls| cls.superclass == GitObject }).name.underscore.to_sym

    raise InvalidTypeError, "Invalid type '#{type}' (expected '#{expected_type}')"  unless type == expected_type
    raise InvalidSha1Error, "Invalid SHA1 '#{sha1}' (expected '#{content_sha1}')"   unless sha1 == content_sha1

    validate_data
  end

  def validate_data
    raise NotImplementedError
  end

  def checkout!(destination_path = default_checkout_folder)
    raise NotImplementedError
  end

  protected

  def default_checkout_folder
    File.join 'checkout_files', sha1[0..6]
  end

  def parse_data(data)
  end

  def load
    object_info = repository.load_object(sha1)

    @size         = object_info[:size]
    @content_sha1 = object_info[:content_sha1]
    @type         = object_info[:type]
    @data         = object_info[:data]

    parse_data(@data) if @data

    data_size = @data.respond_to?(:bytesize) ? @data.bytesize : data.size

    # Since the data will not always be available, its size must be checked here (and not later, in the :validate method).
    raise InvalidSizeError, "Invalid size #{@size} (expected #{data_size})" unless @size == data_size

    # Nullify data for Blobs, if applicable.
    @data = nil if @type == :blob && !load_blob_data?
  end

  def equals?(value, another_value, what)
    (value == another_value).tap do |equals|
      raise "'#{value}' != '#{another_value}' when comparing '#{what}' in #{self.class.name} with SHA1 #{sha1}" unless equals
    end
  end

  remember :validate
end
