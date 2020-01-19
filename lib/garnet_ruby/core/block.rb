module GarnetRuby
  class Block
    attr_writer :proc
    attr_reader :environment, :self_value

    def initialize(environment, self_value)
      @environment = environment
      @self_value = self_value
    end

    def to_s
      "<#Block env=#{environment} self=#{self_value}>"
    end
    
    def inspect
      to_s
    end

    def proc
      @proc ||= RProc.new(Core.cProc, [], self)
    end

    def dispatch(*)
      raise "NOT IMPLEMENTED: #{self.class}#dispatch"
    end

    def description
      '(block)'
    end

    def iseq
      nil
    end
  end

  class IseqBlock < Block
    attr_reader :iseq

    def initialize(environment, self_value, iseq)
      super(environment, self_value)
      @iseq = iseq
    end

    def arity
      iseq.local_table.count { |_, x| x.first == :arg }
    end

    def to_s
      "<#IseqBlock iseq=#{iseq} env=#{environment} self=#{self_value}>"
    end

    def dispatch(vm, args, block_block = nil, override_self_value = nil, method = nil, klass = nil)
      sv = override_self_value || self_value
      vm.execute_block_iseq(self, args, block_block, sv, method, klass)
    end

    def description
      iseq.location
    end
  end

  class ProcBlock < Block
    attr_reader :wrapped_proc

    def initialize(wrapped_proc)
      super(wrapped_proc.block.environment, wrapped_proc.block.self_value)
      @wrapped_proc = wrapped_proc
    end

    def iseq
      wrapped_proc.block.iseq
    end

    def arity
      wrapped_proc.arity
    end

    def to_s
      "<#ProcBlock env=#{environment} self=#{self_value}>"
    end

    def dispatch(vm, args, block_block = nil, override_self_value = nil, method = nil, klass = nil)
      Core.proc_call(wrapped_proc, *args, block: block_block, self_value: override_self_value, klass: klass)
    end

    def description
      prc.block.description
    end
  end

  class BuiltInBlock < Block
    attr_reader :block

    def initialize(environment, self_value, &block)
      super(environment, self_value)
      @block = block
    end

    def arity
      block.arity
    end

    def to_s
      "<#BuiltInBlock env=#{environment} self=#{self_value}>"
    end

    def dispatch(vm, args, block_block = nil, override_self_value = nil, method = nil, klass = nil)
      if block_block
        sv = override_self_value || self_value
        block.call(*args) do |*blargs|
          vm.execute_block(block_block, blargs, blargs.length, nil, sv)
        end
      else
        block.call(*args)
      end
    end
  end
end
