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

      def enum_grep(obj, pat)
        ary = RArray.from([])
        block_given = rb_block_given?

        if rb_block_given?
          vm = VM.instance
          block = vm.caller_environment.block

          rb_block_call(obj, :each) do |x|
            if rtest(rb_funcall(pat, :===, x))
              ary_push(ary, vm.execute_block(block, [x], 1))
            end
          end
        else
          rb_block_call(obj, :each) do |x|
            ary_push(ary, x) if rtest(rb_funcall(pat, :===, x))
          end
        end
        ary
      end

      def enum_find(obj, *args)
        if_none = args.empty? ? Q_NIL : args.first

        vm = VM.instance
        block = vm.caller_environment.block

        memo = Q_UNDEF
        rb_block_call(obj, :each) do |x|
          if rtest(vm.execute_block(block, [x], 1))
            memo = x
            rb_iter_break
          end
          Q_NIL
        end

        return memo if memo != Q_UNDEF
        return rb_funcall(if_none, :call) if if_none != Q_NIL

        Q_NIL
      end

      def enum_find_index(obj, *args)
        vm = VM.instance
        block = vm.caller_environment.block

        memo = Q_NIL
        i = 0
        if args.empty?
          # TODO: return enumerator
          rb_block_call(obj, :each) do |x|
            if rtest(vm.execute_block(block, [x], 1))
              memo = RPrimitive.from(i)
              rb_iter_break
            end
            i += 1
          end
        else
          rb_block_call(obj, :each) do |x|
            if rtest(rb_equal(x, args[0]))
              memo = RPrimitive.from(i)
              rb_iter_break
            end
            i += 1
          end
        end
        memo
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

      def enum_flat_map(obj)
        # TODO: return enumerator

        vm = VM.instance
        block = vm.caller_environment.block

        ary = RArray.from([])
        rb_block_call(obj, :each) do |x|
          i = vm.execute_block(block, [x], 1)
          tmp = i.check_array_type
          if tmp == Q_NIL
            ary_push(ary, i)
          else
            ary.array_value.concat(tmp.array_value)
          end
          Q_NIL
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

      def enum_first(obj, *args)
        return enum_take(obj, args[0]) unless args.empty?

        memo = Q_NIL
        rb_block_call(obj, :each) do |x|
          memo = x
          rb_iter_break
        end
        memo
      end

      def enum_take(obj, n)
        len = num2long(n)

        rb_raise(eArgError, 'attempt to take a negative size') if len.negative?
        return RArray.from([]) if len.zero?

        result = RArray.from([])
        i = len
        rb_block_call(obj, :each) do |x|
          ary_push(result, x)
          i -= 1
          rb_iter_break if i.zero?
          Q_NIL
        end
        result
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

      rb_define_method(mEnumerable, :sort, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :sort_by, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :grep, &method(:enum_grep))
      rb_define_method(mEnumerable, :grep_v, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :count, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :find, &method(:enum_find))
      rb_define_method(mEnumerable, :detect, &method(:enum_find))
      rb_define_method(mEnumerable, :find_index, &method(:enum_find_index))
      rb_define_method(mEnumerable, :find_all, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :select, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :filter, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :filter_map, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :reject, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :collect, &method(:enum_collect))
      rb_define_method(mEnumerable, :map, &method(:enum_collect))
      rb_define_method(mEnumerable, :flat_map, &method(:enum_flat_map))
      rb_define_method(mEnumerable, :collect_concat, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :inject, &method(:enum_inject))
      rb_define_method(mEnumerable, :reduce, &method(:enum_inject))
      rb_define_method(mEnumerable, :partition, &method(:enum_partition))
      rb_define_method(mEnumerable, :group_by, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :tally, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :first, &method(:enum_first))
      rb_define_method(mEnumerable, :all?, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :any?, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :one?, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :none?, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :min, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :max, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :minmax, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :min_by, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :max_by, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :minmax_by, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :member?, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :include?, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :each_with_index, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :reverse_each, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :each_entry, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :each_slice, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :each_cons, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :each_with_object, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :zip, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :take, &method(:enum_take))
      rb_define_method(mEnumerable, :take_while, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :drop, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :drop_while, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :cycle, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :chunk, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :slice_before, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :slice_after, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :slice_when, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :chunk_while, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :sum, &method(:TODO_not_implemented))
      rb_define_method(mEnumerable, :uniq, &method(:TODO_not_implemented))
    end
  end
end
