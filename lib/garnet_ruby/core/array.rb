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
      def to_array_type(ary)
        ary.rb_convert_type_with_id(Array, "Array", :to_ary)
      end

      def check_array_type(ary)
        ary.rb_check_convert_type_with_id(Array, "Array", :to_ary)
      end

      def check_to_array(ary)
        ary.rb_check_convert_type_with_id(Array, "Array", :to_a)
      end

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

      def ary_plus(x, y)
        y = to_array_type(y)
        RArray.from(x.array_value + y.array_value)
      end
    end

    def self.init_array
      @cArray = rb_define_class(:Array)

      rb_define_method(cArray, :inspect, &method(:ary_inspect))
      rb_alias_method(cArray, :to_s, :inspect)

      rb_define_method(cArray, :[], &method(:ary_aref))
      rb_define_method(cArray, :[]=, &method(:ary_aset))

      rb_define_method(cArray, :+, &method(:ary_plus))
    end
  end
end
