Flags - A Ruby Library for Simple Command-Line Flags
====================================================
Flags is a framework for Ruby which allows the definition of command-line flags, which are parsed in and can be accessed smartly from within your Ruby code.  This framework allows for numerous flag types and takes care of the process of type conversion and flag validation (type and value checking).

This flags framework is modeled after, and loosely resembles Google's, python-gflags library.  The advantage of these kinds of flags over other well-known libraries is the ability to define flags in the place at which they are used (libraries, utility files, setup files), rather than entirely in the main execution function of the calling program.

Usage
-----
Require the "flags" gem at the top of your file.  Then, define flags after require statements but before any other code. A flag with a given name may not be defined more than once, and doing so will raise an error. Examples:

    Flags.define_string(:my_string_flag, "default_value", "This is my comment for a string flag")
    Flags.define_symbol(:my_symbol_flag, :default_val, "This is my comment for a symbol flag")
    Flags.define_int(:my_int_flag, 1000, "This is my comment for an int flag")
    Flags.define_float(:my_float_flag, 2.0, "This is my comment for a float flag")
    Flags.define_bool(:my_bool_flag, true, "This is my comment for a bool flag")

In your main:

    if __FILE__ == $0
      Flags.init  # This will parse and consume all the flags from your command line that match a defined flag
    end

Run your file with some command-line flags:
    ./myfile -my_string_flag "foo" -my_int_flag 2

Note that specifying a boolean flag requires the word "true" or "false" following the flag name.

Then your code can access the flags any time after Flags.init with:
    Flags.my_string_flag and Flags.my_int_flag

Contributing
------------
Feel free to create tickets for enhancement ideas, or just fork and submit a pull request on our [GitHub page](https://github.com/ooyala/flags).  Note that this first distribution is pre-release code, and while it is stable, there is potential for significant changes in future releases.

License
-------
Licensed under the [MIT license](http://opensource.org/licenses/mit-license.php).

Credits
-------
Copyright © 2011 Ooyala, Inc.