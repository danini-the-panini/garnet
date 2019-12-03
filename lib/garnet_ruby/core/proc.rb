module GarnetRuby
  class RProc < RBasic
    attr_accessor :block

    def initialize(klass, flags, block)
      super(klass, flags)
      @block = block
      block.proc = self
    end

    def to_s
      "<#Proc block=#{block}>"
    end
    alias inspect to_s
  end

  module Core
    def self.init_proc
      @cProc = rb_define_class(:Proc, cObject)

      rb_define_method(cProc, :to_proc) { |x| x }
    end
  end
end
