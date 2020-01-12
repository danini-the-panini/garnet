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

    def arity
      definition.arity
    end
  end

  class MethodDef
    def arity
      nil
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
  end

  class AliasMethodDef < MethodDef
    attr_reader :original_method

    def initialize(original_method)
      @original_method = original_method.definition.is_a?(AliasMethodDef) ? original_method.definition.original_method : original_method
    end

    def arity
      original_method.arity
    end
  end

  class UndefinedMethodDef < MethodDef
  end

  class ProcMethodDef < MethodDef
    attr_reader :proc_value

    def initialize(proc_value)
      @proc_value = proc_value
    end

    def arity
      proc_value.arity
    end
  end

  class ZSuperMethodDef < MethodDef
  end
end
