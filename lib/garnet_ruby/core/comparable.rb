module GarnetRuby
  module Core
    class << self
      def rb_cmp(x, y)
        rb_funcall(x, :<=>, y)
      end

      def cmpint(x, y)
        rb_cmpint(rb_cmp(x, y), x, y)
      end

      def cmp_equal(x, y)
        return Q_TRUE if x == y

        c = rb_cmp(x, y)

        return Q_FALSE if c == Q_NIL
        return Q_TRUE if rb_cmpint(c, x, y) == 0

        Q_FALSE
      end

      def cmp_gt(x, y)
        return Q_TRUE if cmpint(x, y) > 0

        Q_FALSE
      end

      def cmp_ge(x, y)
        return Q_TRUE if cmpint(x, y) >= 0

        Q_FALSE
      end

      def cmp_lt(x, y)
        return Q_TRUE if cmpint(x, y) < 0

        Q_FALSE
      end

      def cmp_le(x, y)
        return Q_TRUE if cmpint(x, y) <= 0

        Q_FALSE
      end

      def cmp_between(x, min, max)
        return Q_FALSE if cmpint(x, min) < 0
        return Q_FALSE if cmpint(x, max) > 0

        Q_TRUE
      end

      def cmp_clamp(x, *args)
        min, max = args
        excl = false

        if args.length == 1
          range = min
          min, max, excl = range_values(range)
          unless min
            rb_raise(eTypeError, "wrong argument type #{range.klass.name} (expected Range)")
          end
          if max == Q_NIL
            rb_raise(eArgError, 'cannot clamp with an exclusive range') if excl
            if min != Q_NIL && cmpint(min, max) > 0
              rb_raise(eArgError, 'min argument must be smaller than max argument')
            end
          end
        elsif cmpint(min, max) > 0
          rb_raise(eArgError, 'min argument must be smaller than max argument')
        end

        if min != Q_NIL
          c = cmpint(x, min)
          return x if c == 0
          return min if c < 0
        end
        if max != Q_NIL
          c = cmpint(x, max)
          return max if c > 0
        end
        x
      end
    end

    def self.init_comparable
      @mComparable = rb_define_module(:Comparable)
      rb_define_method(mComparable, :==, &method(:cmp_equal))
      rb_define_method(mComparable, :>, &method(:cmp_gt))
      rb_define_method(mComparable, :>=, &method(:cmp_ge))
      rb_define_method(mComparable, :<, &method(:cmp_lt))
      rb_define_method(mComparable, :<=, &method(:cmp_le))
      rb_define_method(mComparable, :between?, &method(:cmp_between))
      rb_define_method(mComparable, :clamp, &method(:cmp_clamp))
    end
  end
end
