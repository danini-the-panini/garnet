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
      def obj_is_kind_of(obj, c)
        cl = obj.klass

        # TODO: make sure c is a module/class
        c.search_ancestor(cl) ? Q_TRUE : Q_FALSE
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

      def rb_caller(_, *args)
        VM.instance.backtrace_to_ary(args, 1, true)
      end

      def rb_loop(_)
        vm = VM.instance
        vm.while_current_control_frame do
          vm.rb_yield()
        end
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
      rb_define_private_method(cBasicObject, :initialize) { nil }
      rb_define_method(cBasicObject, :==, &method(:obj_equal))
      rb_define_method(cBasicObject, :'!', &method(:obj_not))
      rb_define_method(cBasicObject, :'!=', &method(:obj_not_equal))

      @mKernel = rb_define_module(:Kernel)
      cObject.include_module(mKernel)

      rb_define_method(mKernel, :=~) { Q_NIL }
      rb_define_method(mKernel, :'!~', &method(:obj_not_match))
      rb_define_method(mKernel, :eql?, &method(:obj_equal))
      rb_define_method(mKernel, :hash, &method(:obj_hash))

      rb_define_method(mKernel, :to_s) do |obj|
        RString.from("#<#{obj.klass.name},#{obj.__id__}>")
      end
      rb_alias_method(cObject, :inspect, :to_s)

      rb_define_method(mKernel, :kind_of?, &method(:obj_is_kind_of))

      @cNilClass = rb_define_class(:NilClass)
      ::GarnetRuby.const_set(:Q_NIL, RPrimitive.new(@cNilClass, [], nil))
      rb_define_method(cNilClass, :to_s) do |obj|
        RString.from('')
      end

      rb_define_method(cModule, :===) do |mod, arg|
        obj_is_kind_of(arg, mod)
      end

      rb_define_method(cClass, :new) do |klass, *args|
        obj = klass.alloc
        rb_funcall(obj, :initialize, *args)
        obj
      end

      @cTrueClass = rb_define_class(:TrueClass)
      ::GarnetRuby.const_set(:Q_TRUE, RPrimitive.new(@cTrueClass, [], true))

      @cFalseClass = rb_define_class(:FalseClass)
      ::GarnetRuby.const_set(:Q_FALSE, RPrimitive.new(@cFalseClass, [], false))

      rb_define_global_function(:caller, &method(:rb_caller))

      rb_define_global_function(:loop, &method(:rb_loop))
    end
  end
end
