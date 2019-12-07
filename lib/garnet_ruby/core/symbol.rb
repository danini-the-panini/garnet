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
      RString.from(x.symbol_value.to_s)
    end

    def self.from(value)
      return Q_NIL if value.nil?

      new(Core.cSymbol, [], value)
    end
  end

  module Core
    def self.init_symbol
      @cSymbol = rb_define_class(:Symbol)

      rb_define_method(cSymbol, :to_s) { x.sym2str }

      rb_define_method(cSymbol, :inspect) do |x|
        RString.from(":#{x.symbol_value}")
      end
    end
  end
end
