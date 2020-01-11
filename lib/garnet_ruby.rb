# frozen_string_literal: true

require 'optparse'

def __grb_debug__?
  ENV['GARNET_DEBUG']
end

module GarnetRuby
  class Error < StandardError; end

  Q_UNDEF = Object.new

  def self.parse_options
    options = {}
    OptionParser.new do |opts|
      opts.banner = "Usage: garnet [switches] [--] [progfile] [arguments]"

      opts.on("-e 'command'", "one line of script. Several -e's allowed. Omit [programfile]") do |v|
        options[:scriptname] = '-e'
        if options[:source]
          options[:source] += "\n#{v}"
        else
          options[:source] = v
        end
      end

      opts.on("-v", "--version", "print the version number, then exit") do
        puts "garnet #{VERSION}"
        exit
      end

      opts.on("-h", "--help", "show this message") do
        puts opts
        exit
      end
    end.parse!
    if !options[:scriptname]
      if ARGV.empty?
        options[:scriptname] = '-'
        options[:source] = STDIN.read
      else
        scriptname = ARGV.shift
        options[:scriptname] = scriptname
        options[:source] = File.read(scriptname)
      end
    end
    options[:argv] = ARGV
    options
  end

  def self.run
    options = parse_options

    Core.init

    parser = Parser.new(options[:source], options[:scriptname])
    node = parser.parse
    if __grb_debug__?
      pp node
      puts '-----'
    end

    iseq = Iseq.new('<main>', :main)
    Compiler.new(iseq).compile_node(node)

    vm = VM.new
    Core.inject_env(vm)
    Core.inject_global_variables(vm)
    vm.running = true
    vm.execute_main(iseq)
  end
end

require 'garnet_ruby/version'

require 'garnet_ruby/core/basic'
require 'garnet_ruby/core/object'
require 'garnet_ruby/core/class'
require 'garnet_ruby/core/primitive'
require 'garnet_ruby/core/vm_eval'
require 'garnet_ruby/core/eval'
require 'garnet_ruby/core/error'
require 'garnet_ruby/core/numeric'
require 'garnet_ruby/core/enum'
require 'garnet_ruby/core/range'
require 'garnet_ruby/core/symbol'
require 'garnet_ruby/core/string'
require 'garnet_ruby/core/array'
require 'garnet_ruby/core/hash'
require 'garnet_ruby/core/regexp'
require 'garnet_ruby/core/method'
require 'garnet_ruby/core/block'
require 'garnet_ruby/core/proc'
require 'garnet_ruby/core/io'
require 'garnet_ruby/core/file'
require 'garnet_ruby/core/signal'
require 'garnet_ruby/core/process'
require 'garnet_ruby/core/core'

require 'garnet_ruby/compiler/parser'
require 'garnet_ruby/compiler/instruction'
require 'garnet_ruby/compiler/iseq'
require 'garnet_ruby/compiler/compiler'

require 'garnet_ruby/vm/environment'
require 'garnet_ruby/vm/control_frame'
require 'garnet_ruby/vm/vm'
