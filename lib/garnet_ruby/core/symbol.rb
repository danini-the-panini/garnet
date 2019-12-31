module GarnetRuby
  class RSymbol < RBasic
    attr_reader :symbol_value

    def initialize(klass, flags, symbol_value)
      super(klass, flags)
      @symbol_value = symbol_value
    end

    def to_s
      symbol_value.inspect
    end

    def inspect
      "<#Symbol:#{symbol_value}>"
    end

    def sym2str
      RString.from(symbol_value.to_s)
    end

    def self.from(value)
      return Q_NIL if value.nil?

      new(Core.cSymbol, [], value)
    end

    def ==(other)
      return false unless other.is_a?(RSymbol)

      symbol_value == other.symbol_value
    end

    def type
      Symbol
    end

    def type?(x)
      x == Symbol
    end
  end

  module Core
    class << self
      def sym_hash(sym)
        RPrimitive.from(sym.symbol_value.hash)
      end
    end

    def self.init_symbol
      @cSymbol = rb_define_class(:Symbol)

      rb_define_method(cSymbol, :hash, &method(:sym_hash))
      rb_define_method(cSymbol, :inspect) do |x|
        RString.from(":#{x.symbol_value}")
      end
      rb_define_method(cSymbol, :to_s) { |x| x.sym2str }
    end
  end
end
