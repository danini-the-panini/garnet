module GarnetRuby
  class RArray < RBasic
    attr_reader :array_value

    def initialize(klass, flags, array_value)
      super(klass, flags)
      @array_value = array_value
    end

    def to_s
      "[#{array_value.map(&:to_s).join(', ')}]"
    end
  end

  module Core
    def self.init_array
      @cArray = rb_define_class(:Array)

      rb_define_method(cArray, :inspect) do |ary|
        strings = ary.array_value.map do |item|
          rb_funcall(item, :to_s).string_value
        end
        RString.new(cString, 0, "[#{strings.join(', ')}]")
      end
      rb_alias_method(cArray, :to_s, :inspect)

      rb_define_method(cArray, :[]) do |ary, *args|
        case args.length
        when 1
          if args[0].is_a?(RPrimitive) && args[0].value.is_a?(Integer)
            ary.array_value[args[0].value]
          else
            # TODO: Range
          end
        when 2
          RArray.new(Core.cArray, 0, ary.array_value[args[0].value, args[1].value])
        end
      end
      rb_define_method(cArray, :[]=) do |ary, *args|
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
    end
  end
end
