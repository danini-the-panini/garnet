module GarnetRuby
  class MethodEntry
    attr_reader :called_id, :defined_class, :visibility, :definition, :owner, :flags

    def initialize(called_id, defined_class, visibility, definition, flags = [])
      @called_id = called_id
      @defined_class = defined_class
      @visibility = visibility
      @flags = flags
      @definition = definition
    end

    def basic?
      flags.include?(:basic)
    end

    def undefined?
      definition.is_a?(UndefinedMethodDef)
    end

    def arity
      definition.arity
    end
  end

  class MethodDef
    def arity
      nil
    end

    def dispatch(*)
      raise "NOT IMPLEMENTED: #{self.class}#dispatch"
    end
  end

  class BuiltInMethodDef < MethodDef
    attr_reader :block

    def initialize(&block)
      @block = block
    end

    def arity
      block.arity
    end

    def dispatch(vm, target, method, args, block=nil)
      env = Environment.new(target.klass, nil)
      env.method_entry = env
      env.method_object = method
      control_frame = ControlFrame.new(target, nil, env, block)
      vm.push_control_frame(control_frame)
      begin
        ret = method.definition.block.call(target, *args)
      rescue VM::GarnetThrow => e
        vm.handle_rescue_throw(e)
      end
      vm.pop_control_frame if vm.current_control_frame == control_frame
      ret
    end
  end

  class ISeqMethodDef < MethodDef
    attr_reader :iseq, :environment

    def initialize(iseq, environment)
      @iseq = iseq
      @environment = environment
    end

    def arity
      iseq.local_table.count { |_, x| x.first == :arg }
    end

    def dispatch(vm, target, method, args, block=nil)
      vm.execute_method_iseq(target, method, args, block)
    end
  end

  class AliasMethodDef < MethodDef
    attr_reader :original_method

    def initialize(original_method)
      @original_method = original_method.definition.is_a?(AliasMethodDef) ? original_method.definition.original_method : original_method
    end

    def arity
      original_method.arity
    end

    def dispatch(vm, target, method, args, block=nil)
      vm.dispatch_method(target, method.definition.original_method, args, block)
    end
  end

  class UndefinedMethodDef < MethodDef
    def dispatch(*)
      raise "CANNOT DISPATCH UNDEFINED METHOD"
    end
  end

  class ProcMethodDef < MethodDef
    attr_reader :proc_value

    def initialize(proc_value)
      @proc_value = proc_value
    end

    def arity
      proc_value.arity
    end

    def dispatch(vm, target, method, args, block=nil)
      vm.execute_block(proc_value.block, args, args.length, block, target, method)
    end
  end

  class ZSuperMethodDef < MethodDef
    attr_reader :original_id

    def initialize(original_id)
      @original_id = original_id
    end
  end

  class IvarMethodDef < MethodDef
    attr_reader :ivar

    def initialize(ivar)
      @ivar = ivar
    end

    def dispatch(vm, target, method, args, block=nil)
      target.ivar_get(ivar) || Q_NIL
    end
  end

  class AttrsetMethodDef < MethodDef
    attr_reader :ivar

    def initialize(ivar)
      @ivar = ivar
    end

    def dispatch(vm, target, method, args, block=nil)
      value = args[0]
      target.ivar_set(ivar, value)
      value
    end
  end
end
