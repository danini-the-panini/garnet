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

    def type
      String
    end

    def type?(x)
      x == String
    end

    def subseq(beg, len)
      string_value[beg, len]
    end

    def length
      string_value.length
    end

    def eql_internal(str2)
      string_value == str2.string_value ? Q_TRUE : Q_FALSE
    end

    def format(*args)
      fmt_args = args.map do |arg|
        case arg
        when RPrimitive
          arg.value
        when RString
          arg.string_value
        else
          Core.rb_funcall(arg, :to_s).string_value
        end
      end
      RString.from(string_value % fmt_args)
    end
  end

  module Core
    class << self
      def str_equal(str1, str2)
        return Q_TRUE if str1 == str2

        unless str2.is_a?(RString)
          return Q_FALSE unless rb_respond_to?(str2, :to_str)
          return rb_equal(str1, str2)
        end

        str1.eql_internal(str2)
      end

      def str_eql(str1, str2)
        return Q_TRUE if str1 == str2
        return Q_FALSE unless str2.type?(String)

        str1.eql_internal(str2)
      end

      def str_hash(str)
        result = str.string_value.bytes.reduce(0) do |h, c|
          31 * h + c
        end
        RPrimitive.from(result)
      end

      def rb_sprintf(str, *args)
        str.format(*args)
      end
    end

    def self.init_string
      @cString = rb_define_class(:String)

      rb_define_method(cString, :==, &method(:str_equal))
      rb_define_method(cString, :===, &method(:str_equal))
      rb_define_method(cString, :eql?, &method(:str_eql))
      rb_define_method(cString, :hash, &method(:str_hash))

      rb_define_method(cString, :to_s) { |x| x }
      rb_define_method(cString, :inspect) do |x|
        RString.from(x.string_value.inspect)
      end
    end
  end
end
