module GarnetRuby
  class RClass < RObject
    attr_reader :method_table, :super_class, :const_table
    attr_accessor :parent_subclasses, :subclasses, :allocator

    SubclassEntry = Struct.new(:klass, :next_entry)

    UNDEF_ALLOC_FUNC = -1

    def initialize(klass, flags)
      super
      @method_table = {}
      @super_class = super_class
      @const_table = {}
    end

    def alloc
      alloc_func.call(self)
    end

    def alloc_func
      return nil if @allocator == UNDEF_ALLOC_FUNC
      return nil if super_class.nil?
      return super_class.alloc_func if @allocator.nil?

      @allocator
    end

    def define_alloc_func(func)
      @allocator = func
    end

    def undef_alloc_func
      @allocator = UNDEF_ALLOC_FUNC
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

    def cvar_get(name)
      return ivars[name] if ivars.key?(name)
      return nil if super_class.nil? || super_class == Q_NIL

      super_class.cvar_get(name)
    end

    def cvar_set(name, value)
      if ivars.key?(name) || super_class.nil? || super_class == Q_NIL
        ivars[name] = value
        return
      end

      super_class.cvar_set(name, value)
    end

    def super_class=(s)
      if s && s != Q_UNDEF
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

    def to_s
      "<#Class:#{name}>"
    end

    def search_ancestor(cl)
      while cl
        return cl if cl == self
        cl = cl.super_class
      end
      false
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

      metaclass.flags |= [:SINGLETON]

      if meta_class_of_class_class?
        self.metaclass = metaclass
        metaclass.metaclass = metaclass
      else
        tmp = metaclass
        self.metaclass = metaclass
        metaclass.metaclass = tmp#.ensure_eigenclass
      end

      s = super_class
      s = s.super_class while s&.flags&.include?(:ICLASS)
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

    def has_metaclass?
      metaclass.flags.include?(:SINGLETON)
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

    def real
      if flags.include?(:SINGLETON) || flags.include?(:ICLASS)
        return super_class.real
      end

      self
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
