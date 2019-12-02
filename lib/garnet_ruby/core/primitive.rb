module GarnetRuby
  class RPrimitive < RBasic
    attr_reader :value

    def initialize(klass, flags, value)
      super(klass, flags)
      @value = value
    end

    def to_s
      "Q_#{value.inspect.upcase}"
    end

    def ==(other)
      return false unless other.is_a?(RPrimitive)
      return unless other.type?(type)

      value == other.value
    end

    def type
      value.class
    end

    def type?(t)
      value.is_a?(t)
    end
  end
end
