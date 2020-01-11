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

      def rb_obj_clone(obj)
        clone = obj.klass.alloc
        # TODO: clone singleton class and attach

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
        obj.klass
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

      rb_define_method(mKernel, :to_s) do |obj|
        RString.from("#<#{obj.klass.name},#{obj.__id__}>")
      end
      rb_alias_method(cObject, :inspect, :to_s)

      rb_define_method(mKernel, :kind_of?, &method(:obj_is_kind_of))

      rb_define_global_function(:sprintf, &method(:f_sprintf))

      @cNilClass = rb_define_class(:NilClass)
      ::GarnetRuby.const_set(:Q_NIL, RPrimitive.new(@cNilClass, [], nil))
      rb_define_method(cNilClass, :to_s) do |obj|
        RString.from('')
      end
      rb_define_global_const(:NIL, Q_NIL)

      rb_define_method(cModule, :===) do |mod, arg|
        obj_is_kind_of(arg, mod)
      end

      rb_define_alloc_func(cModule, &method(:rb_module_s_alloc))

      rb_define_method(cClass, :new, &method(:rb_class_new_instance))
      rb_define_alloc_func(cClass, &method(:rb_class_s_alloc))

      @cTrueClass = rb_define_class(:TrueClass)
      ::GarnetRuby.const_set(:Q_TRUE, RPrimitive.new(@cTrueClass, [], true))
      rb_define_global_const(:TRUE, Q_TRUE)

      @cFalseClass = rb_define_class(:FalseClass)
      ::GarnetRuby.const_set(:Q_FALSE, RPrimitive.new(@cFalseClass, [], false))
      rb_define_global_const(:FALSE, Q_FALSE)

      rb_define_global_function(:caller, &method(:rb_caller))

      rb_define_global_function(:loop, &method(:rb_loop))
    end
  end
end
