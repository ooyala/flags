# Copyright © 2011 Ooyala, Inc.
# A simple command-line flag framework.
#
# Usage:
#
# Define flags at the top of your ruby file, after require statements but before any other code. A flag with
# a given name may not be defined more than once, and doing so will raise an error. Examples:
#
# Flags.define_string(:my_string_flag, "default_value", "This is my comment for a string flag")
# Flags.define_symbol(:my_symbol_flag, :default_val, "This is my comment for a symbol flag")
# Flags.define_int(:my_int_flag, 1000, "This is my comment for an int flag")
# Flags.define_float(:my_float_flag, 2.0, "This is my comment for a float flag")
# Flags.define_bool(:my_bool_flag, true, "This is my comment for a bool flag")
#
# In your main:
# if __FILE__ == $0
#   Flags.init  # This will parse and consume all the flags from your command line that match a defined flag
# end
#
# Run your file with some command-line flags:
# ./myfile -my_string_flag "foo" -my_int_flag 2
#
# Note that specifying a boolean flag requires the word "true" or "false" following the flag name.
#
# Then your code can access the flags any time after Flags.init with
# Flags.my_string_flag and Flags.my_int_flag

require 'yaml'

# Note that the Flags class is a singleton, and all of its methods and data storage are class-level rather
# than instance-level. It is currently not possible to have multiple Flags instances within a single process.
class Flags
  # Parses the command line args and extracts flag value pairs. Should be called at least once before getting
  # or setting any flag value. In the future, Flags will start throwing errors if any flag is accessed
  # prior to Flags.init being called.
  #
  # NOTE: this method HAS SIDE EFFECTS - it removes the flag name/value pairs from the supplied array of
  # argument strings! For example, if -meaning_of_life is a flag then after this call to Flags.init:
  #   args = [ "-meaning_of_life", "42", "path/to/output/file" ]
  #   Flags.init(args)
  # the args array will be [ "path/to/output/file" ].
  def self.init(args=$*)
    @@init_called = true

    if args.index("--help") || args.index("-help")
      puts self.help_message
      exit(0)
    end
    @@flags.each do |flag_name, flag|
      flag_name = "-#{flag.name}"
      setter = "#{flag.name}="
      # Use a loop in order to consume all settings for a flag and to keep the last one.
      while true
        value = self.extract_value_for_flag(args, flag_name)
        break if value.nil?  # Check for nil because false values are ok for boolean flags.
        self.send(setter, value)
      end
    end
  end

  # Defines a new flag of string type, such as:
  # Flags.define_string(:my_flag_name, "hello world", "An example of a string flag")
  def self.define_string(name, default_value, description)
    self.define_flag(name, default_value, description, StringFlag)
  end

  # Defines a new flag of symbol type, such as:
  # Flags.define_symbol(:my_flag_name, :a_symbol, "An example of a symbol flag")
  def self.define_symbol(name, default_value, description)
    self.define_flag(name, default_value, description, SymbolFlag)
  end

  # Defines a new flag of integer type, such as:
  # Flags.define_int(:my_flag_name, 42, "An example of an integer flag")
  def self.define_int(name, default_value, description)
    self.define_flag(name, default_value, description, IntFlag)
  end

  # Defines a new flag of boolean type, such as:
  # Flags.define_bool(:my_flag_name, true, "An example of a boolean flag")
  def self.define_bool(name, default_value, description)
    self.define_flag(name, default_value, description, BoolFlag)
  end

  # Defines a new flag of float type, such as:
  # Flags.define_float(:my_flag_name, 3.14, "An example of a float flag")
  def self.define_float(name, default_value, description)
    self.define_flag(name, default_value, description, FloatFlag)
  end

  # TODO: Get rid of the longer define_*_flag() methods and just keep the define_*() ones.
  # Alias the older, longer methods to the new, shorter ones.
  class << self
    alias :define_string_flag :define_string
    alias :define_symbol_flag :define_symbol
    alias :define_int_flag :define_int
    alias :define_bool_flag :define_bool
    alias :define_float_flag :define_float
  end

  # Registers a flag validator that checks the range of a flag.
  def self.register_range_validator(name, range)
    raise_unless_symbol!(name)
    raise_unless_flag_defined!(name)
    flag = @@flags[name]
    flag.add_validator(RangeValidator.new(range))
  end

  # Registers a flag validator that ensures that the flag value is one of the allowed values.
  def self.register_allowed_values_validator(name, *allowed_values)
    raise_unless_symbol!(name)
    raise_unless_flag_defined!(name)
    flag = @@flags[name]
    flag.add_validator(AllowedValuesValidator.new(allowed_values))
  end

  # Registers a flag validator that ensures that the flag value is not one of the disallowed values.
  def self.register_disallowed_values_validator(name, *disallowed_values)
    raise_unless_symbol!(name)
    raise_unless_flag_defined!(name)
    flag = @@flags[name]
    flag.add_validator(DisallowedValuesValidator.new(disallowed_values))
  end

  # Registers a custom flag validator that will raise an error with the specified message if proc.call(value)
  # returns false whenever a value is assigned to the flag.
  def self.register_custom_validator(name, proc, error_message)
    raise_unless_symbol!(name)
    raise_unless_flag_defined!(name)
    flag = @@flags[name]
    validator = FlagValidator.new(proc, error_message)
    flag.add_validator(validator)
  end

  # Returns the description of a flag, or nil if the given flag is not defined.
  # TODO: Deprecate and remove?
  def self.comment_for_flag(name)
    return nil unless @@flags.key? name.to_sym
    return @@flags[name.to_sym].description
  end

  # TODO: how to do aliases for class methods?
  def self.flags_get_comment(name)
    self.comment_for_flag(name)
  end

  def self.flags_get_default_value(name)
    raise_unless_flag_defined!(name)
    return @@flags[name.to_sym].default_value
  end

  def self.flags_is_default(name)
    raise_unless_flag_defined!(name)
    return @@flags[name.to_sym].default?
  end

  # Sets the value of the named flag if the default value has not been overridden. A default value can be
  # overridden in one of these ways:
  # 1) By specifying a value for the flag on the command line (i.e. "-x y")
  # 2) By explicitly changing the value of the flag in the code (i.e. Flags.x = y)
  # 3) By loading a value for the flag from a hash or yaml file.
  #
  # Returns true if the flag value was changed and false if it was not. Raises an error if the named flag does
  # not exist.
  def self.set_if_default(name, value)
    raise_unless_symbol!(name)
    raise_unless_flag_defined!(name)

    flag = @@flags[name]
    return false unless flag.default?
    flag.value = value  # NOTE: calling the setter method changes the internal is_default field to false
    return true
  end

  # Takes a hash of { flag name => flag value } pairs and calls self.set_if_default() on each pair.
  def self.set_multiple_if_default(hash)
    hash.each_pair do |flag_name, flag_value|
      self.set_if_default(flag_name, flag_value)
    end
  end

  # Restores the value of the named flag to its default setting, and returns nil. Raises an error if the named
  # flag does not exist.
  def self.restore_default(name)
    raise_unless_symbol!(name)
    raise_unless_flag_defined!(name)

    @@flags[name].restore_default
    nil
  end

  # Takes an Array or Set of flag names, and calls self.restore_default() on each element.
  def self.restore_multiple_defaults(names)
    names.each do |flag_name|
      self.restore_default(flag_name)
    end
  end

  # Restores the values of all flags to their default settings, and returns nil.
  def self.restore_all_defaults()
    @@flags.each_pair do |name, flag|
      flag.restore_default
    end
    nil
  end

  # Dumps the flags, serialized to yaml to the specified io object.  Returns a string if io is nil.
  def self.to_yaml(io=nil)
    flags = []
    @@flags.keys.sort { |a, b| a.to_s <=> b.to_s }.each do |name|
      flag = @@flags[name]
      flags += [ "-#{name}", flag.value ]
    end
    YAML.dump(flags, io)
  end

  # Serializes the arguments from yaml and returns an array of arguments that can be passed to
  # init.
  def self.args_from_yaml(yaml)
    YAML.load(yaml)
  end

  # This function takes the @@flags object, and returns a hash of just the key, value pairs
  def self.to_hash
    return Hash[@@flags.map { |name, flag| [name, flag.value] }]
  end

  # Converts the flags to a printable string.
  def self.to_s
    flags = []
    @@flags.keys.sort { |a, b| a.to_s <=> b.to_s }.each do |name|
      flag = @@flags[name]
      flag_name = "-#{name}"
      value = flag.value
      if value.is_a?(String)  # we call inspect() on String flags to take care of embedded quotes, spaces, etc.
        flags << "-#{name} #{value.inspect}"
      else
        flags << "-#{name} #{value.to_s}"
      end
    end
    flags.join(" ")
  end

  # This override makes it so that the mocha rubygem prints nicer debug messages.  The downside
  # is that now you need to call Flags.to_s to print human-readable strings.
  def self.inspect
    "Flags"
  end

  private

  # Has Flags.init been called already? Flag values should not be read or written prior to calling Flags.init.
  @@init_called = false

  # Hash of flag name symbols => Flag objects.
  @@flags = {}

  # Internal method that defines a new flag with the given name, default value, description, and type. Used
  # by the public define_* and define_*_flag methods.
  def self.define_flag(name, default_value, description, flag_class)
    raise_unless_symbol!(name)
    raise_if_flag_defined!(name)

    # For each flag, we store the file name where it was defined, and print these file names if called with
    # the --help argument. To get the file names we have to examine the call stack, which is accessible
    # through the Kernel.caller() method. The caller method returns an array of strings that look like this:
    #   ["./bar.rb:1", "foo.rb:2:in `require'", "foo.rb:2"]
    #
    # The caller frame immediately above this one (index 0) is one of the public define_*_flag methods. The
    # frame above that (index 1) is the location where the Flags.define_*_flag method was called, and is the
    # one we want. We also strip the leading "./" from the file name if it's present, for improved readability.
    definition_file = caller[1].split(":")[0].gsub("./", "")
    flag = flag_class.new(name, default_value, description, definition_file)
    @@flags[name] = flag

    # TODO: The flag getter and setter methods should call raise_unless_initialized! However, for now
    # this breaks unit tests so not viable until we add some kind of hook with test/unit that calls Flags.init
    # with empty args before each test case runs.

    # TODO: Would look cleaner if we used the eigenclass approach and class_eval + code block instead
    # of instance_eval + string.

    instance_eval "def self.#{name}; @@flags[:#{name.to_s}].value; end"
    instance_eval "def self.#{name}=(value); @@flags[:#{name.to_s}].value = value; end"
  end

  # Internal method that undefines a flag. Used by the unit test to clean up state between test cases.
  def self.undefine_flag(name)
    raise_unless_symbol!(name)
    raise_unless_flag_defined!(name)

    @@flags.delete(name)

    eigenclass = class << Flags; self; end
    eigenclass.class_eval "remove_method :#{name}"
    eigenclass.class_eval "remove_method :#{name}="
  end

  # Raises an error if a flag with the given name is already defined, or if the flag name would conflict
  # with an existing Flags method.
  def self.raise_if_flag_defined!(name)
    raise "Flag #{name} already defined" if @@flags.key?(name.to_sym)
    raise "Flag #{name} conflicts with an internal Flags method" if self.respond_to?(name.to_sym)
    nil
  end

  # Raises an error unless a flag with the given name is defined.
  def self.raise_unless_flag_defined!(name)
    raise "Flag #{name} not defined" unless @@flags.key?(name.to_sym)
    nil
  end

  # Raises an error unless Flags.init has been called at least once. Useful for catching subtle "I forgot to
  # call Flags.init at the start of my program" bugs.
  def self.raise_unless_initialized!()
    raise "Flags.init has not been called" unless @@init_called
  end

  def self.raise_unless_symbol!(name)
    raise ArgumentError, "Flag name must be a symbol but is a #{name.class}" unless name.is_a?(Symbol)
  end

  def self.extract_value_for_flag(args, flag)
    index = args.index(flag)
    if index
      value = args[index+1]
      args[index..(index+1)] = []  # delete from args
      return value
    end
  end

  def self.help_message
    help = "Known command line flags:\n\n"
    max_name_length = @@flags.values.map { |flag| flag.name.to_s.length }.max
    # Sort the flags by the location in which they are defined (primary) and flag name (secondary).
    definition_file_to_flags = Hash.new { |h, k| h[k] = [] }
    @@flags.each_pair do |name, flag|
      definition_file_to_flags[flag.definition_file].push name
    end

    definition_file_to_flags.keys.sort.each do |file|
      flags = definition_file_to_flags[file]
      help << "Defined in #{file}:\n"
      flags.sort { |a, b| a.to_s <=> b.to_s }.each do |flag_name|
        flag = @@flags[flag_name]
        help << "  -#{flag_name.to_s.ljust(max_name_length+1)} (#{flag.type}) #{flag.description} "\
                "(Default: #{flag.default_value.inspect})\n"
      end
      help << "\n"
    end
    help
  end

  # A subclass of ArgumentError that's raised when an invalid value is assigned to a flag.
  class InvalidFlagValueError < ArgumentError
    def initialize(flag_name, flag_value, error_message)
      super("Flag value #{flag_value.inspect} for flag -#{flag_name.to_s} is invalid: #{error_message}")
    end
  end

  # A FlagValidator can check whether a flag's value is valid (with validity implicitly defined via a provided
  # callback), and raise an error if the validation check fails.
  class FlagValidator
    def initialize(proc, error_message)
      @proc = proc
      @error_message = error_message
    end

    def validate!(flag_name, flag_value)
      raise InvalidFlagValueError.new(flag_name, flag_value, @error_message) unless @proc.call(flag_value)
    end
  end

  # A validator that raises an error if the class of the flag's value is not one of the expected classes.
  class ClassValidator < FlagValidator
    def initialize(*expected_value_classes)
      expected_value_classes = expected_value_classes.to_a.flatten
      proc = Proc.new { |flag_value| expected_value_classes.include?(flag_value.class) }
      error_message = "unexpected value class, expecting one of [#{expected_value_classes.join(',')}]"
      super(proc, error_message)
    end
  end

  # A validator that raises an error if the flag's value is outside the given Range.
  # No type checking is performed (that's the job of the ClassValidator).
  class RangeValidator < FlagValidator
    def initialize(range)
      proc = Proc.new { |flag_value| range.include?(flag_value) }
      error_message = "value out of range! Valid range is #{range.inspect}"
      super(proc, error_message)
    end
  end

  # A validator that raises an error if the flag's value is not in the provided set of allowed values.
  class AllowedValuesValidator < FlagValidator
    def initialize(*allowed_values)
      allowed_values = allowed_values.to_a.flatten
      proc = Proc.new { |flag_value| allowed_values.include?(flag_value) }
      error_message = "illegal value, expecting one of [#{allowed_values.join(',')}]"
      super(proc, error_message)
    end
  end

  # A validator that raises an error if the flag's value is in the provided set of disallowed values.
  class DisallowedValuesValidator < FlagValidator
    def initialize(*disallowed_values)
      disallowed_values = disallowed_values.to_a.flatten
      proc = Proc.new { |flag_value| !disallowed_values.include?(flag_value) }
      error_message = "illegal value, may not be one of [#{disallowed_values.join(',')}]"
      super(proc, error_message)
    end
  end

  # A Flag represents everything we know about a flag - its name, value, default value, description, where
  # it was defined, whether the default value has been explicitly modified, and an optional callback to
  # validate the flag.
  class Flag
    attr_reader :type             # the type of flag, as a symbol
    attr_reader :name             # the name of the flag
    attr_reader :value            # the current value of the flag
    attr_reader :default_value    # the default value of the flag
    attr_reader :is_explicit      # false unless the flag's value has been explicitly changed from default.
                                  # NOTE: if a flag is explicitly set to the default value, this will be true!
    attr_reader :description      # a string description of the flag
    attr_reader :definition_file  # The file name where the flag was defined

    # Initializes the Flag. Arguments:
    #   type - the type of this flag, as one of the symbols [ :string, :symbol, :int, :float, :bool ]
    #   name - the name of this flag, as a symbol
    #   default_value - the default value of the flag. The current value always equals the default when the
    #       Flag object is initialized.
    #   description - a String describing the flag.
    #   definition_file - a String describing the path to the file where this flag was defined.
    #   validators - a list of FlagValidator objects. Additional validators can be added after the flag is
    #       constructed, and all of the registered validators are checked whenever a flag assignment is
    #       performed.
    def initialize(type, name, default_value, description, definition_file, validators)
      @type = type
      @name = name
      @default_value = default_value
      @description = description
      @definition_file = definition_file
      @validators = validators
      self.value = default_value  # use the public setter method which performs type checking
      @is_explicit = false        # @is_explicit must be set to false AFTER calling the value= method
    end

    # Sets the value of the flag. The new_value argument can be a String or the appropriate type for the flag
    # (i.e. a Float for FloatFlag). If it's a String, an attempt will be made to convert to the correct type.
    def value=(new_value)
      new_value = value_from_string(new_value) if new_value.is_a?(String)
      validate!(new_value)
      @is_explicit = true
      @value = new_value
    end

    # Restores the default value of the flag.
    def restore_default()
      @is_explicit = false
      @value = @default_value
    end

    # Returns true if the flag has been explicitly set.
    alias :explicit? :is_explicit

    # Returns true if the flag has not been explicitly set.
    def default?; return !explicit?; end

    # Adds a new validator object to this flag and immediately validates the current value against it.
    def add_validator(validator)
      @validators.push validator
      validate!(@value)
    end

    private

    # Method for subclasses to implement that converts from a String argument to the flag's internal data
    # type. Subclasses may throw an ArgumentError if the input is malformed.  Subclasses return the string
    # itself if they cannot convert, which will be caught by the Class Validator
    def value_from_string(string)
      raise NotImplementedError, "Subclass must implement value_from_string()"
    end

    def validate!(value)
      @validators.each { |validator| validator.validate!(@name, value) }
    end
  end

  # A flag with a string value.
  class StringFlag < Flag
    def initialize(name, default_value, description, definition_file)
      super(:string, name, default_value, description, definition_file, [ClassValidator.new(String)])
    end

    private
    def value_from_string(string); return string.to_s; end
  end

  # A flag with a symbol value.
  class SymbolFlag < Flag
    def initialize(name, default_value, description, definition_file)
      super(:symbol, name, default_value, description, definition_file, [ClassValidator.new(Symbol)])
    end

    private
    def value_from_string(string); return string.to_sym; end
  end

  # A flag with an integer value.
  class IntFlag < Flag
    def initialize(name, default_value, description, definition_file)
      super(:int, name, default_value, description, definition_file,
          [ClassValidator.new(Integer, Bignum, Fixnum)])
    end

    private
    def value_from_string(string); Integer(string) rescue string; end
  end

  # A flag with a boolean value.
  class BoolFlag < Flag
    def initialize(name, default_value, description, definition_file)
      super(:bool, name, default_value, description, definition_file,
          [ClassValidator.new(TrueClass, FalseClass)])
    end

    private
    STRING_TO_BOOL_VALUE = { 'true' => true, 'false' => false }

    def value_from_string(string)
      result = STRING_TO_BOOL_VALUE[string.downcase]
      return result.nil? ? string : result
    end
  end

  # A flag with a floating-point numeric value.
  class FloatFlag < Flag
    def initialize(name, default_value, description, definition_file)
      super(:float, name, default_value, description, definition_file, [ClassValidator.new(Float)])
    end

    private
    def value_from_string(string); return Float(string) rescue string; end
  end
end
