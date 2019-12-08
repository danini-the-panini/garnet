module GarnetRuby
  class RString < RObject
    attr_reader :string_value

    def initialize(klass, flags, string_value)
      super(klass, flags)
      @string_value = string_value
    end

    def to_s
      string_value.inspect
    end

    def self.from(str)
      return Q_NIL if str.nil?

      new(Core.cString, [], str)
    end

    def subseq(beg, len)
      string_value[beg, len]
    end

    def length
      string_value.length
    end
  end

  module Core
    def self.init_string
      @cString = rb_define_class(:String)

      rb_define_method(cString, :to_s) { |x| x }
      rb_define_method(cString, :inspect) do |x|
        RString.from(x.string_value.inspect)
      end
    end
  end
end
