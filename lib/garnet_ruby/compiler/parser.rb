require 'ruby_parser'

module GarnetRuby
  class Parser
    def initialize(source, filename)
      @source = source
      @filename = filename
      @ruby_parser = Ruby26Parser.new
    end

    def parse
      @ruby_parser.parse(@source, @filename) || s(:nil)
    end
  end
end
