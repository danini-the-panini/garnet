module RubyRuby
  class Environment
    LexicalScope = Struct.new(:klass, :next_scope)

    attr_accessor :lexical_scope

    def initialize(klass, next_scope)
      @lexical_scope = LexicalScope.new(klass, next_scope)
    end
  end
end
