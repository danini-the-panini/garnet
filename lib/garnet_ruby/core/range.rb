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
  end

  module Core
    class << self
      def range_eqq(range, val)
        ret = range.include_internal(val)
        return ret unless ret == Q_UNDEF

        range.cover?(val)
      end
    end

    def self.init_range
      @cRange = rb_define_class(:Range, cObject)

      rb_define_method(cRange, :===, &method(:range_eqq))

      rb_define_method(cRange, :to_s) do |r|
        st_string = rb_funcall(r.st, :to_s)
        ed_string = rb_funcall(r.ed, :to_s)
        RString.from("#{st_string.string_value}#{r.excl ? '...' : '..'}#{ed_string.string_value}")
      end
    end
  end
end
