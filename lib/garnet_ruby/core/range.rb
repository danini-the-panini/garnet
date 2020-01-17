module GarnetRuby
  class RRange < RObject
    attr_reader :st, :ed, :excl

    def initialize(klass, flags, st, ed, excl)
      super(klass, flags)
      @st = st
      @ed = ed
      @excl = excl
    end

    def self.from(value)
      return Q_NIL if value.nil?

      st = Core.ruby2garnet(value.begin)
      ed = Core.ruby2garnet(value.end)
      make(st, ed, value.exclude_end?)
    end

    def self.make(st, ed, excl)
      new(Core.cRange, [], st, ed, excl)
    end

    def include_internal(val)
      Q_UNDEF # TODO
    end

    def cover?(val)
      if !st == Q_NIL || r_less(@st, val) <= 0
        ex = @excl ? 1 : 0
        return Q_TRUE if @ed == Q_NIL || r_less(val, @ed) <= -ex
      end
      Q_FALSE
    end

    def r_less(a, b)
      r = Core.rb_funcall(a, :<=>, b)
      return 9999999 if r == Q_NIL # TODO: INT_MAX

      Core.rb_cmpint(r, a, b)
    end

    def each_func(arg)
      vm = VM.instance

      b = @st
      e = @ed
      v = b

      if excl
        loop do
          break unless r_less(v, e) < 0
          break if yield(v, arg)

          v = Core.rb_funcall(v, :succ)
        end
      else
        loop do
          c = r_less(v, e)
          break unless c <= 0
          break if yield(v, arg)
          break if c.zero?

          v = Core.rb_funcall(v, :succ)
        end
      end
    end
  end

  module Core
    class << self
      def range_eqq(range, val)
        ret = range.include_internal(val)
        return ret unless ret == Q_UNDEF

        range.cover?(val)
      end

      def each_i(v, arg)
        rb_yield(v)
        false
      end

      def sym_each_i(v, arg)
        rb_yield(RSymbol.from(v.to_sym))
        false
      end

      def range_each(range)
        vm = VM.instance
        beg, ed = range.st, range.ed

        if beg.type?(Integer) && ed == Q_NIL
          i = beg.value
          
          loop do
            vm.rb_yield(RPrimitive.from(i))
            i += 1
          end
        elsif beg.type?(Integer) && ed.type?(Integer)
          i = beg.value
          lim = ed.value
          lim +=1 unless range.excl
          loop do
            break if i >= lim
            vm.rb_yield(RPrimitive.from(i))
            i += 1
          end
        elsif beg.is_a?(RSymbol) && (ed == Q_NIL || d.is_a?(RSymbol))
          beg = beg.sym2str
          if ed == Q_NIL
            # TODO: not implented
            rb_str_upto_endless_each(beg, nil, &method(:sym_each_i))
          else
            # TODO: not implented
            rb_str_upto_each(beg, ed.sym2str, range.excl, nil, &method(:sym_each_i))
          end
        else
          tmp = beg.check_string_type

          if tmp != Q_NIL
            if ed != Q_NIL
              # TODO: not implented
              rb_str_upto_each(tmp, ed, range.excl, nil, &method(:each_i))
            else
              # TODO: not implented
              rb_str_upto_endless_each(tmp, nil, &method(:each_i))
            end
          else
            if !beg.discrete_object?
              raise TypeError, "can't iterate from #{beg.klass}"
            end
            if ed != Q_NIL
              range.each_func(nil, &method(:each_i))
            else
              loop do
                vm.rb_yield(beg)
                beg = Core.rb_funcall(beg, :succ)
              end
            end
          end
        end
      end

      def range_begin(range)
        range.st
      end

      def range_end(range)
        range.ed
      end

      def range_to_a(range)
        if range.ed == Q_NIL
          raise RangeError, 'cannot convert endless range to an array'
        end

        rb_call_super
      end

      def range_to_s(r)
        st_string = rb_funcall(r.st, :to_s).string_value
        ed_string = rb_funcall(r.ed, :to_s).string_value
        RString.from("#{st_string}#{r.excl ? '...' : '..'}#{ed_string}")
      end

      def range_exclude_end_p(range)
        range.excl ? Q_TRUE : Q_FALSE
      end

      def range_values(range)
        if obj_is_kind_of(range, cRange)
          return range.st, range.ed, range.excl

          # TODO: check against ArithSeq ??
        else
          b = rb_check_funcall(range, :begin)
          return false, nil, nil if b == Q_UNDEF
          e = rb_check_funcall(range, :end)
          return false, nil, nil if e == Q_UNDEF
          x = rb_check_funcall(range, :exclude_end?)
          return false, nil, nil if x == Q_UNDEF

          return b, e, x
        end
      end

      def range_beg_len(range, len, err)
        b, e, excl = range_values(range)
        return Q_FALSE, nil, nil unless b

        beg = b == Q_NIL ? 0 : num2long(b)
        ed = e == Q_NIL ? -1 : num2long(e)
        origbeg = beg
        origend = ed
        if beg.negative?
          beg += len
          out_of_range(origbeg, origend, excl, err) if beg.negative?
        end
        ed += len if ed.negative?
        ed += 1 unless excl
        if err.zero? || err == 2
          out_of_range(origbeg, origend, excl, err) if beg > len
          ed = len if ed > len
        end
        len = ed - beg
        len = 0 if len.negative?

        return Q_TRUE, beg, len
      end

      def out_of_range(beg, ed, excl, err=1)
        return if err.zero?
        raise RangeError, "#{beg}#{excl ? '...' : '..'}#{ed} out of range"
      end
    end

    def self.init_range
      @cRange = rb_define_class(:Range, cObject)
      cRange.include_module(mEnumerable)

      rb_define_method(cRange, :===, &method(:range_eqq))
      rb_define_method(cRange, :each, &method(:range_each))
      rb_define_method(cRange, :begin, &method(:range_begin))
      rb_define_method(cRange, :end, &method(:range_end))
      rb_define_method(cRange, :to_a, &method(:range_to_a))
      rb_define_method(cRange, :entries, &method(:range_to_a))
      rb_define_method(cRange, :to_s, &method(:range_to_s))

      rb_define_method(cRange, :exclude_end?, &method(:range_exclude_end_p))
    end
  end
end
