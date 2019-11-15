module RubyRuby
  class Environment
    LexicalScope = Struct.new(:klass, :next_scope)

    attr_reader :lexical_scope, :locals, :previous

    def initialize(klass, next_scope, locals = {}, previous = nil)
      @lexical_scope = LexicalScope.new(klass, next_scope)
      @locals = locals
      @previous = previous
    end
  end
end
