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
      def empty_str_alloc(klass)
        RString.new(klass, [], "")
      end

      def str_cmp(str1, str2)
        str1.string_value <=> str2.string_value
      end

      def str_cmp_m(str1, str2)
        s = str2.check_string_type
        return invcmp(str1, str2) if s == Q_NIL

        result = str_cmp(str1, s)
        RPrimitive.from(result)
      end

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

      def str_to_f(str)
        RPrimitive.from(str.string_value.to_f)
      end

      def str_split(str, *args)
        limit = nil
        if args.length == 2
          limit = num2long(args[1])
        end
        
        pattern = args.empty? ? VM.instance.get_global(:'$;') : args[0]
        if pattern.type?(String)
          pattern = pattern.string_value
        elsif pattern.type?(Regexp)
          pattern = pattern.regexp_value
        elsif pattern == Q_NIL
          pattern = ' '
        else
          raise TypeError, "(wrong argument type #{pattern.klass} (expected Regexp))"
        end

        split_args = [pattern, limit].compact

        if rb_block_given?
          str.string_value.split(*split_args) do |x|
            rb_yield(RString.from(x))
          end
          str
        else
          result = str.string_value.split(*split_args)
          RArray.from(result)
        end
      end

      def str_reverse_bang(str)
        str.string_value.reverse!
        str
      end

      def str_reverse(str)
        RString.from(str.string_value.reverse)
      end

      def str_scan(str, pattern)
        if pattern.type?(String)
          pattern = pattern.string_value
        elsif pattern.type?(Regexp)
          pattern = pattern.regexp_value
        else
          raise TypeError, "(wrong argument type #{pattern.klass} (expected Regexp))"
        end

        if rb_block_given?
          str.string_value.scan(pattern) do |x|
            if x.is_a?(Array)
              rb_yield(RArray.from(x))
            else
              rb_yield(RString.from(x))
            end
          end
          str
        else
          result = str.string_value.scan(pattern)
          RArray.from(result)
        end
      end

      def rb_sprintf(str, *args)
        str.format(*args)
      end
    end

    def self.init_string
      @cString = rb_define_class(:String)
      rb_define_alloc_func(cString, &method(:empty_str_alloc))

      rb_define_method(cString, :<=>, &method(:str_cmp_m))
      rb_define_method(cString, :==, &method(:str_equal))
      rb_define_method(cString, :===, &method(:str_equal))
      rb_define_method(cString, :eql?, &method(:str_eql))
      rb_define_method(cString, :hash, &method(:str_hash))

      rb_define_method(cString, :to_f, &method(:str_to_f))
      rb_define_method(cString, :to_s) { |x| x }
      rb_define_method(cString, :inspect) do |x|
        RString.from(x.string_value.inspect)
      end

      rb_define_method(cString, :split, &method(:str_split))
      rb_define_method(cString, :reverse, &method(:str_reverse))
      rb_define_method(cString, :reverse!, &method(:str_reverse_bang))

      rb_define_method(cString, :scan, &method(:str_scan))
    end
  end
end
