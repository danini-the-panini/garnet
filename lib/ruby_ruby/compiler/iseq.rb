module RubyRuby
  class Iseq
    attr_reader :name, :instructions

    def initialize(name)
      @name = name
      @instructions = []
      @local_table = {}
    end

    def add_instruction(type, *args)
      @instructions << Instruction.new(type, *args)
    end

    def debug_dump_instructions
      @instructions.each do |insn|
        puts "#{insn.type}\t#{insn.arguments.map(&:inspect).join(',')}"
      end
    end
  end
end
