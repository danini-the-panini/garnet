module GarnetRuby
  class VM
    class << self
      attr_reader :instance

      def new
        @instance ||= super
      end
    end

    def initialize
      @control_frames = []
      @global_variables = {}
    end

    def execute_main(iseq)
      $indent = '';

      main = RObject.new(Core.cObject, [])
      control_frame = ControlFrame.new(main, iseq, Environment.new(Core.cObject, nil))
      @control_frames.push(control_frame)

      execute(iseq) until @control_frames.empty?
    end

    def execute_method_iseq(target, method, args, block=nil)
      iseq = method.iseq
      locals = iseq.local_table.select { |_, v| v == :arg }.keys[0..args.count].zip(args).to_h
      env = Environment.new(target.klass, method.environment, locals)
      control_frame = ControlFrame.new(target, iseq, env, block)
      push_control_frame(control_frame)

      execute(iseq) until @control_frames.last != control_frame

      control_frame.stack.pop
    end

    def execute_block_iseq(block, args)
      prev_control_frame = @control_frames.last

      iseq = block.iseq
      locals = iseq.local_table.select { |_, v| v == :arg }.keys[0..args.count].zip(args).to_h
      env = Environment.new(block.self_value.klass, block.environment, locals, block.environment)
      control_frame = ControlFrame.new(block.self_value, iseq, env, prev_control_frame.block)
      push_control_frame(control_frame)

      execute(iseq) until @control_frames.last != control_frame

      control_frame.stack.pop
    end

    def execute_rescue_iseq(iseq, exception, prev_control_frame=@control_frames.last)
      locals = { :"\#$!" => exception }
      env = Environment.new(prev_control_frame.self_value.klass, prev_control_frame.environment, locals, prev_control_frame.environment)
      control_frame = ControlFrame.new(prev_control_frame.self_value, iseq, env, prev_control_frame.block)
      push_control_frame(control_frame)

      execute(iseq) until @control_frames.last != control_frame

      control_frame.stack.pop
    end

    def execute(iseq)
      control_frame = @control_frames.last
      insn = iseq.instructions[control_frame.pc]

      puts "#{$indent}begin : #{insn.type} for #{control_frame}"

      method_name = :"exec_#{insn.type}"
      raise "EXEC_ERROR: Unknown Instruction Type #{insn.type}" unless respond_to?(method_name)

      prev_pc = control_frame.pc
      __send__(method_name, control_frame, insn)
      control_frame.pc += 1 if control_frame.pc == prev_pc

      puts "#{$indent}end   : #{insn.type} for #{control_frame}"
    end

    def exec_leave(control_frame, insn)
      pop_control_frame
      if control_frame.iseq.type == :rescue
        cfp = @control_frames.last
        cr = cfp.iseq.catch_table.find do |x|
          x.type == :rescue && x.iseq == control_frame.iseq
        end
        @control_frames.last.stack << control_frame.stack.last
        @control_frames.last.pc = cr.cont if cr
      end
      if control_frame.iseq.type == :ensure
        cfp = @control_frames.last
        cr = cfp.iseq.catch_table.find do |x|
          x.type == :ensure && x.iseq == control_frame.iseq
        end
        @control_frames.last.pc = cr.cont if cr
      end
      puts "#{$indent}  --- leave: now executing: #{@control_frames.last}"
    end

    def exec_nop(control_frame, insn)
    end

    def exec_pop(control_frame, insn)
      pop_stack
    end

    def exec_dup(control_frame, insn)
      push_stack(peek_stack)
    end

    def exec_put_object(control_frame, insn)
      push_stack insn.arguments[0]
    end

    def exec_put_self(control_frame, insn)
      push_stack control_frame.self_value
    end

    def exec_put_nil(control_frame, insn)
      push_stack Q_NIL
    end

    def exec_put_string(control_frame, insn)
      push_stack RString.from(insn.arguments[0])
    end

    def exec_concat_strings(control_frame, insn)
      count = insn.arguments[0]
      strings = pop_stack_multi(count)
      string = RString.from(strings.map(&:string_value).join(''))
      push_stack(string)
    end

    def exec_new_array(control_frame, insn)
      count = insn.arguments[0]
      items = pop_stack_multi(count)
      array = RArray.from(items)
      push_stack(array)
    end

    def make_array(x)
      case x
      when RArray then x
      when RPrimitive then RArray.from([x])
      else Core.rb_funcall(x, :to_a)
      end
    end

    def dup_array(ary)
      RArray.from(ary.array_value)
    end

    def exec_concat_array(control_frame, insn)
      ary1, ary2 = pop_stack_multi(2).map { |x| make_array(x) }
      ary = RArray.from(ary1.array_value + ary2.array_value)
      push_stack(ary)
    end

    def exec_splat_array(control_frame, insn)
      flag = insn.arguments[0]
      ary = make_array(pop_stack)
      ary = dup_array(ary) if flag
      push_stack(ary)
    end

    def exec_expand_array(control_frame, insn)
      num, is_splat, post = insn.arguments
      ary = make_array(pop_stack).array_value
      len = ary.length
      if post
        (num - len).times { push_stack(Q_NIL) } if len < num
        [num, len].min.times { |j| push_stack(ary[len - j - 1]) }
        if is_splat
          push_stack(RArray.from(ary[0,(len - [num, len].min)]))
        end
      else
        if is_splat
          if num > len
            push_stack(RArray.from([]))
          else
            push_stack(RArray.from(ary[num..-1]))
          end
        end
        (num - 1).downto(0) do |i|
          if len <= i
            push_stack(Q_NIL)
          else
            push_stack(ary[i])
          end
        end
      end
    end

    def exec_new_hash(control_frame, insn)
      count = insn.arguments[0]
      items = pop_stack_multi(count)
      hash = RHash.from(items.each_slice(2).to_a.to_h)
      push_stack(hash)
    end

    def exec_put_iseq(control_frame, insn)
      push_stack insn.arguments[0]
    end

    def exec_define_method(control_frame, insn)
      method_iseq = pop_stack
      mid_sym = pop_stack
      mid = mid_sym.symbol_value

      klass = control_frame.environment.lexical_scope.klass
      method = ISeqMethod.new(mid, klass, :public, method_iseq, control_frame.environment)
      klass.method_table[mid] = method

      push_stack(mid_sym)
    end

    def exec_define_singleton_method(control_frame, insn)
      method_iseq = pop_stack
      mid_sym = pop_stack
      mid = mid_sym.symbol_value
      target = pop_stack
      singleton = Core.singleton_class_of(target)

      method = ISeqMethod.new(mid, singleton, :public, method_iseq, control_frame.environment)
      singleton.method_table[mid] = method

      push_stack(mid_sym)
    end

    def exec_branch_if(control_frame, insn)
      cond = pop_stack
      control_frame.pc = insn.arguments[0] if rtest(cond)
    end

    def exec_branch_unless(control_frame, insn)
      cond = pop_stack
      control_frame.pc = insn.arguments[0] unless rtest(cond)
    end

    def exec_check_match(control_frame, insn)
      target, pattern = pop_stack_multi(2)
      type, flags = insn.arguments
      if flags.include?(:array)
        result = pattern.array_value.any? do |v|
          rtest(Core.check_match(target, v, type))
        end
        push_stack(result ? Q_TRUE : Q_FALSE)
      else
        push_stack Core.check_match(target, pattern, type)
      end
    end

    def exec_jump(control_frame, insn)
      control_frame.pc = insn.arguments[0]
    end

    def exec_throw(control_frame, insn)
      throw_type = insn.arguments[0]

      case throw_type
      when :break
        until @control_frames.empty?
          cfp = @control_frames.last
          cr = cfp.iseq.catch_table.find do |x|
            x.type == :break && x.iseq == control_frame.iseq && (x.st..x.ed).include?(cfp.pc)
          end
          if cr
            cfp.pc = cr.cont
            break
          end
          pop_control_frame
        end
      when :retry
        # TODO
      when :continue
        exception = pop_stack

        pop_control_frame
        prev_control_frame = @control_frames.last

        cr = nil
        if control_frame.iseq.type == :rescue
          cfp = @control_frames.last
          cr = cfp.iseq.catch_table.find do |x|
            x.type == :ensure && (x.st..x.ed).include?(cfp.pc)
          end
          pop_control_frame
        end

        if !cr
          until @control_frames.empty?
            cfp = @control_frames.last
            puts "THROW AT CFP(#{cfp})"
            cr = cfp.iseq.catch_table.find do |x|
              x.type == :rescue && x.iseq != control_frame.iseq && (x.st..x.ed).include?(cfp.pc)
            end
            cr ||= cfp.iseq.catch_table.find do |x|
              x.type == :ensure && x.iseq != control_frame.iseq && (x.st..x.ed).include?(cfp.pc)
            end
            break if cr
            pop_control_frame
          end
        end

        if cr
          execute_rescue_iseq(cr.iseq, exception, prev_control_frame)
          return
        end

        raise "Uncaught Exception: #{exception}"
      end
    end

    def exec_send_without_block(control_frame, insn)
      callinfo = insn.arguments[0]
      if callinfo.flags.include?(:blockarg)
        blockarg = Core.rb_funcall(pop_stack, :to_proc)
      end
      args = pop_stack_multi(callinfo.argc)
      if callinfo.flags.include?(:splat)
        *pargs, splat = args
        args = [*pargs, *splat.array_value]
      end
      target = pop_stack
      method = find_method(target, callinfo.mid)
      ret = dispatch_method(target, method, args, blockarg&.block)
      push_stack(ret) unless ret == Q_UNDEF
    end

    def exec_send(control_frame, insn)
      callinfo = insn.arguments[0]
      args = pop_stack_multi(callinfo.argc)
      if callinfo.flags.include?(:splat)
        *pargs, splat = args
        args = [*pargs, *splat.array_value]
      end
      target = pop_stack
      method = find_method(target, callinfo.mid)
      block = Block.new(callinfo.block_iseq, control_frame.environment, control_frame.self_value)
      ret = dispatch_method(target, method, args, block)
      push_stack(ret) unless ret == Q_UNDEF
    end

    def exec_invoke_block(control_frame, insn)
      callinfo = insn.arguments[0]
      args = pop_stack_multi(callinfo.argc)
      if callinfo.flags.include?(:splat)
        *pargs, splat = args
        args = [*pargs, *splat.array_value]
      end
      block = control_frame.block
      ret = execute_block_iseq(block, args)
      push_stack(ret)
    end

    def exec_get_local(control_frame, insn)
      name, level = insn.arguments
      local_env = get_local_env(level)
      push_stack(local_env.locals[name])
    end

    def exec_set_local(control_frame, insn)
      value = pop_stack
      name, level = insn.arguments
      local_env = get_local_env(level)
      local_env.locals[name] = value
      push_stack(value)
    end

    def exec_get_block_param_proxy(control_frame, insn)
      level = insn.arguments[0]
      local_env = get_local_env(level)
      push_stack(local_env.block.proc)
    end

    def exec_set_constant(control_frame, insn)
      value = pop_stack
      name = insn.arguments[0]
      control_frame.environment.lexical_scope.klass.rb_const_set(name, value)
    end

    def exec_get_constant(control_frame, insn)
      name = insn.arguments[0]
      ret = control_frame.environment.lexical_scope.klass.rb_const_get(name)
      push_stack(ret)
    end

    def exec_set_global(control_frame, insn)
      value = pop_stack
      @global_variables[insn.arguments[0]] = value
    end

    def exec_get_global(control_frame, insn)
      value = @global_variables[insn.arguments[0]] || Q_NIL
      push_stack(value)
    end

    def exec_setn(control_frame, insn)
      n = insn.arguments[0]
      control_frame.stack[-n - 1] = control_frame.stack.last
    end

    def exec_dupn(control_frame, insn)
      n = insn.arguments[0]
      control_frame.stack[-n..-1].each do |x|
        control_frame.stack << x
      end
    end

    def exec_adjust_stack(control_frame, insn)
      n = insn.arguments[0]
      control_frame.stack.pop(n)
    end

    def push_stack(obj)
      raise "PUSH NIL!" if obj.nil?
      raise "PUSH UNDEF!" if obj == Q_UNDEF
      control_frame = @control_frames.last
      control_frame.stack.push obj
    end

    def pop_stack
      control_frame = @control_frames.last
      control_frame.stack.pop
    end

    def peek_stack
      control_frame = @control_frames.last
      control_frame.stack.last
    end

    def pop_stack_multi(n)
      control_frame = @control_frames.last
      control_frame.stack.pop(n)
    end

    def rb_call(recv, mid, *args)
      method = find_method(recv, mid)
      dispatch_method(recv, method, args)
    end

    def find_method(target, mid)
      raise "TRYING TO CALL #{mid} on NIL" if target.nil?
      klass = target.klass
      method = klass.method_table[mid]
      while method.nil?
        klass = klass.super_class
        if klass.nil?
          # method_missing
          raise "undefined method #{mid} for #{target}"
        end
        method = klass.method_table[mid]
      end
      method
    end

    def dispatch_method(target, method, args, block=nil)
      case method
      when BuiltInMethod
        if block
          method.block.call(target, *args) do |*blargs|
            execute_block_iseq(block, blargs)
          end
        else
          method.block.call(target, *args)
        end
      when ISeqMethod
        execute_method_iseq(target, method, args, block)
      else
        raise "NOT IMPLEMENTED: #{method.class} dispatch"
      end
    end

    def get_local_env(level)
      control_frame = @control_frames.last
      local_env = control_frame.environment
      level.times do
        local_env = local_env.previous
      end
      local_env
    end

    def rtest(value)
      Core.rtest(value)
    end

    def do_raise(exception)
      until @control_frames.empty?
        cfp = @control_frames.last
        cr = cfp.iseq.catch_table.find do |x|
          x.type == :rescue && (x.st..x.ed).include?(cfp.pc)
        end
        cr ||= cfp.iseq.catch_table.find do |x|
          x.type == :ensure && (x.st..x.ed).include?(cfp.pc)
        end
        if cr
          execute_rescue_iseq(cr.iseq, exception)
          return
        end
        pop_control_frame
      end
      raise "Uncaught Exception: #{exception}"
    end

    def push_control_frame(cfp)
      puts "#{$indent}BEGIN CONTROL FRAME: #{cfp}"
      $indent += "  "
      @control_frames << cfp
    end

    def pop_control_frame
      $indent.slice!(0, 2)
      @control_frames.pop.tap { |cfp|
        puts "#{$indent}END CONTROL FRAME: #{cfp}"
      }
    end
  end
end
