module GarnetRuby
  class RObject < RBasic
    attr_reader :ivars

    def initialize(klass, flags)
      super
      @ivars = {}
    end

    def ivar_set(k, v)
      @ivars[k] = v
    end

    def ivar_get(k)
      @ivars[k]
    end
  end

  module Core
    class << self
      def rb_class_allocate_instance(klass)
        RObject.new(klass, [])
      end

      def rb_module_s_alloc(_)
        RClass.new(cModule, [:MODULE])
      end

      def rb_class_s_alloc(_)
        RClass.new(cClass, [:CLASS])
      end

      def rb_class_new_instance(klass, *args)
        obj = klass.alloc
        rb_funcall(obj, :initialize, *args)
        obj
      end

      def singleton_class_clone(obj)
        singleton_class_clone_and_attach(obj, Q_UNDEF)
      end

      def singleton_class_clone_and_attach(obj, attach)
        klass = obj.klass

        if !klass.flags.include?(:SINGLETON)
          return klass
        end

        clone = RClass.new(nil, klass.flags)
        if obj.flags.include?(:CLASS)
          clone.klass = clone
        else
          clone.klass = singleton_class_clone(klass)
        end

        clone.super_class = klass.super_class
        clone.allocator = klass.allocator
        # TODO: copy iv table?
        if klass.const_table
          klass.const_table.each do |k,v|
            clone.const_table[k] = v
          end
        end
        # if attach != Q_UNDEF
        #   rb_singleton_class_attached(clone, attach)
        # end

        klass.method_table.each do |k,v|
          clone.method_table[k] = clone_method(klass, clone, k, v)
        end
        # rb_singleton_class_attached(clone.klass, clone)
        clone.flags |= [:SINGLETON]
      
        clone
      end

      def rb_obj_clone(obj)
        clone = obj_class(obj).alloc

        singleton = singleton_class_clone_and_attach(obj, clone)
        clone.klass = singleton
        # TODO
        # if singleton.flags.include?(:SINGLETON)
        #   rb_singleton_class_attached(singleton, clone)
        # end

        init_copy(clone, obj)
        rb_funcall(clone, :initialize_clone, obj)

        clone
      end

      def init_copy(clone, obj)
        rb_copy_generic_ivar(clone, obj)
      end

      def rb_copy_generic_ivar(clone, obj)
        obj.ivars.each do |k, v|
          clone.ivar_set(clone, obj)
        end
      end

      def obj_is_kind_of(obj, c)
        cl = obj.klass

        # TODO: make sure c is a module/class
        c.search_ancestor(cl) ? Q_TRUE : Q_FALSE
      end

      def f_sprintf(_, *args)
        rb_sprintf(*args)
      end

      def obj_not_match(obj1, obj2)
        result = rb_funcall(obj1, :=~, obj2)
        rtest(result) ? Q_FALSE : Q_TRUE
      end

      def obj_equal(obj1, obj2)
        obj1 == obj2 ? Q_TRUE : Q_FALSE
      end

      def obj_not(obj)
        rtest(obj) ? Q_FALSE : Q_TRUE
      end

      def obj_not_equal(obj1, obj2)
        result = rb_funcall(obj1, :==, obj2)
        rtest(result) ? Q_FALSE : Q_TRUE
      end

      def obj_hash(obj)
        v = obj.__id__
        RPrimitive.from(v ^ (v >> 32))
      end

      def check_id(name)
        if name.type?(Symbol)
          name.symbol_value
        elsif name.type?(String)
          name.string_value.to_sym
        else
          tmp = name.check_string_type
          if tmp == Q_NIL
            raise TypeError, "#{name} is not a symbol or a string"
          end
          tmp.string_value.to_sym
        end
      end

      def obj_method(obj, vid)
        id = check_id(vid)
        klass = obj.klass
        mclass = cMethod

        me = find_method(klass, id)

        RMethod.new(mclass, [], me, obj)
      end

      def obj_class(obj)
        obj.klass.real
      end

      def obj_clone(obj)
        # TODO: freeze kwarg
        rb_obj_clone(obj)
      end

      def obj_init_copy(obj, orig)
        return obj if obj == orig
        # TODO: check frozen
        if obj.type != orig.type || obj_class(obj) != obj_class(orig)
          rb_raise(eTypeError, 'initialize_copy should take same class object')
        end
        obj
      end

      def obj_init_dup_clone(obj, orig)
        rb_funcall(obj, :initialize_copy, orig)
        obj
      end

      def rb_caller(_, *args)
        VM.instance.backtrace_to_ary(args, 1, true)
      end

      def rb_loop(_)
        loop do
          rb_yield
        end
      rescue VM::GarnetThrow => e
        raise unless e.throw_type == :break
        e.value
      end

      def rb_equal(obj1, obj2)
        return Q_TRUE if obj1 == obj2

        result = rb_funcall(obj1, :==, obj2)
        rtest(result) ? Q_TRUE : Q_FALSE
      end

      def rb_eql(obj1, obj2)
        return Q_TRUE if obj1 == obj2

        result = rb_funcall(obj1, :eql?, obj2)
        rtest(result) ? Q_TRUE : Q_FALSE
      end

      def mod_cmp(mod, arg)
        return RPrimitive.from(0) if mod == arg
        return Q_NIL unless arg.is_a?(RClass)

        cmp = mod.inherited?(arg)
        return Q_NIL if cmp == Q_NIL
        if rtest(cmp)
          RPrimitive.from(-1)
        else
          RPrimitive.from(1)
        end
      end

      def mod_name(mod)
        RString.from(mod.name)
      end

      def mod_ancestors(mod)
        ary = RArray.from([])

        p = mod
        while p
          # TODO: something to do with origin
          next if p != p.origin

          if p.flags.include?(:ICLASS)
            ary_push(ary, p.klass)
          else
            ary_push(ary, p)
          end

          p = p.super_class
        end

        ary
      end
    end

    def self.init_object
      rb_define_private_method(cBasicObject, :initialize) { Q_NIL }
      rb_define_alloc_func(cBasicObject, &method(:rb_class_allocate_instance))
      rb_define_method(cBasicObject, :==, &method(:obj_equal))
      rb_define_method(cBasicObject, :equal?, &method(:obj_equal))
      rb_define_method(cBasicObject, :'!', &method(:obj_not))
      rb_define_method(cBasicObject, :'!=', &method(:obj_not_equal))

      @mKernel = rb_define_module(:Kernel)
      cObject.include_module(mKernel)

      rb_define_method(mKernel, :=~) { Q_NIL }
      rb_define_method(mKernel, :'!~', &method(:obj_not_match))
      rb_define_method(mKernel, :eql?, &method(:obj_equal))
      rb_define_method(mKernel, :hash, &method(:obj_hash))
      rb_define_method(mKernel, :method, &method(:obj_method))

      rb_define_method(mKernel, :class, &method(:obj_class))
      rb_define_method(mKernel, :clone, &method(:obj_clone))
      rb_define_method(mKernel, :initialize_copy, &method(:obj_init_copy))
      rb_define_method(mKernel, :initialize_dup, &method(:obj_init_dup_clone))
      rb_define_method(mKernel, :initialize_clone, &method(:obj_init_dup_clone))

      rb_define_method(mKernel, :to_s) do |obj|
        RString.from("#<#{obj.klass.name},#{obj.__id__}>")
      end
      rb_alias_method(cObject, :inspect, :to_s)

      rb_define_method(mKernel, :kind_of?, &method(:obj_is_kind_of))

      rb_define_global_function(:sprintf, &method(:f_sprintf))

      @cNilClass = rb_define_class(:NilClass)
      ::GarnetRuby.const_set(:Q_NIL, RPrimitive.new(@cNilClass, [], nil))
      rb_define_method(cNilClass, :to_i) { |_| RPrimitive.from(0) }
      rb_define_method(cNilClass, :to_s) { |_| RString.from('') }
      rb_define_method(cNilClass, :inspect) { |_| RString.from('nil') }
      rb_define_global_const(:NIL, Q_NIL)

      rb_define_method(cModule, :===) do |mod, arg|
        obj_is_kind_of(arg, mod)
      end
      rb_define_method(cModule, :<=>, &method(:mod_cmp))
      rb_define_method(cModule, :name, &method(:mod_name))
      rb_define_method(cModule, :ancestors, &method(:mod_ancestors))

      rb_define_alloc_func(cModule, &method(:rb_module_s_alloc))

      rb_define_method(cClass, :new, &method(:rb_class_new_instance))
      rb_define_alloc_func(cClass, &method(:rb_class_s_alloc))

      @cTrueClass = rb_define_class(:TrueClass)
      ::GarnetRuby.const_set(:Q_TRUE, RPrimitive.new(@cTrueClass, [], true))
      rb_define_method(cTrueClass, :to_s) { |_| RString.from("true") }
      rb_alias_method(cTrueClass, :inspect, :to_s)
      rb_define_global_const(:TRUE, Q_TRUE)

      @cFalseClass = rb_define_class(:FalseClass)
      ::GarnetRuby.const_set(:Q_FALSE, RPrimitive.new(@cFalseClass, [], false))
      rb_define_method(cFalseClass, :to_s) { |_| RString.from("false") }
      rb_alias_method(cFalseClass, :inspect, :to_s)
      rb_define_global_const(:FALSE, Q_FALSE)

      rb_define_global_function(:caller, &method(:rb_caller))

      rb_define_global_function(:loop, &method(:rb_loop))
    end
  end
end
