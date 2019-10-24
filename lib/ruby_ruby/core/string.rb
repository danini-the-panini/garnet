module RubyRuby
  class RString < RBasic
    attr_reader :value

    def initialize(value)
      @value = value
    end
  end
end
