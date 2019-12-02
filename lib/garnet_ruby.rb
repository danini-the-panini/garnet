# frozen_string_literal: true

module GarnetRuby
  class Error < StandardError; end

  Q_UNDEF = Object.new

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

require 'garnet_ruby/version'

require 'garnet_ruby/core/basic'
require 'garnet_ruby/core/object'
require 'garnet_ruby/core/class'
require 'garnet_ruby/core/primitive'
require 'garnet_ruby/core/numeric'
require 'garnet_ruby/core/symbol'
require 'garnet_ruby/core/string'
require 'garnet_ruby/core/array'
require 'garnet_ruby/core/hash'
require 'garnet_ruby/core/method'
require 'garnet_ruby/core/block'
require 'garnet_ruby/core/io'
require 'garnet_ruby/core/core'

require 'garnet_ruby/compiler/parser'
require 'garnet_ruby/compiler/instruction'
require 'garnet_ruby/compiler/iseq'
require 'garnet_ruby/compiler/compiler'

require 'garnet_ruby/vm/environment'
require 'garnet_ruby/vm/control_frame'
require 'garnet_ruby/vm/vm'
