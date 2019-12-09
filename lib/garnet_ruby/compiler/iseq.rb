module GarnetRuby
  class Iseq
    class CatchRecord
      attr_reader :type, :st, :ed, :cont, :iseq

      def initialize(type, st, ed, cont, iseq)
        @type = type
        @st = st
        @ed = ed
        @cont = cont
        @iseq = iseq
      end

      def to_s
        "catch type: #{type} st: #{st} ed: #{ed} cont: #{cont}, iseq: #{iseq}"
      end
    end

    attr_reader :name,
                :type,
                :instructions,
                :local_table,
                :catch_table,
                :parent_iseq,
                :local_iseq

    attr_accessor :start_label, :end_label, :redo_label, :start_index

    def initialize(name, type, parent = nil, local_table = {})
      @name = name
      @type = type
      @instructions = []
      @local_table = local_table
      @catch_table = []
      @start_index = 0
      set_relation(parent)
    end

    def add_instruction(node, type, *args)
      file = node.file rescue '?'
      line = node.line rescue '?'
      Instruction.new(file, line, type, *args).tap do |insn|
        @instructions << insn
      end
    end

    def add_catch_type(type, st, ed, cont, iseq)
      @catch_table << CatchRecord.new(type, st, ed, cont, iseq)
    end

    def to_s
      name
    end

    def inspect
      "#<Iseq:#{name}>"
    end

    def debug_dump_instructions
      return unless __grb_debug__?
      @instructions.each_with_index do |insn, i|
        args = insn.arguments
                   .map { |x| x.is_a?(String) ? x.inspect : x.to_s }
                   .join(',')
        puts "#{i}: #{insn.type}\t#{args}"
      end
    end

    def method_iseq
      return self if type == :method
      raise "NO METHOD ISEQ" if parent_iseq.nil?
      parent_iseq.method_iseq
    end

    def local_level(label)
      i = self
      l = local_iseq
      lv = 0
      while i != l && !i.local_table.key?(label)
        break if i.parent_iseq.nil?

        i = i.parent_iseq
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
