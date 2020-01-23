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
      "#<RSymbol:#{symbol_value}>"
    end

    def sym2str
      RString.from(symbol_value.to_s)
    end

    def sym_to_proc
      cfp = VM.instance.current_control_frame
      block = SymbolBlock.new(cfp.environment, cfp.environment.lexical_scope.klass, symbol_value)
      RProc.new(Core.cProc, [], block)
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

    def sym_hash
      RPrimitive.from(symbol_value.hash)
    end

    def sym_inspect
      RString.from(":#{symbol_value}")
    end

    def sym_equal(other)
      self == other ? Q_TRUE : Q_FALSE
    end
  end

  module Core
    class << self
    end

    def self.init_symbol
      @cSymbol = rb_define_class(:Symbol)

      rb_define_method(cSymbol, :==, &:sym_equal)
      rb_define_method(cSymbol, :===, &:sym_equal)
      rb_define_method(cSymbol, :hash, &:sym_hash)
      rb_define_method(cSymbol, :inspect, &:sym_inspect)
      rb_define_method(cSymbol, :to_s, &:sym2str)
      rb_define_method(cSymbol, :id2name, &:sym2str)
      rb_define_method(cSymbol, :intern, &:itself)
      rb_define_method(cSymbol, :to_sym, &:itself)
      rb_define_method(cSymbol, :to_proc, &:sym_to_proc)
    end
  end
end
