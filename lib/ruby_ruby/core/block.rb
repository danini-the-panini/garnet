module RubyRuby
  class Block
    attr_reader :iseq, :environment, :self_value

    def initialize(iseq, environment, self_value)
      @iseq = iseq
      @environment = environment
      @self_value = self_value
    end
  end
end
