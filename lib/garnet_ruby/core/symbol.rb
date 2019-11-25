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
  end

  module Core
    def self.init_symbol
      @cSymbol = rb_define_class(:Symbol)

      rb_define_method(cSymbol, :to_s) do |x|
        RString.new(Core.cString, 0, x.symbol_value.to_s)
      end
      rb_define_method(cSymbol, :inspect) do |x|
        RString.new(Core.cString, 0, ":#{x.symbol_value}")
      end
    end
  end
end
