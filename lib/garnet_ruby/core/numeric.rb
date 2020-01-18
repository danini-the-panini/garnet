module GarnetRuby
  module Core
    class << self
      def fixnum?(value)
        value.numeric? && value.type?(Integer)
      end

      def modf(x)
        i = x.floor
        f = x - i
        [f, i]
      end

      def num2long(val)
        if val == Q_NIL
          raise TypeError, 'no implicit conversion from nil to integer'
        end

        return val.value if fixnum?(val)
        return RPrimitive.from(val.value.to_i) if val.type?(Float)

        num2long(rb_to_int(val))
      end

      def rb_to_int(val)
        val.to_integer(:to_int)
      end

      def int_to_s(x, *args)
        base = 10
        if args.length == 1
          base = num2long(args.first)
        end
        RString.from(x.value.to_s(base))
      end

      def int_odd_p(num)
        if fixnum?(num)
          return Q_TRUE if num.value.odd?
        elsif rb_funcall(num, :%, RPrimitive.from(2)) != RPrimitive.from(0)
          return Q_TRUE
        end
        Q_FALSE
      end

      def int_even_p(num)
        if fixnum?(num)
          return Q_TRUE if num.value.even?
        elsif rb_funcall(num, :%, RPrimitive.from(2)) == RPrimitive.from(0)
          return Q_TRUE
        end
        Q_FALSE
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
          Q_FALSE
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

      def num_cmp(x, y)
        return RPrimitive.from(0) if x == y
        Q_NIL
      end

      def int_chr(num)
        # TODO: encoding
        RString.from(num.value.chr)
      end

      def int_to_f(num)
        if fixnum?(num)
          RPrimitive.from(num.value.to_f)
        else
          rb_raise(eNotImpError, "Unknown subclass for to_f: #{num.klass}")
        end
      end

      def int_cmp(x, y)
        if fixnum?(x)
          fix_cmp(x, y)
        else
          Q_NIL
        end
      end

      def fix_cmp(x, y)
        return RPrimitive.from(0) if x == y

        if fixnum?(y)
          return RPrimitive.from(1) if x.value > y.value
          RPrimitive.from(-1)
        elsif y.type?(Flaot)
          integer_float_cmp(x, y)
        else
          num_coerce_cmp(x, y, :<=>)
        end
      end

      def integer_float_cmp(x, y)
        yd = y.value
        return Q_NIL if yd.nan?

        return RPrimitive.from(yd > 0.0 ? -1 : 1) if yd.infinite?

        yf, yi = modf(yd)
        xn = x.value
        return RPrimitive.from(-1) if xn < yi
        return RPrimitive.from(1) if xn > yi
        return RPrimitive.from(1) if yf < 0.0
        return RPrimitive.from(-1) if yf > 0.0
        RPrimitive.from(0)
      end

      def rb_cmperr(x, y)
        classname = if y.type?(Symbol) || y.type?(Float)
                      rb_funcall(y, :inspect)
                    else
                      y.klass
                    end
        rb_raise(eArgError, "comparison of #{x.klass} with #{classname} failed")
      end

      def coerce_failed(x, y)
        y = if y.type?(Symbol) || y.type?(Float)
              rb_funcall(y, :inspect)
            else
              y.klass
            end
        rb_raise(eTypeError, "#{y} can't be coerced into #{x.klass}")
      end

      def do_coerce(x, y, err)
        ary = rb_check_funcall(y, :coerce, x)
        if ary == Q_UNDEF
          coerce_failed if err
          return false
        end
        return false if !err && ary == Q_NIL

        if ary.is_a?(RArray) || ary.array_value.length != 2
          rb_raise(eTypeError, 'coerce must return [x, y]')
          return false
        end

        ary.array_value
      end

      def num_coerce_relop(x, y, func)
        coerse = do_coerce(x, y, false)

        if !coerse || (c = rb_funcall(coerse[0], func, coerse[1])) == Q_NIL
          rb_cmperr(x, y)
          return Q_NIL
        end
        c
      end

      def fix_gt(x, y)
        if fixnum?(y)
          return Q_TRUE if x.value > y.value

          Q_FALSE
        elsif y.type?(Float)
          integer_float_cmp(x, y).value == 1 ? Q_TRUE : Q_FALSE
        else
          num_coerce_relop(x, y, :>)
        end
      end

      def int_gt(x, y)
        if fixnum?(x)
          fix_gt(x, y)
        else
          Q_NIL
        end
      end

      def fix_ge(x, y)
        if fixnum?(y)
          return Q_TRUE if x.value >= y.value

          Q_FALSE
        elsif y.type?(Float)
          rel = integer_float_cmp(x, y)
          rel.value == 1 || rel.value.zero? ? Q_TRUE : Q_FALSE
        else
          num_coerce_relop(x, y, :>=)
        end
      end

      def int_ge(x, y)
        if fixnum?(x)
          fix_ge(x, y)
        else
          Q_NIL
        end
      end

      def fix_lt(x, y)
        if fixnum?(y)
          return Q_TRUE if x.value < y.value

          Q_FALSE
        elsif y.type?(Float)
          integer_float_cmp(x, y).value == -1 ? Q_TRUE : Q_FALSE
        else
          num_coerce_relop(x, y, :<)
        end
      end

      def int_lt(x, y)
        if fixnum?(x)
          fix_lt(x, y)
        else
          Q_NIL
        end
      end

      def fix_le(x, y)
        if fixnum?(y)
          return Q_TRUE if x.value <= y.value

          Q_FALSE
        elsif y.type?(Float)
          rel = integer_float_cmp(x, y)
          rel.value == -1 || rel.value.zero? ? Q_TRUE : Q_FALSE
        else
          num_coerce_relop(x, y, :<=)
        end
      end

      def int_le(x, y)
        if fixnum?(x)
          fix_le(x, y)
        else
          Q_NIL
        end
      end

      def rb_cmpint(val, a, b)
        if val == Q_NIL
          rb_cmperr(a, b)
        end

        if val.type?(Integer)
          l = val.value
          return 1  if l > 0
          return -1 if l < 0
          return 0
        end

        return 1  if rtest(rb_funcall(val, :>, PRimitive.from(0)))
        return -1 if rtest(rb_funcall(val, :<, PRimitive.from(0)))

        0
      end

      def fix_uminus(num)
        RPrimitive.from(-num.value)
      end

      def int_uminus(num)
        if fixnum?(num)
          fix_uminus(num)
        else
          Core.rb_funcall(num, :'-@')
        end
      end

      def int_plus(x, y)
        # TODO: type coersion
        RPrimitive.from(x.value + y.value)
      end

      def int_minus(x, y)
        # TODO: type coersion
        RPrimitive.from(x.value - y.value)
      end

      def int_mul(x, y)
        # TODO: type coersion
        RPrimitive.from(x.value * y.value)
      end

      def int_div(x, y)
        # TODO: type coersion
        RPrimitive.from(x.value / y.value)
      end

      def int_modulo(x, y)
        # TODO: type coersion
        RPrimitive.from(x.value % y.value)
      end

      def num_positive_int?(num)
        mid = :>

        if fixnum?(num) && rb_method_basic_definition?(cInteger, mid)
          return num.value.positive?
        end

        rtest(rb_num_compare_with_zero(num, mid))
      end

      def num_negative_int?(num)
        mid = :<

        if fixnum?(num) && rb_method_basic_definition?(cInteger, mid)
          return num.value.negative?
        end

        rtest(rb_num_compare_with_zero(num, mid))
      end

      def num_remainder(x, y)
        z = rb_funcall(x, :%, y)

        if (!rtest(rb_equal(z, RPrimitive.from(0)))) &&
          ((num_negative_int?(x) && num_positive_int?(y)) ||
           (num_positive_int?(x) && num_negative_int?(y)))

          return rb_funcall(z, :-, y)
        end

        z
      end

      def int_remainder(x, y)
        if fixnum?(x)
          num_remainder(x, y)
        else
          Q_NIL
        end
      end

      def int_pow(x, y)
        # TODO: type coersion
        RPrimitive.from(x.value ** y.value)
      end

      def fix_abs(fix)
        i = fix.value

        i = -i if i.negative?

        RPrimitive.from(i)
      end

      def int_abs(num)
        return fix_abs(num) if fixnum?(num)
        Q_NIL
      end

      def fix_comp(fix)
        return RPrimitive.from(~fix.value)
      end

      def int_comp(num)
        return fix_comp(num) if fixnum?(num)
        Q_NIL
      end

      def fix_and(x, y)
        if fixnum?(y)
          val = x.value & y.value
          return RPrimitive.from(val)
        end

        rb_num_coerce_bits(x, y, :&)
      end

      def int_and(x, y)
        return fix_and(x, y) if fixnum?(x)
        Q_NIL
      end

      def fix_or(x, y)
        if fixnum?(y)
          val = x.value | y.value
          return RPrimitive.from(val)
        end

        rb_num_coerce_bits(x, y, :&)
      end

      def int_or(x, y)
        return fix_or(x, y) if fixnum?(x)
        Q_NIL
      end

      def fix_xor(x, y)
        if fixnum?(y)
          val = x.value ^ y.value
          return RPrimitive.from(val)
        end

        rb_num_coerce_bits(x, y, :&)
      end

      def int_xor(x, y)
        return fix_xor(x, y) if fixnum?(x)
        Q_NIL
      end

      def int_lshift(x, y)
        # TODO: type coersion
        RPrimitive.from(x.value << y.value)
      end

      def int_rshift(x, y)
        # TODO: type coersion
        RPrimitive.from(x.value >> y.value)
      end

      def fix_size(fix)
        RPrimitive.from(fix.value.size)
      end

      def int_size(num)
        return fix_size(num) if fixnum?(num)

        Q_NIL
      end

      def int_upto(from, to)
        # TODO: return enumerator if no block given
        if fixnum?(from) && fixnum?(to)
          i = from.value
          loop do
            break unless i <= to.value
            rb_yield(RPrimitive.from(i))
            i += 1
          end
        else
          i = from
          c = nil

          loop do
            c = rb_funcall(i, :>, to)
            break if rtest(c)
            rb_yield(i)
            i = rb_funcall(i, :+, RPrimitive.from(1))
          end
          rb_cmperr(i, to) if c == Q_NIL
        end
        from
      end

      def int_downto(from, to)
        # TODO: return enumerator if no block given
        if fixnum?(from) && fixnum?(to)
          i = from.value
          
          loop do
            break unless i >= to.value
            rb_yield(RPrimitive.from(i))
            i -= 1
          end
        else
          i = from
          c = nil

          loop do
            c = rb_funcall(i, :<, to)
            break if rtest(c)
            rb_yield(i)
            i = rb_funcall(i, :-, RPrimitive.from(1))
          end
          rb_cmperr(i, to) if c == Q_NIL
        end
        from
      end

      def int_dotimes(num)
        # TODO: return enumerator if no block given

        if fixnum?(num)
          i = 0
          loop do
            break unless i < num.value
            rb_yield(RPrimitive.from(i))
            i += 1
          end
        else
          i = RPrimitive.from(0)

          loop do
            break unless rtest(rb_funcall(i, :<, num))
            rb_yield(i)
            i = rb_funcall(i, :+, RPrimitive.from(1))
          end
        end
        num
      end

      def int_hash(num)
        v = num.value
        RPrimitive.from(v ^ (v >> 32))
      end

      def float_to_s(flt)
        RString.from(flt.value.to_s)
      end

      def float_plus(x, y)
        if y.numeric?
          RPrimitive.from(x.value + y.value)
        else
          rb_num_coerce_bin(x, y, :+)
        end
      end

      def float_minus(x, y)
        if y.numeric?
          RPrimitive.from(x.value - y.value)
        else
          rb_num_coerce_bin(x, y, :-)
        end
      end

      def float_mul(x, y)
        if y.numeric?
          RPrimitive.from(x.value * y.value)
        else
          rb_num_coerce_bin(x, y, :*)
        end
      end

      def float_div(x, y)
        num = x.value
        if y.numeric?
          den = y.value.to_f
        else
          return rb_num_coerce_bin(x, y, :/)
        end

        ret = double_div_double(num, den)
        RPrimitive.from(ret)
      end

      def double_div_double(x, y)
        if y != 0.0
          x / y
        elsif x == 0.0
          Float::NAN
        else
          Float::INFINITY
        end
      end

      def float_mod(x, y)
        if y.numeric?
          RPrimitive.from(x.value % y.value)
        else
          rb_num_coerce_bin(x, y, :%)
        end
      end

      def float_eq(x, y)
        if fixnum?(y) || y.type?(Float)
          x.value == y.value ? Q_TRUE : Q_FALSE
        else
          num_equal(x, y)
        end
      end

      def float_gt(x, y)
        if y.numeric?
          x.value > y.value ? Q_TRUE : Q_FALSE
        else
          rb_num_coerce_relop(x, y, :>)
        end
      end

      def float_ge(x, y)
        if y.numeric?
          x.value >= y.value ? Q_TRUE : Q_FALSE
        else
          rb_num_coerce_relop(x, y, :>=)
        end
      end

      def float_lt(x, y)
        if y.numeric?
          x.value < y.value ? Q_TRUE : Q_FALSE
        else
          rb_num_coerce_relop(x, y, :<)
        end
      end

      def float_le(x, y)
        if y.numeric?
          x.value <= y.value ? Q_TRUE : Q_FALSE
        else
          rb_num_coerce_relop(x, y, :<=)
        end
      end

      def float_abs(num)
        RPrimitive.from(num.value.abs)
      end

      def float_floor(num, *args)
        if args.length.zero?
          RPrimitive.from(num.value.floor)
        else
          RPrimitive.from(num.value.floor(num2long(args.first)))
        end
      end

      def float_ceil(num, *args)
        if args.length.zero?
          RPrimitive.from(num.value.ceil)
        else
          RPrimitive.from(num.value.ceil(num2long(args.first)))
        end
      end

      def float_round(num, *args)
        # TODO: half kwarg
        if args.length.zero?
          RPrimitive.from(num.value.round)
        else
          RPrimitive.from(num.value.round(num2long(args.first)))
        end
      end

      def float_truncate(num, *args)
        if args.length.zero?
          RPrimitive.from(num.value.truncate)
        else
          RPrimitive.from(num.value.truncate(num2long(args.first)))
        end
      end
    end

    def self.init_numeric
      @cNumeric = rb_define_class(:Numeric, cObject)

      rb_define_method(cNumeric, :<=>, &method(:num_cmp))

      @cInteger = rb_define_class(:Integer, cNumeric)
      rb_define_method(cInteger, :to_s, &method(:int_to_s))
      rb_alias_method(cInteger, :inspect, :to_s)
      rb_define_method(cInteger, :odd?, &method(:int_odd_p))
      rb_define_method(cInteger, :even?, &method(:int_even_p))
      rb_define_method(cInteger, :upto, &method(:int_upto))
      rb_define_method(cInteger, :downto, &method(:int_downto))
      rb_define_method(cInteger, :times, &method(:int_dotimes))
      rb_define_method(cInteger, :chr, &method(:int_chr))
      rb_define_method(cInteger, :to_i) { |num| num }
      rb_define_method(cInteger, :to_f, &method(:int_to_f))
      rb_define_method(cInteger, :<=>, &method(:int_cmp))

      rb_define_method(cInteger, :'-@', &method(:int_uminus))
      rb_define_method(cInteger, :+, &method(:int_plus))
      rb_define_method(cInteger, :-, &method(:int_minus))
      rb_define_method(cInteger, :*, &method(:int_mul))
      rb_define_method(cInteger, :/, &method(:int_div))
      rb_define_method(cInteger, :%, &method(:int_modulo))
      rb_define_method(cInteger, :modulo, &method(:int_modulo))
      rb_define_method(cInteger, :remainder, &method(:int_remainder))
      rb_define_method(cInteger, :**, &method(:int_pow))

      rb_define_method(cInteger, :pow, &method(:int_pow))

      rb_define_method(cInteger, :abs, &method(:int_abs))
      rb_define_method(cInteger, :magnitude, &method(:int_abs))

      rb_define_method(cInteger, :===, &method(:int_equal))
      rb_define_method(cInteger, :==, &method(:int_equal))
      rb_define_method(cInteger, :>, &method(:int_gt))
      rb_define_method(cInteger, :>=, &method(:int_ge))
      rb_define_method(cInteger, :<, &method(:int_lt))
      rb_define_method(cInteger, :<=, &method(:int_le))
      rb_define_method(cInteger, :hash, &method(:int_hash))

      rb_define_method(cInteger, :~, &method(:int_comp))
      rb_define_method(cInteger, :&, &method(:int_and))
      rb_define_method(cInteger, :|, &method(:int_or))
      rb_define_method(cInteger, :'^', &method(:int_xor))

      rb_define_method(cInteger, :<<, &method(:int_lshift))
      rb_define_method(cInteger, :>>, &method(:int_rshift))

      rb_define_method(cInteger, :size, &method(:int_size))

      rb_define_const(cObject, :Fixnum, cInteger)

      @cFloat = rb_define_class(:Float, cNumeric)

      rb_define_method(cFloat, :to_s, &method(:float_to_s))
      rb_alias_method(cFloat, :inspect, :to_s)
      rb_define_method(cFloat, :+, &method(:float_plus))
      rb_define_method(cFloat, :-, &method(:float_minus))
      rb_define_method(cFloat, :*, &method(:float_mul))
      rb_define_method(cFloat, :/, &method(:float_div))
      rb_define_method(cFloat, :%, &method(:float_mod))
      rb_define_method(cFloat, :==, &method(:float_eq))
      rb_define_method(cFloat, :>, &method(:float_gt))
      rb_define_method(cFloat, :>=, &method(:float_ge))
      rb_define_method(cFloat, :<, &method(:float_lt))
      rb_define_method(cFloat, :<=, &method(:float_le))
      rb_define_method(cFloat, :abs, &method(:float_abs))

      rb_define_method(cFloat, :floor, &method(:float_floor))
      rb_define_method(cFloat, :ceil, &method(:float_ceil))
      rb_define_method(cFloat, :round, &method(:float_round))
      rb_define_method(cFloat, :truncate, &method(:float_truncate))
    end
  end
end
