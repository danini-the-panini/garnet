module GarnetRuby
  class Method
    attr_reader :called_id, :defined_class, :visibility, :owner

    def initialize(called_id, defined_class, visibility)
      @called_id = called_id
      @defined_class = defined_class
      @visibility = visibility
    end
  end

  class BuiltInMethod < Method
    attr_reader :block

    def initialize(called_id, defined_class, visibility, &block)
      super(called_id, defined_class, visibility)
      @block = block
    end
  end

  class ISeqMethod < Method
    attr_reader :iseq, :environment

    def initialize(called_id, defined_class, visibility, iseq, environment)
      super(called_id, defined_class, visibility)
      @iseq = iseq
      @environment = environment
    end
  end

  class AliasMethod < Method
    attr_reader :original_method

    def initialize(called_id, defined_class, visibility, original_method)
      super(called_id, defined_class, visibility)
      @original_method = original_method.is_a?(AliasMethod) ? original_method.original_method : original_method
    end
  end

  class UndefinedMethod < Method
  end
end
