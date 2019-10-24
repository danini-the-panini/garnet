module RubyRuby
  class RClass < RObject
    attr_reader :method_table, :super_class, :const_table
    attr_accessor :parent_subclasses, :subclasses

    SubclassEntry = Struct.new(:klass, :next_entry)

    def initialize(klass, flags)
      super
      @method_table = {}
      @super_class = super_class
      @const_table = {}
    end

    def set_const(name, value)
      @const_table[name] = value
    end

    def super_class=(s)
      if s
        remove_from_super_subclasses
        s.add_subclass(self)
      end
      @super_class = s
    end

    def name=(n)
      ivar_set(:__classid__, n)
    end

    def self.boot(super_class)
      klass = new(Core.cClass, [:CLASS])

      klass.super_class = super_class

      klass
    end

    def add_subclass(klass)
      entry = SubclassEntry.new(klass, nil)

      head = subclasses
      if head
        entry.next_entry = head
        head.klass.parent_subclasses = entry.next_entry
      end

      subclasses = entry
      klass.parent_subclasses = subclasses
    end

    private

    def remove_from_super_subclasses
      if parent_subclasses
        entry = parent_subclasses
        @parent_subclasses = entry.next_entry
        entry.next_entry.klass.parent_subclasses = parent_subclasses if entry.next_entry
      end
      @parent_subclasses = nil
    end
  end
end
