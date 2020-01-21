module GarnetRuby
  module Core
    class << self
    end

    def self.init_iseq
      @cISeq = rb_define_class_under(cRubyVM, :InstructionSequence, cObject)
    end
  end
end