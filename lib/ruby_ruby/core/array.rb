module RubyRuby
  class RArray < RBasic
    attr_reader :value

    def initialize(value)
      @value = value
    end
  end
end
