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

      def str_plus(str1, str2)
        str2 = str2.obj_as_string

        RString.from(str1.string_value + str2.string_value)
      end

      def str_times(str, times)
        len = num2long(times)
        if len.zero?
          return RString.from("")
        elsif len == 1
          return str
        end

        RString.from(str.string_value * len)
      end

      def str_aref_m(str, *args)
        if args.length == 2
          # TODO
        end
        str_aref(str, args.first)
      end

      def str_splice(str, beg, len, val)
        val = val.obj_as_string
        str.string_value[beg, len] = val.string_value
      end

      def str_aset(str, indx, val)
        if fixnum?(indx)
          idx = indx.value
        else
          # TODO: some other stuff

          result, beg, len = range_beg_len(indx, str.length, 1)
          if rtest(result)
            str_splice(str, beg, len, val)
            return val
          end

          idx = num2long(indx)
        end

        str_splice(str, idx, 1, val)
        val
      end

      def str_aset_m(str, *args)
        if args.length == 3
          # TODO
        end
        str_aset(str, args[0], args[1])
      end

      def str_length(str)
        RPrimitive.from(str.string_value.length)
      end

      def str_subpat(str, re)
        if re.match_pos(str).positive?
          return RString.from(backref_get.match_value[0])
        end
        Q_NIL
      end

      def str_aref(str, indx)
        if fixnum?(indx)
          idx = indx.value
        elsif indx.type?(Regexp)
          return RString.from(str_subpat(str, indx))
        elsif indx.type?(String)
          if str.string_value.include?(indx.string_value)
            return rb_str_dup(indx)
          end
          return Q_NIL
        else
          # TODO: check if indx is a range
        end

        RString.from(str.string_value[idx])
      end

      def str_to_f(str)
        RPrimitive.from(str.string_value.to_f)
      end

      def str_upcase(str)
        # TODO: options
        str = rb_str_dup(str)
        str_upcase_bang(str)
        str
      end

      def str_downcase(str)
        # TODO: options
        str = rb_str_dup(str)
        str_downcase_bang(str)
        str
      end

      def str_swapcase(str)
        # TODO: options
        str = rb_str_dup(str)
        str_swapcase_bang(str)
        str
      end

      def str_upcase_bang(str)
        # TODO: options
        str.string_value.upcase!
        str
      end

      def str_downcase_bang(str)
        # TODO: options
        str.string_value.downcase!
        str
      end

      def str_swapcase_bang(str)
        # TODO: options
        str.string_value.swapcase!
        str
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

      def rb_str_dup(str)
        RString.from(str.string_value.dup)
      end

      def str_sub(str, *args)
        str = rb_str_dup(str)
        str_sub_bang(str, *args)
        str
      end

      def str_gsub(str, *args)
        str = rb_str_dup(str)
        str_gsub_bang(str, *args)
        str
      end

      def str_sub_bang(str, *args)
        rb_str_sub(str, :sub!, *args)
      end

      def str_gsub_bang(str, *args)
        rb_str_sub(str, :gsub!, *args)
      end

      def rb_str_sub(str, mid, *args)
        mode = :string

        case args.length
        when 1
          # TODO: return enumerator
          mode = :iter
        when 2
          repl = args[1]
          hash = repl.check_hash_type
          if hash == Q_NIL
            repl = repl.string_value
          else
            mode = :map
          end
        else
          # TODO: arity error
        end

        pat = args.first
        tmp = pat.check_string_type
        if tmp == Q_NIL
          raise ArgumentError unless pat.is_a?(RRegexp)
          pat = pat.regexp_value
        else
          pat = tmp.string_value
        end

        case mode
        when :string
          str.string_value.__send__(mid, pat, repl)
          backref_set(RMatch.from($~))
        when :map
          str.string_value.__send__(mid, pat) do |s|
            backref_set(RMatch.from($~))
            val = hash_aref(hash, RString.from(s))
            val = val.obj_as_string.string_value
          end
        when :iter
          str.string_value.__send__(mid, pat) do |s|
            backref_set(RMatch.from($~))
            rb_yield(RString.from(s)).obj_as_string.string_value
          end
        end

        str
      end

      def str_tr(str, src, repl)
        str = rb_str_dup(str)
        str_tr_bang(str, src, repl)
        str
      end

      def str_tr_s(str, src, repl)
        str = rb_str_dup(str)
        str_tr_s_bang(str, src, repl)
        str
      end

      def str_delete(str, *args)
        str = rb_str_dup(str)
        str_delete_bang(str, *args)
        str
      end

      def str_squeeze(str, *args)
        str = rb_str_dup(str)
        str_squeeze_bang(str, *args)
        str
      end

      def str_tr_bang(str, src, repl)
        src = src.obj_as_string
        repl = repl.obj_as_string
        RString.from(str.string_value.tr!(src.string_value, repl.string_value))
      end

      def str_tr_s_bang(str, src, repl)
        src = src.obj_as_string
        repl = repl.obj_as_string
        RString.from(str.string_value.tr_s!(src.string_value, repl.string_value))
      end

      def str_delete_bang(str, *args)
        RString.from(str.string_value.delete!(*args.map { |a| a.obj_as_string.string_value }))
      end

      def str_squeeze_bang(str, *args)
        RString.from(str.string_value.squeeze!(*args.map { |a| a.obj_as_string.string_value }))
      end

      def str_each_byte(str)
        # TODO: return enumerator
        str.string_value.each_byte do |byte|
          rb_yield(RPrimitive.from(byte))
        end
        str
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
      rb_define_method(cString, :+, &method(:str_plus))
      rb_define_method(cString, :*, &method(:str_times))
      rb_define_method(cString, :[], &method(:str_aref_m))
      rb_define_method(cString, :[]=, &method(:str_aset_m))
      rb_define_method(cString, :length, &method(:str_length))
      rb_define_method(cString, :size, &method(:str_length))

      rb_define_method(cString, :to_f, &method(:str_to_f))
      rb_define_method(cString, :to_s) { |x| x }
      rb_define_method(cString, :inspect) do |x|
        RString.from(x.string_value.inspect)
      end

      rb_define_method(cString, :upcase, &method(:str_upcase))
      rb_define_method(cString, :downcase, &method(:str_downcase))
      rb_define_method(cString, :swapcase, &method(:str_swapcase))

      rb_define_method(cString, :upcase!, &method(:str_upcase_bang))
      rb_define_method(cString, :downcase!, &method(:str_downcase_bang))
      rb_define_method(cString, :swapcase!, &method(:str_swapcase_bang))

      rb_define_method(cString, :split, &method(:str_split))
      rb_define_method(cString, :reverse, &method(:str_reverse))
      rb_define_method(cString, :reverse!, &method(:str_reverse_bang))

      rb_define_method(cString, :scan, &method(:str_scan))

      rb_define_method(cString, :sub, &method(:str_sub))
      rb_define_method(cString, :gsub, &method(:str_gsub))

      rb_define_method(cString, :sub!, &method(:str_sub_bang))
      rb_define_method(cString, :gsub!, &method(:str_gsub_bang))

      rb_define_method(cString, :tr, &method(:str_tr))
      rb_define_method(cString, :tr_s, &method(:str_tr_s))
      rb_define_method(cString, :delete, &method(:str_delete))
      rb_define_method(cString, :squeeze, &method(:str_squeeze))

      rb_define_method(cString, :tr!, &method(:str_tr_bang))
      rb_define_method(cString, :tr_s!, &method(:str_tr_s_bang))
      rb_define_method(cString, :delete!, &method(:str_delete_bang))
      rb_define_method(cString, :squeeze!, &method(:str_squeeze_bang))
      
      rb_define_method(cString, :each_byte, &method(:str_each_byte))
    end
  end
end
