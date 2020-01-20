module GarnetRuby
  class RClass < RObject
    attr_reader :method_table, :super_class, :const_table
    attr_accessor :parent_subclasses, :subclasses, :allocator, :includer

    SubclassEntry = Struct.new(:klass, :next_entry)

    UNDEF_ALLOC_FUNC = -1

    def initialize(klass, flags)
      super
      @method_table = {}
      @super_class = super_class
      @const_table = {}
    end

    def type
      Class
    end

    def type?(x)
      x == Class
    end

    def alloc
      alloc_func.call(self)
    end

    def alloc_func
      return super_class&.alloc_func if @allocator.nil?
      return nil if @allocator == UNDEF_ALLOC_FUNC
      
      @allocator
    end

    def define_alloc_func(func)
      @allocator = func
    end

    def undef_alloc_func
      @allocator = UNDEF_ALLOC_FUNC
    end

    def rb_const_defined?(name)
      return true if @const_table.key?(name)

      result = find_constant_in_lexical_scope(name) || 
        find_constant_in_superclass(name)

      result ? true : false
    end

    def const_direct(name)
      @const_table[name]
    end

    def has_const_direct?(name)
      @const_table.key?(name)
    end

    def rb_const_get(name, check = true)
      return const_direct(name) if has_const_direct?(name)

      result = find_constant_in_lexical_scope(name) ||
               find_constant_in_superclass(name)

      # TODO: call missing const

      Core.rb_raise(Core.eNameError, "uninitialized constant #{name}") if check && result.nil?

      result
    end

    def has_const?(name)
      has_at = has_const_direct?(name)
      return has_at if has_at

      result = find_constant_in_lexical_scope(name) ||
               find_constant_in_superclass(name)

      !result.nil?
    end

    def find_constant_in_lexical_scope(name)
      scope = VM.instance.current_control_frame.environment
      while scope
        klass = scope.klass
        return klass.const_direct(name) if klass.has_const_direct?(name)
        scope = scope.next_scope
      end
      nil
    end

    def find_constant_in_superclass(name)
      return const_direct(name) if @const_table.key?(name)
      return nil unless super_class

      super_class.find_constant_in_superclass(name)
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

    def inherited?(arg)
        return Q_TRUE if self == arg
        if !arg.is_a?(RClass) && !arg.flags.include?(:ICLASS)
          rb_raise(eTypeError, "compared with non class/module")
        end

        # TODO: some origin thing?
        if arg.search_ancestor(self)
          return Q_TRUE
        end

        if self.search_ancestor(arg)
          return Q_FALSE
        end

        Q_NIL
    end

    def self.new_class(super_class)
      klass = new(Core.cClass, [:CLASS])
      klass.super_class = super_class
      if super_class && super_class != Q_UNDEF && super_class.has_metaclass?
        klass.ensure_eigenclass
      end
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

    def origin
      # TODO
      self
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
      metaclass&.flags&.include?(:SINGLETON)
    end

    def ensure_eigenclass
      if has_metaclass?
        metaclass
      else
        make_metaclass
      end
    end

    def include_module(mdl)
      changed = 0

      # TODO: ensure includable

      changed = include_modules_at(origin, mdl, true)
      if changed.nil?
        Core.rb_raise(Core.eArgError, 'cyclic include detected')
      end
    end

    def include_modules_at(c, mdl, search_super)
      method_changed = false
      constant_changed = false
      klass_m_tbl = origin.method_table

      # TODO: refinements?

      while mdl
        superclass_seen = false
        tbl = nil

        if klass_m_tbl && klass_m_tbl.equal?(mdl.method_table)
          return nil
        end

        p = super_class
        skip = false
        while p
          if p.flags.include?(:ICLASS)
            if p.method_table.equal?(mdl.method_table)
              if !superclass_seen
                c = p # move insertion point
              end
              skip = true
              break
            end
          elsif p.flags.include?(:CLASS)
            break unless search_super
            superclass_seen = true
          end

          p = p.super_class
        end

        if !skip
          iclass = mdl.make_include_class(c.super_class)
          c.super_class = iclass
          iclass.includer = self

          m = mdl
          m = m.klass if m.flags.include?(:ICLASS)
          m.add_subclass(iclass)

          # TODO: refinements?

          tbl = mdl.method_table
          method_changed = true if tbl && !tbl.empty?

          tbl = mdl.const_table
          constant_changed = true if tbl && !tbl.empty?
        end

        mdl = mdl.super_class
      end

      # TODO: would clear method and const caches here

      method_changed
    end

    def make_include_class(zuper = super_class)
      mod = self
      klass = RClass.new(klass, [:ICLASS])

      if mod.flags.include?(:ICLASS)
        mod = mod.klass
      end
      klass.method_table = method_table
      klass.const_table = const_table

      klass.super_class = zuper

      if mod.flags.include?(:ICLASS)
        klass.klass = mod.klass
      else
        klass.klass = mod
      end

      klass
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

  module Core
    def self.init_class_heirarchy
      @cBasicObject = boot_defclass(:BasicObject, nil)
      @cObject = boot_defclass(:Object, cBasicObject)
      # rb_gc_register_mark_object(rb_cObject) # TODO

      # resolve class name ASAP for order-independence
      # rb_class_name(rb_cObject); #TODO ??

      @cModule = boot_defclass(:Module, cObject)
      @cClass = boot_defclass(:Class, cModule)

      cObject.rb_const_set(:BasicObject, cBasicObject)
      cClass.klass = cClass
      cModule.klass = cClass
      cObject.klass = cClass
      cBasicObject.klass = cClass
    end
  end
end
