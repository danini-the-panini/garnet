module GarnetRuby
  class RArray < RObject
    attr_reader :array_value

    def initialize(klass, flags, array_value)
      super(klass, flags)
      @array_value = array_value
    end

    def to_s
      "[#{array_value.map(&:to_s).join(', ')}]"
    end

    def self.from(ary)
      return Q_NIL if ary.nil?

      new(Core.cArray, [], ary.map { |x| Core.ruby2garnet(x) })
    end

    def type
      Array
    end

    def type?(x)
      x == Array
    end
  end

  module Core
    class << self

      def ary_inspect(ary)
        strings = ary.array_value.map do |item|
          rb_funcall(item, :to_s).string_value
        end
        RString.from("[#{strings.join(', ')}]")
      end

      def ary_aref(ary, *args)
        case args.length
        when 1
          if args[0].is_a?(RPrimitive) && args[0].value.is_a?(Integer)
            ary.array_value[args[0].value] || Q_NIL
          else
            # TODO: Range
          end
        when 2
          RArray.from(ary.array_value[args[0].value, args[1].value])
        end
      end

      def ary_aset(ary, *args)
        case args.length
        when 2
          if args[0].is_a?(RPrimitive) && args[0].value.is_a?(Integer)
            ary.array_value[args[0].value] = args[1]
          else
            # TODO: Range
          end
        when 3
          ary.array_value[args[0].value, args[1].value] = args[2]
        end
      end

      def ary_join(ary, sep)
        return RString.from("") if ary.array_value.length.zero?

        if sep != Q_NIL
          sep = sep.str_to_str
        end
        strings = ary.array_value.map do |v|
          next v if v.type?(String)
          next ary_join_recursive(ary, sep, v) if v.type?(Array)

          tmp = v.check_string_type
          next tmp unless tmp == Q_NIL

          tmp = v.check_array_type
          next ary_join_recursive(ary, sep, v) unless tmp == Q_NIL

          v.obj_as_string
        end

        RString.from(strings.map(&:string_value).join(sep.string_value))
      end

      def ary_join_recursive(ary, sep, v)
        # TODO: exec recursively
        ary_join(v, sep)
      end

      def ary_plus(x, y)
        RArray.from(x.array_value + y.to_array_type.array_value)
      end

      def ary_times(ary, times)
        tmp = times.check_string_type
        
        return ary_join(ary, tmp) if tmp != Q_NIL

        len = times.value
        return RArray.from([]) if len.zero?
        raise ArgumentError, "negative argument" if len.negative?
        # TODO: check ARY_MAX_SIZE

        RArray.from(ary.array_value * len)
      end

      def ary_hash(ary)
        h = ary.array_value.reduce(1) do |result, element|
          result = 31 * result + Core.rb_funcall(element, :hash).value
        end
        RPrimitive.from(h)
      end
    end

    def self.init_array
      @cArray = rb_define_class(:Array)

      rb_define_method(cArray, :inspect, &method(:ary_inspect))
      rb_alias_method(cArray, :to_s, :inspect)

      rb_define_method(cArray, :hash, &method(:ary_hash))

      rb_define_method(cArray, :[], &method(:ary_aref))
      rb_define_method(cArray, :[]=, &method(:ary_aset))

      rb_define_method(cArray, :+, &method(:ary_plus))
      rb_define_method(cArray, :*, &method(:ary_times))
    end
  end
end
