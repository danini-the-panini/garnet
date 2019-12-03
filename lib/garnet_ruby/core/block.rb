module GarnetRuby
  class Block
    attr_writer :proc
    attr_reader :iseq, :environment, :self_value

    def initialize(iseq, environment, self_value)
      @iseq = iseq
      @environment = environment
      @self_value = self_value
    end

    def to_s
      "<#Block iseq=#{iseq} env=#{environment} self=#{self_value}>"
    end
    alias inspect to_s

    def proc
      @proc ||= RProc.new(Core.cProc, [], self)
    end
  end
end
