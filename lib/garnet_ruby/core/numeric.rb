module GarnetRuby
  module Core
    class << self
      def fixnum?(value)
        value.is_a?(RPrimitive) && value.type?(Integer)
      end

      def modf(x)
        i = x.floor
        f = x - i
        [f, i]
      end

      def integer_float_eq(x, y)
        yd = y.value
        return Q_FALSE if yd.nan? || yd.infinite?

        yf, yi = modf(yd)
        return Q_FALSE unless yf.zero?
        return Q_TRUE if yi == x.value

        Q_FALSE
      end

      def num_equal(x, y)
        return Q_TRUE if x == y

        rtest(rb_funcall(y, :==, x))
      end

      def fix_equal(x, y)
        return Q_TRUE if x == y

        if fixnum?(y)
          return Q_FALSE
        elsif y.type?(Float)
          integer_float_eq(x, y)
        else
          num_equal(x, y)
        end
      end

      def int_equal(x, y)
        if fixnum?(x)
          fix_equal(x, y)
        else
          Q_NIL
        end
      end
    end

    def self.init_numeric
      @cNumeric = rb_define_class(:Numeric, cObject)

      @cInteger = rb_define_class(:Integer, cNumeric)
      rb_define_method(cInteger, :+) do |x, y|
        # TODO: type coersion
        RPrimitive.new(cInteger, 0, x.value + y.value)
      end
      rb_define_method(cInteger, :to_s) do |x, base = 10|
        RString.new(cString, 0, x.value.to_s(base))
      end
      rb_alias_method(cInteger, :inspect, :to_s)
      rb_define_method(cInteger, :===, &method(:int_equal))
      rb_define_method(cInteger, :==, &method(:int_equal))
    end
  end
end
