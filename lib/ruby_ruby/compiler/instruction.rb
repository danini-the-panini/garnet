module RubyRuby
  class Instruction
    attr_reader :type, :arguments

    def initialize(type, *args)
      @type = type
      @arguments = args
    end
  end
end
