module RubyRuby
  class ControlFrame
    attr_accessor :pc, :stack, :iseq, :self_value
    attr_reader :environment, :block

    def initialize(self_value, environment, block=nil)
      @pc = 0
      @stack = []
      @self_value = self_value
      @environment = environment
      @block = block
    end
  end
end
