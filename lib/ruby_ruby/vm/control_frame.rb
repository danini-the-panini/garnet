module RubyRuby
  class ControlFrame
    attr_accessor :pc, :sp, :iseq, :self_value

    def initialize(self_value, environment)
      @pc = 0
      @sp = 0
      @self_value = self_value
      @environment = environment
    end
  end
end
