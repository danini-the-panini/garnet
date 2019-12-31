module GarnetRuby
  module Core
    class << self
      def enum_to_a(obj)
        ary = RArray.from([])

        rb_block_call(obj, :each) do |x|
          ary.array_value.push(x)
        end

        ary
      end

      def enum_collect(obj)
        # TODO: return enumerator

        vm = VM.instance
        block = vm.caller_environment.block

        ary = RArray.from([])
        rb_block_call(obj, :each) do |x|
          ary.array_value.push(vm.execute_block(block, [x]))
        end

        ary
      end
    end

    def self.init_enum
      @mEnumerable = rb_define_module(:Enumerable)

      rb_define_method(mEnumerable, :to_a, &method(:enum_to_a))

      rb_define_method(mEnumerable, :collect, &method(:enum_collect))
    end
  end
end