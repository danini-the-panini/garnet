module GarnetRuby
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

    def rb_const_defined?(name)
      # TODO: recurse
      @const_table.key?(name)
    end

    def rb_const_get(name)
      # TODO: recurse
      @const_table[name]
    end

    def rb_const_set(name, value)
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

    def name
      ivar_get(:__classid__)
    end

    def self.new_class(super_class)
      klass = new(Core.cClass, [:CLASS])
      klass.super_class = super_class
      klass
    end

    def self.new_module
      new(Core.cModule, [:MODULE])
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

    def make_metaclass
      metaclass = RClass.new_class(Q_UNDEF)

      metaclass.flag |= [:SINGLETON]
      # rb_singleton_class_attached(metaclass) # TODO ??

      if meta_class_of_class_class?
        self.metaclass = metaclass
        metaclass.metaclass = metaclass
      else
        tmp = metaclass
        self.metaclass = metaclass
        metaclass.metaclass = tmp.ensure_eigenclass
      end

      s = super_class
      s = s.super_class while s.flags.include?(:ICLASS)
      metaclass.super_class = s&.ensure_eigenclass || Core.cClass

      metaclass
    end

    def metaclass
      klass
    end

    def metaclass=(klass)
      @klass = klass
    end

    def meta_class_of_class_class?
      metaclass == self
    end

    def ensure_eigenclass
      if has_metaclass?
        metaclass
      else
        make_metaclass
      end
    end

    def include_module(mdl)
      # TODO: modules with included modules
      # TODO: support "prepend" (with origin)

      iclass = mdl.make_copy
      iclass.flags |= [:ICLASS]
      iclass.super_class = super_class
      self.super_class = iclass
    end

    def make_copy
      copy = RClass.new(klass, flags)

      copy.method_table = method_table
      copy.const_table = const_table

      copy
    end

    protected
    attr_writer :method_table, :const_table

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
