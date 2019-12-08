module GarnetRuby
  class Instruction
    attr_reader :file, :line, :type, :arguments

    def initialize(file, line, type, *args)
      @file = file
      @line = line
      @type = type
      @arguments = args
    end

    def to_s
      "#{type} #{arguments.map(&:to_s).join(', ')} (#{file}:#{line})"
    end
  end
end
