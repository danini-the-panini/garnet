module GarnetRuby
  class VM

    class << self
      attr_reader :instance

      def new(*args)
        @instance ||= super
      end
    end

    class ExecutionError < StandardError
      def initialize(message, insn)
        super("#{message} in #{insn.type}#{insn.arguments.inspect} (#{insn.file}:#{insn.line})")
      end
    end

    attr_reader :special_variables
    attr_accessor :running

    def initialize(top_self, options)
      $indent = '' if __grb_debug__?
      @options = options
      @top_self = top_self
      @running = false
      @control_frames = []
      @global_variables = {}
      @special_variables = {
        backref: Q_NIL
      }
      @end_procs = []
    end

    def __vm_debug__?
      (@options[:debug] || __grb_debug__?) && @running
    end

    def __vm_debug_exc__?
      ENV['GARNET_EXC'] || __grb_debug__?
    end

    def current_control_frame
      @control_frames.last
    end

    def previous_control_frame
      @control_frames[-2]
    end

    def ruby_level_cfp
      @control_frames.reverse_each do |cfp|
        return cfp unless cfp.iseq.nil?
      end
      nil
    end

    def caller_environment(cfp = current_control_frame)
      env = cfp.environment
      env = env.previous until env.previous.nil?
      env
    end

    def execute_main(iseq)
      control_frame = ControlFrame.new(@top_self, iseq, Environment.new(Core.cObject, nil))
      push_control_frame(control_frame)

      begin
        execute(iseq) until @control_frames.empty?
      rescue GarnetThrow => e
        handle_uncaught_throw(e)
      end

      push_control_frame(control_frame)

      @end_procs.reverse_each do |prc|
        Core.proc_call(prc)
      rescue GarnetThrow => e
        handle_uncaught_throw(e)
      end
    end

    def populate_locals(env, iseq, args)
      offset = 0
      num_locals = iseq.local_table.size
      num_post = iseq.local_table.count { |_, v| v[0] == :post }
      has_kwargs = iseq.local_table.any? { |_, v| v[0] == :kwarg || v[0] == :opt_kwarg }

      if has_kwargs
        if args.last.is_a?(RHash) && args.last.entries.all? { |e| e.key.is_a?(RSymbol) }
          env.locals[:'?'] = args.pop
        else
          env.locals[:'?'] = RHash.from({})
        end
      end

      iseq.local_table.each_with_index do |(k, v), i|
        case v[0]
        when :arg
          env.locals[k] = args[i]
        when :post
          env.locals[k] = args[i - num_locals]
        when :opt
          if args[i]
            env.locals[k] = args[i]
            offset = v[1]
          end
        when :splat
          env.locals[k] = RArray.from(args[i, args.length - num_post - i] || [])
        end
      end
      offset
    end

    def execute_method_iseq(target, method, args, block = nil)
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

    def execute_block_iseq(block, args, block_block = nil, self_value = nil, method = nil, klass = nil)
      self_value ||= block.self_value

      iseq = block.iseq
      env = Environment.new(klass || self_value.klass.real, block.environment, {}, block.environment, block.environment.method_entry)
      env.errinfo = block.environment.errinfo
      if method
        env.method_entry = env
        env.method_object = method
      end
      control_frame = ControlFrame.new(self_value, iseq, env, block_block)
      control_frame.pc = populate_locals(env, iseq, args)
      push_control_frame(control_frame)

      execute(iseq) until current_control_frame != control_frame

      control_frame.stack.pop
    end

    def execute_rescue_iseq(iseq, throw_data, prev_control_frame=current_control_frame)
      locals = { :"\#$!" => throw_data.exc }
      env = Environment.new(prev_control_frame.environment.klass, prev_control_frame.environment, locals, prev_control_frame.environment, prev_control_frame.environment.method_entry)
      env.errinfo = throw_data.exc
      control_frame = ControlFrame.new(prev_control_frame.self_value, iseq, env, prev_control_frame.block)
      control_frame.throw_data = throw_data
      push_control_frame(control_frame)

      execute(iseq) until current_control_frame != control_frame

      control_frame.stack.pop
    rescue GarnetThrow => e
      handle_rescue_throw(e)
    end

    def execute_class_iseq(iseq, klass)
      prev_control_frame = current_control_frame
      env = Environment.new(klass, prev_control_frame.environment)
      control_frame = ControlFrame.new(klass, iseq, env)
      push_control_frame(control_frame)

      execute(iseq) until current_control_frame != control_frame

      control_frame.stack.pop || Q_NIL
    end

    def execute_eval_iseq(iseq, prev_control_frame = previous_control_frame, klass = nil, self_value = nil)
      env = Environment.new(klass || prev_control_frame.klass, prev_control_frame.environment, {}, prev_control_frame.environment)
      control_frame = ControlFrame.new(self_value || prev_control_frame.self_value, iseq, env)
      push_control_frame(control_frame)

      execute(iseq) until current_control_frame != control_frame

      control_frame.stack.pop || Q_NIL
    end

    def execute_load_iseq(iseq)
      env = Environment.new(Core.cObject, nil)
      control_frame = ControlFrame.new(@top_self, iseq, env)
      push_control_frame(control_frame)

      execute(iseq) until current_control_frame != control_frame

      Q_NIL
    end

    def execute(iseq)
      control_frame = current_control_frame
      insn = iseq.instructions[control_frame.pc]

      puts "#{$indent}begin : #{insn} for #{control_frame}" if __vm_debug__?

      method_name = :"exec_#{insn.type}"
      raise ExecutionError.new("EXEC_ERROR: Unknown Instruction Type #{insn.type}", insn) unless respond_to?(method_name)

      prev_pc = control_frame.pc
      begin
        __send__(method_name, control_frame, insn)
      rescue GarnetThrow => e
        handle_rescue_throw(e)
      rescue => e
        raise ExecutionError.new(e.message, insn)
      end
      control_frame.pc += 1 if control_frame.pc == prev_pc

      puts "#{$indent}end   : #{insn} for #{control_frame}" if __vm_debug__?
    end

    def exec_leave(control_frame, insn)
      if insn.arguments.empty?
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
        return
      end

      raise GarnetThrow.of_type(insn.arguments[0]).new(pop_stack, current_control_frame)
    end

    def exec_nop(control_frame, insn)
    end

    def exec_pop(control_frame, insn)
      pop_stack
    end

    def exec_dup(control_frame, insn)
      push_stack(peek_stack)
    end

    def exec_swap(control_frame, insn)
      s = control_frame.stack
      s[-1], s[-2] = s[-2], s[-1]
    end

    def exec_not(control_frame, insn)
      v = rtest(pop_stack)
      push_stack(v ? Q_FALSE : Q_TRUE)
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

    def exec_intern(control_frame, insn)
      string = pop_stack
      sym = RSymbol.from(string.string_value.to_sym)
      push_stack(sym)
    end

    def exec_to_regexp(control_frame, insn)
      options, count = insn.arguments
      strings = pop_stack_multi(count)
      string = RString.from(strings.map(&:string_value).join(''))
      isfixed = !((options || 0) & Regexp::FIXEDENCODING).zero?
      string.string_value.force_encoding(isfixed ? 'utf-8' : 'ascii-8bit')
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
      ary1, ary2 = pop_stack_multi(2)

      tmp1 = ary1.check_to_array
      tmp2 = ary2.check_to_array

      tmp1 = RArray.from([tmp1]) if tmp1 == Q_NIL
      tmp2 = RArray.from([tmp2]) if tmp2 == Q_NIL

      if tmp1 == ary1
        tmp1 = dup_array(ary1)
      end

      ary = RArray.from(tmp1.array_value + tmp2.array_value)
      push_stack(ary)
    end

    def exec_splat_array(control_frame, insn)
      flag = insn.arguments[0]
      ary = pop_stack

      tmp = ary.check_to_array
      ary = if tmp == Q_NIL
              RArray.from([ary])
            elsif flag
              dup_array(tmp)
            else
              tmp
            end

      push_stack(ary)
    end

    def exec_expand_array(control_frame, insn)
      num, is_splat, post = insn.arguments
      ary = pop_stack
      obj = ary

      if !ary.type?(Array) && (ary = ary.check_array_type) == Q_NIL
        ary = obj
        ptr = [ary]
        len = 1
      else
        ptr = ary.array_value
        len = ary.len
      end

      if post
        (num - len).times { push_stack(Q_NIL) } if len < num
        [num, len].min.times { |j| push_stack(ptr[len - j - 1]) }
        if is_splat
          push_stack(RArray.from(ptr[0,(len - [num, len].min)]))
        end
      else
        if is_splat
          if num > len
            push_stack(RArray.from([]))
          else
            push_stack(RArray.from(ptr[num..-1]))
          end
        end
        (num - 1).downto(0) do |i|
          if len <= i
            push_stack(Q_NIL)
          else
            push_stack(ptr[i])
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

    def exec_hash_merge_ptr(control_frame, insn)
      n = insn.arguments[0]
      items = pop_stack_multi(n)
      hash = pop_stack

      items.each_slice(2).each do |(a, b)|
        hash.update(a, b)
      end

      push_stack(hash)
    end

    def exec_hash_merge_kwd(control_frame, insn)
      hash1, hash2 = pop_stack_multi(2)

      hash2 = hash2.to_hash_type

      hash2.entries.each do |e|
        hash1.update(e.key, e.value)
      end

      push_stack(hash1)
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
      old_mid = old_mid_sym.symbol_value

      klass = control_frame.environment.lexical_scope.klass

      Core.rb_alias(klass, mid, old_mid)

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

    def exec_branch_nil(control_frame, insn)
      cond = pop_stack
      control_frame.pc = insn.arguments[0] if cond == Q_NIL
    end

    def exec_check_match(control_frame, insn)
      type, flags = insn.arguments

      pattern = pop_stack
      target = pop_stack if type != :when

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
      raise GarnetThrow.of_type(throw_type).new(pop_stack, current_control_frame)
    end

    def exec_send_without_block(control_frame, insn)
      callinfo = insn.arguments[0]
      blockarg = get_block_arg(callinfo)
      blockarg = nil if blockarg == Q_NIL
      args = collect_args(callinfo)
      target = pop_stack
      method = find_method(target, callinfo.mid)
      ret = dispatch_method(target, method, args, blockarg)
      push_stack(ret) unless ret.nil? || ret == Q_UNDEF
    end

    def exec_send(control_frame, insn)
      callinfo = insn.arguments[0]
      args = collect_args(callinfo)
      target = pop_stack
      method = find_method(target, callinfo.mid)
      block = IseqBlock.new(control_frame.environment, control_frame.self_value, callinfo.block_iseq)
      ret = dispatch_method(target, method, args, block)
      push_stack(ret) unless ret.nil? || ret == Q_UNDEF
    end

    def exec_invoke_block(control_frame, insn)
      callinfo = insn.arguments[0]
      args = collect_args(callinfo)
      block = caller_environment.block
      ret = execute_block(block, args, callinfo.argc)
      push_stack(ret) unless ret.nil? || ret == Q_UNDEF
    end

    def exec_invoke_super(control_frame, insn)
      callinfo = insn.arguments[0]
      block = get_block_for_super(control_frame, callinfo)
      args = collect_args(callinfo)
      target = control_frame.self_value
      method = find_super_method(target, control_frame.method_entry.method_object)
      ret = dispatch_method(target, method, args, block)
      push_stack(ret) unless ret.nil? || ret == Q_UNDEF
    end

    def collect_args(callinfo)
      args = pop_stack_multi(callinfo.argc)
      if callinfo.flags.include?(:splat)
        *pargs, splat = args
        args = [*pargs, *splat.array_value]
      end
      args
    end

    def get_block_arg(callinfo)
      return nil unless callinfo.flags.include?(:blockarg)

      block_value = pop_stack
      return block_value if block_value == Q_NIL

      ProcBlock.new(rb_call(block_value, :to_proc))
    end

    def get_block_for_super(control_frame, callinfo)
      if callinfo.block_iseq
        return IseqBlock.new(control_frame.environment, control_frame.self_value, callinfo.block_iseq)
      end

      blockarg = get_block_arg(callinfo)
      if blockarg.nil?
        control_frame.block
      elsif blockarg == Q_NIL
        nil
      else
        blockarg
      end
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
      name, level = insn.arguments
      local_env = get_local_env(level)

      push_stack(local_env.locals[name] || local_env.block&.proc || Q_NIL)
    end

    def exec_set_block_param_proxy(control_frame, insn)
      exec_set_local(control_frame, insn)
    end

    def exec_set_constant(control_frame, insn)
      const_base, value = pop_stack_multi(2)
      name = insn.arguments[0]
      const_base.rb_const_set(name, value)
      push_stack(value)
    end

    def exec_get_constant(control_frame, insn)
      const_base = pop_stack

      if const_base.is_a?(RClass)
        name = insn.arguments[0]
        ret = const_base.rb_const_get(name)
        push_stack(ret)
      else
        Core.rb_raise(Core.eTypeError, "#{const_base} is not a class/module")
      end
    end

    def exec_set_global(control_frame, insn)
      name = insn.arguments[0]
      value = pop_stack

      if Core.virtual_variable?(name)
        Core.virtual_variable_set(name, value)
      else
        set_global(name, value)
      end

      push_stack(value)
    end

    def exec_get_global(control_frame, insn)
      name = insn.arguments[0]

      value = Core.get_global(name)

      push_stack(value)
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

    def exec_putn(control_frame, insn)
      n = insn.arguments[0]
      control_frame.stack << control_frame.stack[-n - 1]
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
      current_control_frame.push_stack(obj)
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

    def rb_call_with_block(recv, mid, block, *args)
      method = find_method(recv, mid)
      dispatch_method(recv, method, args, block)
    end

    def rb_check_funcall(recv, mid, *args)
      rb_check_funcall_default(recv, mid, Q_UNDEF, *args)
    end

    def rb_check_funcall_default(recv, mid, df, *args)
      return df unless rb_respond_to(recv, mid)
      rb_call(recv, mid, *args)
    end

    def frame_this_func
      current_control_frame.environment.method_entry.method_name
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
    rescue GarnetThrow::Break => e
      e.value if e.cfp.nil?
    end

    def rb_respond_to(recv, mid)
      # TODO: actually call recv#respond_to?
      method = find_method_unchecked(recv, mid)
      method && !method.definition.is_a?(UndefinedMethodDef)
    end

    def rb_yield(*args)
      block = caller_environment.block
      execute_block(block, args, args.length)
    end

    def yield_under(klass, slf, *args)
      block = caller_environment.block
      execute_block(block, args, args.length, nil, slf, nil, klass)
    end

    def is_block_orphan?(block)
      @control_frames.reverse_each do |cfp|
        next if cfp.iseq.nil?
        cr = cfp.iseq.catch_table.find do |x|
          x.type == :break && x.iseq == block.iseq && (x.st..x.ed).include?(cfp.pc)
        end
        return false if cr
      end
      true
    end

    def undefined_method(mid, target)
      # method_missing
      Core.rb_raise(Core.eNoMethodError, "undefined method #{mid} for #{target}")
    end

    def find_method_unchecked(target, mid, klass = target.klass)
      raise "TRYING TO CALL #{mid} on NIL" if target.nil?
      raise "TRYING TO CALL #{mid} on NIL KLASS (#{target})" if klass.nil?

      Core.find_method(klass, mid)
    end

    def find_method(target, mid, klass = target.klass)
      method = find_method_unchecked(target, mid, klass)
      if method.nil? || method.definition.is_a?(UndefinedMethodDef)
        undefined_method(mid, target)
      end
      method
    end

    def find_super_method(target, me)
      meklass = me.defined_class
      sup = meklass.super_class
      if sup.nil? && meklass.flags.include?(:MODULE)
        sup2 = target.klass.super_class
        sup2 = sup2.super_class until sup2.method_table == meklass.method_table
        sup = sup2.super_class
      end
      find_method(target, me.called_id, sup)
    end

    def dispatch_method(target, method, args, block=nil)
      method.definition.dispatch(self, target, method, args, block)
    end

    def execute_block(block, args, argc, block_block = nil, self_value = nil, method_entry = nil, klass = nil)
      if !block.proc.is_lambda &&
         args.length == 1 &&
         argc == 1 &&
         args.first.type?(Array) &&
         block.arity > 1
        args = args[0].array_value
      end

      self_value ||= block.self_value

      block.dispatch(self, args, block_block, self_value, method_entry, klass)
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
        Core.rb_raise(Core.eTypeError, "#{klass} is not a class/module")
      end
    end

    def check_class_redefinition(id, flags, super_class, klass)
      unless klass.flags.include?(:CLASS)
        Core.rb_raise(Core.eTypeError, "#{klass} is not a class")
      end

      if flags.include?(:has_superclass) && super_class != klass.super_class.real
        Core.rb_raise(Core.eTypeError, "superclass mismatch for #{id}")
      end
    end

    def check_module_redefinition(id, flags, klass)
      unless klass.flags.include?(:MODULE)
        Core.rb_raise(Core.eTypeError, "#{klass} is not a module")
      end
    end

    def define_class(id, flags, cbase, super_class)
      if flags.include?(:has_superclass) && !super_class.flags.include?(:CLASS) # TODO: also check it isn't a model
        Core.rb_raise(Core.eTypeError, "superclass must be a Class (#{super_class.klass} given)")
      end

      check_if_namespace(cbase)
      klass = cbase.const_direct(id)
      if klass
        check_class_redefinition(id, flags, super_class, klass)
        return klass
      end

      return declare_class(id, flags, cbase, super_class)
    end

    def define_module(id, flags, cbase)
      check_if_namespace(cbase)
      klass = cbase.const_direct(id)
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

    def set_visibility(visi)
      scope_visi = previous_control_frame.environment.scope_visi
      scope_visi.method_visi = visi
      # TODO: module_func?
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

      Core.rb_raise(Core.eTypeError, 'no class variables available') if klass == Q_NIL

      klass
    end

    def do_raise(exception)
      if exception == Q_NIL
        exception = if previous_control_frame.environment.errinfo
                      previous_control_frame.environment.errinfo
                    else
                      Core.exc_new(Core.eRuntimeError)
                    end
      end
      bt = backtrace_to_ary([], 0, true)
      exception.ivar_set(:backtrace, bt)
      if __vm_debug_exc__?
        STDERR.puts "RASIED EXCEPTION #{exception} (#{exception.ivar_get(:message)})\n#{bt.array_value.map { |x| "\t#{x.string_value}" }.join("\n")}"
      end
      raise GarnetThrow::Raise.new(exception, current_control_frame, exception)
    end

    def handle_rescue_throw(e)
      cfp = current_control_frame
      return if e.handle(self, cfp) unless cfp.iseq.nil?
      pop_control_frame
      raise e
    end

    def handle_uncaught_throw(e)
      case e
      when GarnetThrow::Raise
        return if Core.rtest(Core.obj_is_kind_of(e.exc, Core.eSystemExit))

        STDERR.puts "Uncaught Exception: #{e.exc} #{Core.exc_message(e.exc)}"
        bt = e.exc.ivar_get(:backtrace)
        if !bt.nil? && bt.type?(Array)
          bt.array_value.each do |x|
            STDERR.puts x.string_value
          end
        end
        if __vm_debug_exc__?
          STDERR.puts(e.backtrace)
        end
      else
        raise "Uncaught throw of type #{e.class} (#{e.cfp.iseq&.location})"
      end
    end

    def get_errinfo
      current_control_frame.environment.errinfo
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
          Core.rb_raise(Core.eArgError, "negative level (#{lev})") if lev.negative?

          n = bt.length - lev
        end
      when 2
        lev = level.value
        n = vn.value
        Core.rb_raise(Core.eArgError, "negative level (#{lev})") if lev.negative?
        Core.rb_raise(Core.eArgError, "negative size (#{n})") if n.negative?
      end

      return RArray.from([]) if n.zero?

      if to_str
        RArray.from(bt[lev, n])
      else
        # TODO: backtrace_to_location_ary
      end
    end

    def make_binding(src_cfp)
      i = @control_frames.find_index(src_cfp)
      cfp = i.downto(0).each do |n|
        c = @control_frames[n]
        break c if c.iseq
      end

      RBinding.new(Core.cBinding, [], cfp)
    end

    def push_control_frame(cfp)
      if __vm_debug__?
        puts "#{$indent}BEGIN CONTROL FRAME: #{cfp} (#{caller.first})"
        $indent += "  "
      end
      @control_frames << cfp
    end

    def pop_control_frame
      $indent.slice!(0, 2) if __vm_debug__?
      @control_frames.pop.tap { |cfp|
        puts "#{$indent}END CONTROL FRAME: #{cfp} (#{caller(3, 1).first})" if __vm_debug__?
      }
    end

    def add_end_proc(prc)
      @end_procs << prc
    end
  end
end
