module RubyRuby
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
      main = RObject.new(Core.cObject, [])
      control_frame = ControlFrame.new(main, Environment.new(Core.cObject, nil))
      @control_frames.push(control_frame)

      execute(iseq) until @control_frames.empty?
    end

    def execute_method_iseq(target, method, args)
      prev_control_frame = @control_frames.last

      iseq = method.iseq
      locals = iseq.local_table.select { |_,v| v == :arg }.keys[0..args.count].zip(args).to_h
      control_frame = ControlFrame.new(target, Environment.new(target.klass, method.environment, locals))
      @control_frames.push(control_frame)

      execute(iseq) until @control_frames.last == prev_control_frame

      control_frame.stack.pop
    end

    def execute(iseq)
      control_frame = @control_frames.last
      insn = iseq.instructions[control_frame.pc]

      puts "### executing: #{insn.type}"
      puts "STACK BEFORE: #{control_frame.stack.map(&:to_s).join(',')}"

      method_name = :"exec_#{insn.type}"
      raise "EXEC_ERROR: Unknown Instruction Type #{insn.type}" unless respond_to?(method_name)

      __send__(method_name, control_frame, insn, iseq)
      puts "STACK AFTER: #{control_frame.stack.map(&:to_s).join(',')}"
    end

    def exec_leave(control_frame, insn, iseq)
      @control_frames.pop
    end

    def exec_pop(control_frame, insn, iseq)
      pop_stack
      control_frame.pc += 1
    end

    def exec_dup(control_frame, insn, iseq)
      push_stack(peek_stack)
      control_frame.pc += 1
    end

    def exec_put_object(control_frame, insn, iseq)
      push_stack insn.arguments[0]
      control_frame.pc += 1
    end

    def exec_put_self(control_frame, insn, iseq)
      push_stack control_frame.self_value
      control_frame.pc += 1
    end

    def exec_put_nil(control_frame, insn, iseq)
      push_stack Q_NIL
      control_frame.pc += 1
    end

    def exec_put_string(control_frame, insn, iseq)
      push_stack RString.new(Core.cString, 0, insn.arguments[0])
      control_frame.pc += 1
    end

    def exec_concat_strings(control_frame, insn, iseq)
      count = insn.arguments[0]
      strings = pop_stack_multi(count)
      string = RString.new(Core.cString, 0, strings.map(&:string_value).join(''))
      push_stack(string)
      control_frame.pc += 1
    end

    def exec_new_array(control_frame, insn, iseq)
      count = insn.arguments[0]
      items = pop_stack_multi(count)
      array = RArray.new(Core.cArray, 0, items)
      push_stack(array)
      control_frame.pc += 1
    end

    def exec_new_hash(control_frame, insn, iseq)
      count = insn.arguments[0]
      items = pop_stack_multi(count)
      hash = RHash.new(Core.cHash, 0, items.each_slice(2).to_a.to_h)
      push_stack(hash)
      control_frame.pc += 1
    end

    def exec_put_iseq(control_frame, insn, iseq)
      push_stack insn.arguments[0]
      control_frame.pc += 1
    end

    def exec_define_method(control_frame, insn, iseq)
      method_iseq = pop_stack
      mid_sym = pop_stack
      mid = mid_sym.symbol_value

      klass = control_frame.environment.lexical_scope.klass
      method = ISeqMethod.new(mid, klass, :public, method_iseq, control_frame.environment)
      klass.method_table[mid] = method

      push_stack(mid_sym)

      control_frame.pc += 1
    end

    def exec_branch_if(control_frame, insn, iseq)
      cond = pop_stack
      if cond == Q_NIL || cond == Q_FALSE
        control_frame.pc += 1
      else
        control_frame.pc = insn.arguments[0]
      end
    end

    def exec_branch_unless(control_frame, insn, iseq)
      cond = pop_stack
      if cond == Q_NIL || cond == Q_FALSE
        control_frame.pc = insn.arguments[0]
      else
        control_frame.pc += 1
      end
    end

    def exec_jump(control_frame, insn, iseq)
      control_frame.pc = insn.arguments[0]
    end

    def exec_send(control_frame, insn, iseq)
      mid = insn.arguments[0]
      argc = insn.arguments[1]
      args = pop_stack_multi(argc)
      target = pop_stack
      method = find_method(target, mid)
      ret = dispatch_method(target, method, args)
      push_stack(ret)
      control_frame.pc += 1
    end

    def exec_get_local(control_frame, insn, iseq)
      name = insn.arguments[0]
      level = insn.arguments[1]
      local_env = get_local_env(level)
      push_stack(local_env.locals[name])
      control_frame.pc += 1
    end

    def exec_set_local(control_frame, insn, iseq)
      value = peek_stack
      name = insn.arguments[0]
      level = insn.arguments[1]
      local_env = get_local_env(level)
      local_env.locals[name] = value
      control_frame.pc += 1
    end

    def exec_set_constant(control_frame, insn, iseq)
      value = pop_stack
      name = insn.arguments[0]
      control_frame.environment.lexical_scope.klass.rb_const_set(name, value)
      control_frame.pc += 1
    end

    def exec_get_constant(control_frame, insn, iseq)
      name = insn.arguments[0]
      ret = control_frame.environment.lexical_scope.klass.rb_const_get(name)
      push_stack(ret)
      control_frame.pc += 1
    end

    def exec_set_global(control_frame, insn, iseq)
      value = pop_stack
      @global_variables[insn.arguments[0]] = value
      control_frame.pc += 1
    end

    def exec_get_global(control_frame, insn, iseq)
      value = @global_variables[insn.arguments[0]] || Q_NIL
      push_stack(value)
      control_frame.pc += 1
    end

    def exec_setn(control_frame, insn, iseq)
      n = insn.arguments[0]
      control_frame.stack[-n - 1] = control_frame.stack.last
      control_frame.pc += 1
    end

    def exec_dupn(control_frame, insn, iseq)
      n = insn.arguments[0]
      control_frame.stack[-n..-1].each do |x|
        control_frame.stack << x
      end
      control_frame.pc += 1
    end

    def exec_adjust_stack(control_frame, insn, iseq)
      n = insn.arguments[0]
      control_frame.stack.pop(n)
      control_frame.pc += 1
    end

    def push_stack(obj)
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

    def dispatch_method(target, method, args)
      case method
      when BuiltInMethod
        method.block.call(target, *args)
      when ISeqMethod
        execute_method_iseq(target, method, args)
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
  end
end
