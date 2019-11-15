module RubyRuby
  class Iseq
    attr_reader :name, :type, :instructions, :local_table, :parent_iseq, :local_iseq

    def initialize(name, type, parent = nil, local_table={})
      @name = name
      @type = type
      @instructions = []
      @local_table = local_table
      set_relation(parent)
    end

    def add_instruction(type, *args)
      Instruction.new(type, *args).tap do |insn|
        @instructions << insn
      end
    end

    def to_s
      name
    end

    def debug_dump_instructions
      @instructions.each_with_index do |insn, i|
        puts "#{i}: #{insn.type}\t#{insn.arguments.map(&:to_s).join(',')}"
      end
    end

    def local_level
      i = self
      l = local_iseq
      lv = 0
      while i != l
        i = l.parent_iseq
        lv += 1
      end
      lv
    end

    private

    def set_relation(piseq)
      case type
      when :top, :method, :class, :main
        @local_iseq = self
      else
        @local_iseq = piseq.local_iseq if piseq
      end

      @parent_iseq = piseq if piseq
    end
  end
end
