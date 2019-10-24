require 'ruby_parser'

module RubyRuby
  class Parser
    def initialize(source, filename)
      @source = source
      @filename = filename
      @ruby_parser = RubyParser.new
    end

    def parse
      @ruby_parser.parse(@source, @filename)
    end
  end
end
