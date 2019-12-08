module GarnetRuby
  class Environment
    LexicalScope = Struct.new(:klass, :next_scope)

    attr_accessor :block, :method_entry, :method_name
    attr_reader :lexical_scope, :locals, :previous

    def initialize(klass, next_scope, locals = {}, previous = nil, method_entry = nil)
      @lexical_scope = LexicalScope.new(klass, next_scope)
      @locals = locals
      @previous = previous
      @method_entry = method_entry
    end

    def next_scope
      lexical_scope.next_scope
    end
    
    def klass
      lexical_scope.klass
    end

    def to_s
      "<ENV klass=#{lexical_scope.klass} next=#{lexical_scope.next_scope&.lexical_scope&.klass} locals=#{locals} prev=#{previous}>"
    end
    alias inspect to_s
  end
end
