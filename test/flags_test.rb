# Copyright © 2011 Ooyala, Inc.
# Tests for flags.rb - To run, execute ruby test/flags_test.rb from the root gem directory
require "rubygems"
require "shoulda"
require "mocha"

require "flags"

class FlagsTest < Test::Unit::TestCase
  # Tests for undefine functionality used in the teardown block of all other tests. We want to make sure
  # those work before running any other tests, so these tests are purposefully placed outside a context.
  # Notice that these tests manually do their own teardown.
  def test_undefine_flag
    assert_raise(NoMethodError) { Flags.my_flag_name }
    Flags.define_int_flag(:my_flag_name, 42, "Description")
    assert_equal 42, Flags.my_flag_name
    Flags.send(:undefine_flag, :my_flag_name)
    assert_raise(NoMethodError) { Flags.my_flag_name }
  end

  def test_access_flag_names
    flag_names = Flags.send(:class_variable_get, "@@flags").map { |name, flag| name }
    assert_equal 0, flag_names.size
    Flags.define_int_flag(:my_flag_name, 42, "Description")
    flag_names = Flags.send(:class_variable_get, "@@flags").map { |name, flag| name }
    assert_equal [ :my_flag_name ], flag_names
    Flags.send(:undefine_flag, :my_flag_name)
  end

  context "Flags" do
    teardown do  # Undefine all flags after running a test
      flag_names = Flags.send(:class_variable_get, "@@flags").map { |name, flag| name }
      flag_names.each do |flag_name|
        Flags.send(:undefine_flag, flag_name)
      end
    end

    should "define_string_flag" do
      Flags.define_string_flag(:foo, "bar", "Test string flag")
      assert_equal "bar", Flags.foo
    end

    should "define_symbol_flag" do
      Flags.define_symbol_flag(:foo, :bar, "Test symbol flag")
      Flags.define_symbol_flag(:foo2, "baz", "Test symbol flag from string conversion")
      assert_equal :bar, Flags.foo
      assert_equal :baz, Flags.foo2
    end

    should "define_int_flag" do
      Flags.define_int_flag(:bar, 1, "Test int flag")
      Flags.define_int_flag(:baz, "2", "Test int flag from string conversion")
      assert_equal 1, Flags.bar
      assert_equal 2, Flags.baz
    end

    should "define_bool_flag" do
      Flags.define_bool_flag(:true_bool_flag, true, "Test true bool flag")
      Flags.define_bool_flag(:false_bool_flag, false, "Test false bool flag")
      Flags.define_bool_flag(:true_bool_flag2, "true", "Test true bool flag from string conversion")
      Flags.define_bool_flag(:false_bool_flag2, "false", "Test false bool flag from string conversion")
      assert Flags.true_bool_flag
      assert Flags.true_bool_flag2
      assert !Flags.false_bool_flag
      assert !Flags.false_bool_flag2
    end

    should "define_float_flag" do
      Flags.define_float_flag(:float_flag, 2.0, "Test float flag")
      Flags.define_float_flag(:float_flag2, "3.0", "Test float flag from string conversion")
      assert_equal 2.0, Flags.float_flag
      assert_equal 3.0, Flags.float_flag2
    end

    should "return flag comment" do
      Flags.define_string_flag(:foo, "foobar", "Test string flag")
      assert_equal "Test string flag", Flags.flags_get_comment(:foo)
    end

    should "return default value" do
      Flags.define_string_flag(:foo, "foobar", "Test string flag")
      Flags.foo = "baz"
      assert_equal "baz", Flags.foo
      assert_equal "foobar", Flags.flags_get_default_value(:foo)
    end

    should "initialize flags with init" do
      Flags.define_float_flag(:bar, 2.0, "")
      Flags.define_string_flag(:foo, "foobar", "")
      Flags.define_int_flag(:baz, 3, "")
      Flags.init(["-bar", 3.0, "-foo", "you rock"])
      assert_equal 3.0, Flags.bar
      assert_equal "you rock", Flags.foo
      assert_equal 3, Flags.baz
    end

    should "remove known flags from args array but leave non-flags alone" do
      Flags.define_int_flag(:foo, 41, "")
      args = [ "-foo", "42", "hello world" ]
      Flags.init(args)
      assert_equal [ "hello world" ], args
    end

    should "init bool flag with true default" do
      Flags.define_bool_flag(:bar, true, "")
      Flags.init(["-bar", false])
      assert !Flags.bar
    end

    should "init bool flag with true default and string initial value" do
      Flags.define_bool_flag(:bar, true, "")
      Flags.init(["-bar", "false"])
      assert !Flags.bar
    end

    should "pick last flag value when multiple args are present" do
      Flags.define_bool_flag(:bar, true, "")
      Flags.define_int_flag(:baz, 3, "")
      Flags.init(["-bar", "false", "-baz", 4, "-bar", "true", "-baz" , 5])
      assert Flags.bar
      assert_equal 5, Flags.baz
    end

    should "serialize to string" do
      Flags.define_float_flag(:bar, 2.0, "bla")
      Flags.define_string_flag(:baz, "you rock", "comment \"bla\" 'bla'")
      Flags.define_int_flag(:foo, 3, "")
      Flags.define_bool_flag(:bool, true, "")
      assert_equal "-bar 2.0 -baz \"you rock\" -bool true -foo 3", Flags.to_s
    end

    should "override the default state  flags with init" do
      Flags.define_float_flag(:bar, 2.0, "")
      Flags.define_string_flag(:foo, "foobar", "")
      Flags.define_int_flag(:baz, 3, "")
      Flags.init(["-bar", 3.0, "-foo", "you rock"])
      assert_equal 3.0, Flags.bar
      assert_equal "you rock", Flags.foo
      assert_equal 3, Flags.baz
    end

    should "serialize to/from yaml" do
      Flags.define_float_flag(:bar, 2.0, "")
      Flags.define_string_flag(:foo, "foobar", "")
      args = Flags.args_from_yaml Flags.to_yaml
      assert_equal ["-bar", 2.0, "-foo", "foobar"], args
    end

    context "default values" do
      should "flags_is_default should return true initially" do
        Flags.define_int_flag(:foo, 42, "")
        assert Flags.flags_is_default(:foo)
      end

      should "flags_is_default should return false after flag assignment" do
        Flags.define_int_flag(:foo, 42, "")
        Flags.foo = 43
        assert !Flags.flags_is_default(:foo)
      end

      should "flags_is_default should return false after loading flags from command line" do
        Flags.define_int_flag(:foo, 42, "")
        Flags.define_int_flag(:bar, 43, "")
        Flags.init(["-foo", "41"])
        assert !Flags.flags_is_default(:foo)
        assert Flags.flags_is_default(:bar)
      end

      should "set_if_default should change default value" do
        Flags.define_int_flag(:foo, 42, "")
        Flags.set_if_default(:foo, 43)
        assert_equal 43, Flags.foo
        assert !Flags.flags_is_default(:foo)
      end

      should "set_if_default should not change non-default value" do
        Flags.define_int_flag(:foo, 42, "")
        Flags.foo = 41
        Flags.set_if_default(:foo, 43)
        assert_equal 41, Flags.foo
      end

      should "restore default value" do
        Flags.define_int_flag(:foo, 42, "")
        Flags.foo = 41
        Flags.restore_default(:foo)
        assert_equal 42, Flags.foo
        assert Flags.flags_is_default(:foo)
      end

      should "restore all default values" do
        Flags.define_int_flag(:foo, 42, "")
        Flags.define_int_flag(:bar, 43, "")
        Flags.foo, Flags.bar = 41, 40
        Flags.restore_all_defaults()
        assert_equal 42, Flags.foo
        assert_equal 43, Flags.bar
        assert Flags.flags_is_default(:foo) && Flags.flags_is_default(:bar)
      end
    end

    context "flag validators" do
      should "fail expected class validation" do
        Flags.define_int_flag(:foo, 1, "...")
        assert_raise(Flags::InvalidFlagValueError) { Flags.foo = "not an int" }
        Flags.define_float_flag(:bar, 1.0, "...")
        assert_raise(Flags::InvalidFlagValueError) { Flags.bar = 1 }
        Flags.define_bool_flag(:baz, true, "...")
        assert_raise(Flags::InvalidFlagValueError) { Flags.baz = :hi_there }
        # Converting an empty string to a symbol is an error in Ruby 1.8 but not 1.9
        if RUBY_VERSION[0..2] == '1.8'
          Flags.define_symbol_flag(:boo, :a, "...")
          assert_raise(ArgumentError) { Flags.boo = "" }
        end
        Flags.define_string_flag(:faz, "hello world", "...")
        assert_raise(Flags::InvalidFlagValueError) { Flags.faz = 123 }
      end

      should "register numeric range validators" do
        # A range open on the 'max' end
        Flags.define_int_flag(:foo, 1, "Must be greater than or equal to 0")
        positive_infinity = 1.0 / 0  # TODO: is there a better way to get a reference to the Infinity constant?
        Flags.register_range_validator(:foo, 0..positive_infinity)
        Flags.foo = 2 ** 128
        Flags.foo = 0
        assert_raise(Flags::InvalidFlagValueError) { Flags.foo = -1 }
        assert_equal 0, Flags.foo

        # A range open on the 'min' end
        Flags.define_int_flag(:bar, -1, "Must be less than or equal to 0")
        negative_infinity = -1.0 / 0
        Flags.register_range_validator(:bar, negative_infinity..0)
        Flags.bar = -2 ** 127
        Flags.bar = 0
        assert_raise(Flags::InvalidFlagValueError) { Flags.bar = 1 }
        assert_equal 0, Flags.bar

        # A range closed on both ends
        Flags.define_int_flag(:boo, 0, "Must be between -2 and 2")
        Flags.register_range_validator(:boo, -2..2)
        Flags.boo = -2
        Flags.boo = 2
        assert_raise(Flags::InvalidFlagValueError) { Flags.boo = -3 }
        assert_raise(Flags::InvalidFlagValueError) { Flags.boo = 3 }
        assert_equal 2, Flags.boo
      end

      should "register allowed values validator" do
        Flags.define_symbol_flag(:foo, :north, "Can be one of [:north, :south, :east, :west]")
        Flags.register_allowed_values_validator(:foo, [:north, :south, :east, :west])
        assert_raise(Flags::InvalidFlagValueError) { Flags.foo = :up }
        # One more time and use the variable args version this time
        Flags.define_string_flag(:bar, "left", "Can be one of (left, right)")
        Flags.register_allowed_values_validator(:bar, "left", "right")
        assert_raise(Flags::InvalidFlagValueError) { Flags.bar = "down" }
      end

      should "register disallowed values validator" do
        Flags.define_symbol_flag(:foo, :company, "Cannot be any of [:competitor1, :competitor2]")
        Flags.register_disallowed_values_validator(:foo, [:competitor1, :competitor2])
        Flags.foo = :client
        assert_raise(Flags::InvalidFlagValueError) { Flags.foo = :competitor1 }
        assert_equal :client, Flags.foo
      end

      should "register custom validator" do
        Flags.define_int_flag(:even_number, 2, "Even numbers only!")
        Flags.register_custom_validator(:even_number,
            Proc.new { |flag_value| flag_value % 2 == 0 },
            "Flag value must be an even integer")
        Flags.even_number = 10
        assert_raise(Flags::InvalidFlagValueError) { Flags.even_number = 11 }
        assert_equal 10, Flags.even_number
      end
    end
  end
end
