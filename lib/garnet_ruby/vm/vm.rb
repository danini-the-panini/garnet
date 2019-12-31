module GarnetRuby
  class VM
    class << self
      attr_reader :instance

      def new
        @instance ||= super
      end
    end

    class ExecutionError < StandardError
      def initialize(message, insn)
        super("#{message} (#{insn.file}:#{insn.line})")
      end
    end

    attr_reader :special_variables
    attr_accessor :running

    def initialize
      $indent = '' if __grb_debug__?
      @running = false
      @control_frames = []
      @global_variables = {}
      @special_variables = {
        backref: Q_NIL
      }
    end

    def current_control_frame
      @control_frames.last
    end

    def previous_control_frame
      @control_frames[-2]
    end

    def caller_environment(cfp = current_control_frame)
      env = cfp.environment
      env = env.previous until env.previous.nil?
      env
    end

    def execute_main(iseq)
      main = RObject.new(Core.cObject, [])
      control_frame = ControlFrame.new(main, iseq, Environment.new(Core.cObject, nil))
      @control_frames.push(control_frame)

      execute(iseq) until @control_frames.empty?
    end

    def populate_locals(env, iseq, args)
      offset = 0
      iseq.local_table.each_with_index do |(k, v), i|
        case v[0]
        when :arg
          env.locals[k] = args[i]
        when :opt
          if args[i]
            env.locals[k] = args[i]
            offset = v[1]
          end
        end
      end
      offset
    end

    def execute_method_iseq(target, method, args, block=nil)
      iseq = method.definition.iseq
      env = Environment.new(target.klass, method.definition.environment, {})
      env.method_entry = env
      env.method_object = method
      control_frame = ControlFrame.new(target, iseq, env, block)
      control_frame.pc = populate_locals(env, iseq, args)
      push_control_frame(control_frame)

      execute(iseq) until current_control_frame != control_frame

      control_frame.stack.pop
    end

    def execute_block_iseq(block, args)
      prev_control_frame = current_control_frame

      iseq = block.iseq
      env = Environment.new(block.self_value.klass, block.environment, {}, block.environment, prev_control_frame.environment.method_entry)
      control_frame = ControlFrame.new(block.self_value, iseq, env)
      control_frame.pc = populate_locals(env, iseq, args)
      push_control_frame(control_frame)

      execute(iseq) until current_control_frame != control_frame

      control_frame.stack.pop
    end

    def execute_rescue_iseq(iseq, exception, prev_control_frame=current_control_frame)
      locals = { :"\#$!" => exception }
      env = Environment.new(prev_control_frame.self_value.klass, prev_control_frame.environment, locals, prev_control_frame.environment, prev_control_frame.environment.method_entry)
      control_frame = ControlFrame.new(prev_control_frame.self_value, iseq, env, prev_control_frame.block)
      push_control_frame(control_frame)

      execute(iseq) until current_control_frame != control_frame

      control_frame.stack.pop
    end

    def execute_class_iseq(iseq, klass)
      prev_control_frame = current_control_frame
      env = Environment.new(klass, prev_control_frame.environment)
      control_frame = ControlFrame.new(klass, iseq, env)
      push_control_frame(control_frame)

      execute(iseq) until current_control_frame != control_frame

      control_frame.stack.pop || Q_NIL
    end

    def execute(iseq)
      control_frame = current_control_frame
      insn = iseq.instructions[control_frame.pc]

      puts "#{$indent}begin : #{insn} for #{control_frame}" if __grb_debug__?

      method_name = :"exec_#{insn.type}"
      raise ExecutionError.new("EXEC_ERROR: Unknown Instruction Type #{insn.type}", insn) unless respond_to?(method_name)

      prev_pc = control_frame.pc
      begin
        __send__(method_name, control_frame, insn)
      rescue => e
        raise ExecutionError.new(e.message, insn)
      end
      control_frame.pc += 1 if control_frame.pc == prev_pc

      puts "#{$indent}end   : #{insn} for #{control_frame}" if __grb_debug__?
    end

    def exec_leave(control_frame, insn)
      pop_control_frame
      if control_frame.iseq.type == :rescue
        cfp = current_control_frame
        cr = cfp.iseq.catch_table.find do |x|
          x.type == :rescue && x.iseq == control_frame.iseq
        end
        current_control_frame.stack << control_frame.stack.last
        current_control_frame.pc = cr.cont if cr
      end
      if control_frame.iseq.type == :ensure
        cfp = current_control_frame
        cr = cfp.iseq.catch_table.find do |x|
          x.type == :ensure && x.iseq == control_frame.iseq
        end
        current_control_frame.pc = cr.cont if cr
      end
      puts "#{$indent}  --- leave: now executing: #{current_control_frame}" if __grb_debug__?
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

    def exec_put_special_object(control_frame, insn)
      type = insn.arguments[0]
      case type
      when :const_base
        push_stack(control_frame.environment.lexical_scope.klass)
      # when :vm_core
      # when :cbase
      end
    end

    def exec_concat_strings(control_frame, insn)
      count = insn.arguments[0]
      strings = pop_stack_multi(count)
      string = RString.from(strings.map(&:string_value).join(''))
      push_stack(string)
    end

    def exec_to_regexp(control_frame, insn)
      options, count = insn.arguments
      strings = pop_stack_multi(count)
      string = RString.from(strings.map(&:string_value).join(''))
      regexp = RRegexp.from_string(string, options)
      push_stack(regexp)
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

    def exec_new_range(control_frame, insn)
      excl = insn.arguments[0]
      st, ed = pop_stack_multi(2)
      range = RRange.make(st, ed, excl)
      push_stack(range)
    end

    def exec_put_iseq(control_frame, insn)
      push_stack insn.arguments[0]
    end

    def exec_define_method(control_frame, insn)
      method_iseq = pop_stack
      mid_sym = pop_stack
      mid = mid_sym.symbol_value

      klass = control_frame.environment.lexical_scope.klass
      definition = ISeqMethodDef.new(method_iseq, control_frame.environment)
      method = Core.method_entry_create(mid, klass, :public, definition)
      klass.method_table[mid] = method

      push_stack(mid_sym)
    end

    def exec_define_singleton_method(control_frame, insn)
      method_iseq = pop_stack
      mid_sym = pop_stack
      mid = mid_sym.symbol_value
      target = pop_stack
      singleton = Core.singleton_class_of(target)

      definition = ISeqMethodDef.new(method_iseq, control_frame.environment)
      method = Core.method_entry_create(mid, singleton, :public, definition)
      singleton.method_table[mid] = method

      push_stack(mid_sym)
    end

    def exec_set_method_alias(control_frame, insn)
      new_mid_sym, old_mid_sym = pop_stack_multi(2)
      mid = new_mid_sym.symbol_value

      klass = control_frame.environment.lexical_scope.klass
      original_method = find_method(klass, old_mid_sym.symbol_value, klass)

      definition = AliasMethodDef.new(original_method)
      method = Core.method_entry_create(mid, klass, :public, definition)
      klass.method_table[mid] = method

      push_stack(new_mid_sym)
    end

    def exec_undefine_method(control_frame, insn)
      mid_sym = pop_stack
      mid = mid_sym.symbol_value

      klass = control_frame.environment.lexical_scope.klass
      definition = UndefinedMethodDef.new
      method = Core.method_entry_create(mid, klass, :public, definition)
      klass.method_table[mid] = method

      push_stack(mid_sym)
    end

    def exec_define_class(control_frame, insn)
      id, iseq, type, flags = insn.arguments

      cbase, super_class = pop_stack_multi(2)

      klass = find_or_create_class_by_id(id, type, flags, cbase, super_class)

      ret = execute_class_iseq(iseq, klass)

      push_stack(ret)
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
          cfp = current_control_frame
          unless cfp.iseq.nil?
            cr = cfp.iseq.catch_table.find do |x|
              x.type == :break && x.iseq == control_frame.iseq && (x.st..x.ed).include?(cfp.pc)
            end
            if cr
              cfp.pc = cr.cont
              break
            end
          end
          pop_control_frame
        end
      when :retry
        # TODO
      when :continue
        exception = pop_stack

        pop_control_frame
        prev_control_frame = current_control_frame

        cr = nil
        if control_frame.iseq.type == :rescue
          cfp = current_control_frame
          cr = cfp.iseq.catch_table.find do |x|
            x.type == :ensure && (x.st..x.ed).include?(cfp.pc)
          end
          pop_control_frame
        end

        if !cr
          until @control_frames.empty?
            cfp = current_control_frame
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
      push_stack(ret) unless ret.nil? || ret == Q_UNDEF
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
      block = IseqBlock.new(control_frame.environment, control_frame.self_value, callinfo.block_iseq)
      ret = dispatch_method(target, method, args, block)
      push_stack(ret) unless ret.nil? || ret == Q_UNDEF
    end

    def exec_invoke_block(control_frame, insn)
      callinfo = insn.arguments[0]
      args = pop_stack_multi(callinfo.argc)
      if callinfo.flags.include?(:splat)
        *pargs, splat = args
        args = [*pargs, *splat.array_value]
      end
      block = caller_environment.block
      ret = execute_block(block, args)
      push_stack(ret) unless ret.nil? || ret == Q_UNDEF
    end

    def exec_invoke_super(control_frame, insn)
      callinfo = insn.arguments[0]
      args = pop_stack_multi(callinfo.argc)
      if callinfo.flags.include?(:splat)
        *pargs, splat = args
        args = [*pargs, *splat.array_value]
      end
      target = control_frame.self_value
      method = find_super_method(target, control_frame.method_entry.method_name)
      ret = dispatch_method(target, method, args)
      push_stack(ret) unless ret.nil? || ret == Q_UNDEF
    end

    def exec_get_local(control_frame, insn)
      name, level = insn.arguments
      local_env = get_local_env(level)
      push_stack(local_env.locals[name] || Q_NIL)
    end

    def exec_set_local(control_frame, insn)
      value = pop_stack
      name, level = insn.arguments
      local_env = get_local_env(level)
      local_env.locals[name] = value
      push_stack(value)
    end

    def exec_get_instance_variable(control_frame, insn)
      id = insn.arguments[0]
      value = control_frame.self_value.ivar_get(id) || Q_NIL
      push_stack(value)
    end

    def exec_set_instance_variable(control_frame, insn)
      id = insn.arguments[0]
      value = pop_stack
      control_frame.self_value.ivar_set(id, value)
      push_stack(value)
    end

    def exec_get_class_variable(control_frame, insn)
      id = insn.arguments[0]
      value = cvar_base.cvar_get(id) || Q_NIL
      push_stack(value)
    end

    def exec_set_class_variable(control_frame, insn)
      id = insn.arguments[0]
      value = pop_stack
      cvar_base.cvar_set(id, value)
      push_stack(value)
    end

    def exec_get_block_param_proxy(control_frame, insn)
      level = insn.arguments[0]
      local_env = get_local_env(level)
      push_stack(local_env.block.proc)
    end

    def exec_set_constant(control_frame, insn)
      const_base, value = pop_stack_multi(2)
      name = insn.arguments[0]
      const_base.rb_const_set(name, value)
    end

    def exec_get_constant(control_frame, insn)
      const_base = pop_stack
      name = insn.arguments[0]
      ret = const_base.rb_const_get(name)
      raise NameError, "Undefined Constant #{name}" if ret.nil?
      push_stack(ret)
    end

    def exec_set_global(control_frame, insn)
      value = pop_stack
      set_global(insn.arguments[0], value)
    end

    def exec_get_global(control_frame, insn)
      push_stack(get_global(insn.arguments[0]))
    end

    def exec_get_special(control_frame, insn)
      key, type = insn.arguments

      val = if type.nil?
              lep_svar_get(key)
            else
              backref = lep_svar_get(:backref)

              case type
              when :&
                Core.reg_last_match(backref)
              when :`
                Core.reg_match_pre(backref)
              when :"'"
                Core.reg_match_post(backref)
              when :+
                Core.reg_match_last(backref)
              when Integer
                Core.reg_nth_match(type, backref)
              else
                raise "unexpected back-ref: #{type}"
              end
            end

      push_stack(val)
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
      control_frame = current_control_frame
      control_frame.stack.push obj
    end

    def pop_stack
      control_frame = current_control_frame
      control_frame.stack.pop
    end

    def peek_stack
      control_frame = current_control_frame
      control_frame.stack.last
    end

    def pop_stack_multi(n)
      control_frame = current_control_frame
      control_frame.stack.pop(n)
    end

    def rb_call(recv, mid, *args)
      method = find_method(recv, mid)
      dispatch_method(recv, method, args)
    end

    def rb_check_funcall(recv, mid, *args)
      return Q_UNDEF unless rb_respond_to(recv, mid)
      rb_call(recv, mid, *args)
    end

    def call_super(*args)
      cfp = current_control_frame
      recv = cfp.self_value
      me = cfp.method_entry.method_object

      klass = me.defined_class
      klass = klass.super_class
      id = me.called_id
      me = find_method(recv, id, klass)

      dispatch_method(recv, me, args)
    end

    def rb_block_call(recv, mid, *args, &block)
      control_frame = current_control_frame
      method = find_method(recv, mid)
      block = BuiltInBlock.new(control_frame.environment, control_frame.self_value, &block)
      dispatch_method(recv, method, args, block)
    end

    def rb_respond_to(recv, mid)
      # TODO: actually call recv#respond_to?
      method = find_method_unchecked(recv, mid)
      method && !method.definition.is_a?(UndefinedMethodDef)
    end

    def rb_yield(*args)
      block = caller_environment.block
      execute_block(block, args)
    end

    def undefined_method(mid, target)
      # method_missing
      raise "undefined method #{mid} for #{target}"
    end

    def find_method_unchecked(target, mid, klass = target.klass)
      raise "TRYING TO CALL #{mid} on NIL" if target.nil?
      Core.find_method(klass, mid)
    end

    def find_method(target, mid, klass = target.klass)
      method = find_method_unchecked(target, mid, klass)
      undefined_method(mid, target) if method.nil? || method.definition.is_a?(UndefinedMethodDef)
      method
    end

    def find_super_method(target, mid)
      find_method(target, mid, target.klass.super_class)
    end

    def dispatch_method(target, method, args, block=nil)
      case method.definition
      when BuiltInMethodDef
        env = Environment.new(target.klass, nil)
        env.method_entry = env
        env.method_object = method
        control_frame = ControlFrame.new(target, nil, env, block)
        push_control_frame(control_frame)
        ret = method.definition.block.call(target, *args)
        pop_control_frame if current_control_frame == control_frame
        ret
      when ISeqMethodDef
        execute_method_iseq(target, method, args, block)
      when AliasMethodDef
        dispatch_method(target, method.definition.original_method, args, block)
      when UndefinedMethodDef
        raise "CANNOT CALL UNDEFINED METHOD"
      else
        raise "NOT IMPLEMENTED: #{method.class} dispatch"
      end
    end

    def execute_block(block, args)
      if args.length == 1 && args.first.type?(Array) && block.arity > 1
        args = args[0].array_value
      end

      case block
      when BuiltInBlock
        block.block.call(*args)
      when IseqBlock
        execute_block_iseq(block, args)
      else
        raise "Unknown Block Type: #{block.class}"
      end
    end

    def find_or_create_class_by_id(id, type, flags, cbase, super_class)
      case type
      when :class
        define_class(id, flags, cbase, super_class)
      when :singleton_class
        Core.singleton_class_of(cbase)
      when :module
        define_module(id, flags, cbase)
      else
        raise "unknown defineclass type: #{type}"
      end
    end

    def check_if_namespace(klass)
      unless klass.flags.include?(:CLASS) || klass.flags.include?(:MODULE)
        raise TypeError, "#{klass} is not a class/module"
      end
    end

    def check_class_redefinition(id, flags, super_class, klass)
      unless klass.flags.include?(:CLASS)
        raise TypeError, "#{klass} is not a class"
      end

      if flags.include?(:has_superclass) && super_class != klass.super_class.real
        raise TypeError, "superclass mismatch for #{id}"
      end
    end

    def check_module_redefinition(id, flags, klass)
      unless klass.flags.include?(:MODULE)
        raise TypeError, "#{klass} is not a module"
      end
    end

    def define_class(id, flags, cbase, super_class)
      if flags.include?(:has_superclass) && !super_class.flags.include?(:CLASS) # TODO: also check it isn't a model
        raise TypeError, "superclass must be a Class (#{super_class.klass} given)"
      end

      check_if_namespace(cbase)
      klass = cbase.rb_const_get(id, false)
      if klass
        check_class_redefinition(id, flags, super_class, klass)
        return klass
      end

      return declare_class(id, flags, cbase, super_class)
    end

    def define_module(id, flags, cbase)
      check_if_namespace(cbase)
      klass = cbase.rb_const_get(id, false)
      if klass
        check_module_redefinition(id, flags, klass)
        return klass
      end

      return declare_module(id, flags, cbase)
    end

    def declare_class(id, flags, cbase, super_class)
      super_class = flags.include?(:has_superclass) ? super_class : Core.cObject
      klass = RClass.new_class(super_class)
      klass.name = id
      cbase.rb_const_set(id, klass)
      klass
    end

    def declare_module(id, flags, cbase)
      klass = RClass.new_module
      klass.name = id
      cbase.rb_const_set(id, klass)
      klass
    end

    def get_local_env(level)
      control_frame = current_control_frame
      local_env = control_frame.environment
      level.times do
        local_env = local_env.previous
      end
      local_env
    end

    def set_global(name, value)
      @global_variables[name] = value
    end

    def get_global(name)
      @global_variables[name] || Q_NIL
    end

    def rtest(value)
      Core.rtest(value)
    end

    def lep_svar_get(key)
      @special_variables[key]
    end

    def cvar_base
      env = current_control_frame.environment

      while env.next_scope && (env.klass.nil? || env.klass.flags.include?(:SINGLETON))
        env = env.next_scope
      end

      puts 'WARNING: class variable access from top level' if env.next_scope.nil?

      klass = env.klass

      raise TypeError, 'no class variables available' if klass == Q_NIL

      klass
    end

    def do_raise(exception)
      until @control_frames.empty?
        cfp = current_control_frame
        unless cfp.iseq.nil?
          cr = cfp.iseq.catch_table.find do |x|
            x.type == :rescue && (x.st..x.ed).include?(cfp.pc)
          end
          cr ||= cfp.iseq.catch_table.find do |x|
            x.type == :ensure && (x.st..x.ed).include?(cfp.pc)
          end
          if cr
            cfp.pc = cr.cont
            execute_rescue_iseq(cr.iseq, exception)
            return
          end
        end
        pop_control_frame
      end
      raise "Uncaught Exception: #{exception}"
    end

    def find_tag(tag)
      cfp = @control_frames.reverse.find { |c| c.tag == tag }
      raise UncaughtThrowError, "(uncaught throw #{tag})" if !cfp

      pop_control_frame until current_control_frame == cfp
    end

    def backtrace
      @control_frames.filter(&:iseq).reverse.map do |cfp|
        insn = cfp.iseq.instructions[cfp.pc]
        "#{insn.file}:#{insn.line} in `#{cfp.iseq.name}'"
      end
    end

    def backtrace_to_ary(args, lev_default, to_str)
      level, vn = args
      bt = backtrace

      lev = n = 0

      case args.length
      when 0
        lev = lev_default
        n = bt.length - lev
      when 1
        if level.is_a?(Range)
          # TODO
        else
          lev = level.value
          raise ArgumentError, "negative level (#{lev})" if lev.negative?

          n = bt.length - lev
        end
      when 2
        lev = level.value
        n = vn.value
        raise ArgumentError, "negative level (#{lev})" if lev.negative?
        raise ArgumentError, "negative size (#{n})" if n.negative?
      end

      return RArray.from([]) if n.zero?

      if to_str
        RArray.from(bt[lev, n])
      else
        # TODO: backtrace_to_location_ary
      end
    end

    def push_control_frame(cfp)
      if __grb_debug__?
        puts "#{$indent}BEGIN CONTROL FRAME: #{cfp}"
        $indent += "  "
      end
      @control_frames << cfp
    end

    def pop_control_frame
      $indent.slice!(0, 2) if __grb_debug__?
      @control_frames.pop.tap { |cfp|
        puts "#{$indent}END CONTROL FRAME: #{cfp}" if __grb_debug__?
      }
    end

    def while_current_control_frame
      cfp = current_control_frame
      r = Q_NIL
      while current_control_frame == cfp
        r = yield
      end
      r
    end
  end
end
