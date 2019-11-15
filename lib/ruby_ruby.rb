# frozen_string_literal: true

module RubyRuby
  class Error < StandardError; end

  def self.run(source, filename)
    Core.init

    parser = Parser.new(source, filename)
    node = parser.parse
    pp node
    puts '-----'

    iseq = Iseq.new('<main>', :main)
    Compiler.new(iseq).compile_node(node)

    vm = VM.new
    vm.execute_main(iseq)
  end
end

require 'ruby_ruby/version'

require 'ruby_ruby/core/basic'
require 'ruby_ruby/core/object'
require 'ruby_ruby/core/class'
require 'ruby_ruby/core/primitive'
require 'ruby_ruby/core/numeric'
require 'ruby_ruby/core/symbol'
require 'ruby_ruby/core/string'
require 'ruby_ruby/core/array'
require 'ruby_ruby/core/method'
require 'ruby_ruby/core/io'
require 'ruby_ruby/core/core'

require 'ruby_ruby/compiler/parser'
require 'ruby_ruby/compiler/instruction'
require 'ruby_ruby/compiler/iseq'
require 'ruby_ruby/compiler/compiler'

require 'ruby_ruby/vm/environment'
require 'ruby_ruby/vm/control_frame'
require 'ruby_ruby/vm/vm'
