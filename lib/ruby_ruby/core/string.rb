module RubyRuby
  class RString < RBasic
    attr_reader :string_value

    def initialize(klass, flags, string_value)
      super(klass, flags)
      @string_value = string_value
    end
  end
end
