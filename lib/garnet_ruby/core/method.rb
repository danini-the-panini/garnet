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
  end

  class MethodDef
  end

  class BuiltInMethodDef < MethodDef
    attr_reader :block

    def initialize(&block)
      @block = block
    end
  end

  class ISeqMethodDef < MethodDef
    attr_reader :iseq, :environment

    def initialize(iseq, environment)
      @iseq = iseq
      @environment = environment
    end
  end

  class AliasMethodDef < MethodDef
    attr_reader :original_method

    def initialize(original_method)
      @original_method = original_method.definition.is_a?(AliasMethodDef) ? original_method.definition.original_method : original_method
    end
  end

  class UndefinedMethodDef < MethodDef
  end
end
