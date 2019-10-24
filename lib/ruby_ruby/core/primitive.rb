module RubyRuby
  class RPrimitive < RBasic
    attr_reader :value

    def initialize(klass, flags, value)
      super(klass, flags)
      @value = value
    end
  end
end
