module RubyRuby
  class RPrimitive < RBasic
    attr_reader :value

    def initialize(klass, flags, value)
      super(klass, flags)
      @value = value
    end

    def to_s
      "Q_#{value.inspect.upcase}"
    end
  end
end
