module GarnetRuby
  class RPrimitive < RBasic
    attr_reader :value

    def initialize(klass, flags, value)
      super(klass, flags)
      @value = value
    end

    def ==(other)
      return true if self == other
      value.eql?(other)
    end

    def to_s
      "Q_#{value.inspect.upcase}"
    end

    def inspect
      "<##{klass}:#{value}>"
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

    def numeric?
      type?(Integer) || type?(Float)
    end

    def self.from(value)
      klass = case value
              when NilClass then Q_NIL
              when TrueClass then Q_TRUE
              when FalseClass then Q_FALSE
              when Integer then Core.cInteger
              when Float then Core.cFloat
              else
                raise "unsupported primitive (#{value.class})"
              end

      new(klass, [], value)
    end
  end
end
