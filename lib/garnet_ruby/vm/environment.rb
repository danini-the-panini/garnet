module GarnetRuby
  class Environment
    LexicalScope = Struct.new(:klass, :next_scope)

    attr_accessor :block
    attr_reader :lexical_scope, :locals, :previous

    def initialize(klass, next_scope, locals = {}, previous = nil)
      @lexical_scope = LexicalScope.new(klass, next_scope)
      @locals = locals
      @previous = previous
    end

    def to_s
      "<ENV klass=#{lexical_scope.klass} next=#{lexical_scope.next_scope&.lexical_scope&.klass} locals=#{locals} prev=#{previous}>"
    end
    alias inspect to_s
  end
end
