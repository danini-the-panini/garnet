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
          ary.array_value.push(vm.execute_block(block, [x], 1))
        end

        ary
      end

      def enum_partition(obj)
        # TODO: return enumerator
        
        vm = VM.instance
        block = vm.caller_environment.block

        v1 = RArray.from([])
        v2 = RArray.from([])
        rb_block_call(obj, :each) do |x|
          if rtest(vm.execute_block(block, [x], 1))
            ary_push(v1, x)
          else
            ary_push(v2, x)
          end
        end

        RArray.from([v1, v2])
      end

      def enum_inject(obj, *args)
        init, op = args
        iter = :inject

        vm = VM.instance
        block = vm.caller_environment.block

        case args.length
        when 0
          init = Q_UNDEF
        when 1
          unless rb_block_given?
            id = check_id(init)
            op = id ? RSymbol.from(id) : init
            init = Q_UNDEF
            iter = :inject_op
          end
        when 2
          if rb_block_given?
            puts "WARNING: given block not used"
          end
          id = check_id(op)
          op = RSymbol.from(id) if id
          iter = :inject_op
        end

        memo = init

        case iter
        when :inject
          rb_block_call(obj, :each) do |i|
            if memo == Q_UNDEF
              memo = i
            else
              memo = vm.execute_block(block, [memo, i], 2)
            end
            Q_NIL
          end
        when :inject_op
          rb_block_call(obj, :each) do |i|
            if memo == Q_UNDEF
              memo = i
            elsif op.type?(Symbol)
              memo = rb_funcall(memo, op.symbol_value, i)
            else
              memo = rb_f_send(memo, op, i)
            end
            Q_NIL
          end
        end

        return Q_NIL if memo == Q_UNDEF

        memo
      end
    end

    def self.init_enum
      @mEnumerable = rb_define_module(:Enumerable)

      rb_define_method(mEnumerable, :to_a, &method(:enum_to_a))

      rb_define_method(mEnumerable, :collect, &method(:enum_collect))
      rb_define_method(mEnumerable, :inject, &method(:enum_inject))
      rb_define_method(mEnumerable, :reduce, &method(:enum_inject))
      rb_define_method(mEnumerable, :partition, &method(:enum_partition))
    end
  end
end
