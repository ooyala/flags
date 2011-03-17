#!/usr/bin/env ruby

require "rubygems"
require "flags"

Flags.define_string(:flag, "default", "string flag")

Flags.init

puts Flags.flag
