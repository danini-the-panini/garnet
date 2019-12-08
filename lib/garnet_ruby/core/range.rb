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
  end

  module Core
    def self.init_range
      @cRange = rb_define_class(:Range, cObject)

      rb_define_method(cRange, :to_s) do |r|
        st_string = rb_funcall(r.st, :to_s)
        ed_string = rb_funcall(r.ed, :to_s)
        RString.from("#{st_string.string_value}#{r.excl ? '...' : '..'}#{ed_string.string_value}")
      end
    end
  end
end
