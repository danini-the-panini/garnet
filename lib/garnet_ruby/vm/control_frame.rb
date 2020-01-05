module GarnetRuby
  class ControlFrame
    attr_accessor :pc, :stack, :iseq, :self_value, :tag, :throw_data
    attr_reader :environment, :block

    def initialize(self_value, iseq, environment, block=nil)
      @iseq = iseq
      @pc = 0
      @stack = []
      @self_value = self_value
      @environment = environment
      environment.block = block
    end

    def block
      environment.block
    end

    def method_entry
      environment.method_entry
    end

    def to_s
      inmethod = method_entry ? " in method #{method_entry.method_name}" : ""
      "CFP(self=#{self_value}, pc=#{pc}, iseq=#{iseq}, stack=#{stack})#{inmethod}"
    end

    def push_stack(obj)
      raise "PUSH NIL!" if obj.nil?
      raise "PUSH UNDEF!" if obj == Q_UNDEF
      stack.push obj
    end
  end
end
