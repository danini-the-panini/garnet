# frozen_string_literal: true

module RubyRuby
  class Error < StandardError; end

  def self.run(input, filename)
    tokens = Lexer.new(input, filename).tokens
    ast = Parser.new(tokens).parse
  end
end

require "ruby_ruby/version"
require "ruby_ruby/lexer"
require "ruby_ruby/parser"