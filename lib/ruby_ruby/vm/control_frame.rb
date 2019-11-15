module RubyRuby
  class ControlFrame
    attr_accessor :pc, :stack, :iseq, :self_value
    attr_reader :environment

    def initialize(self_value, environment)
      @pc = 0
      @stack = []
      @self_value = self_value
      @environment = environment
    end
  end
end
