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
    end

    def self.init_object
      rb_define_private_method(cBasicObject, :initialize) { nil }

      @mKernel = rb_define_module(:Kernel)
      cObject.include_module(mKernel)

      rb_define_method(mKernel, :=~) { Q_NIL }
      rb_define_method(mKernel, :'!~', &method(:obj_not_match))

      rb_define_method(mKernel, :to_s) do |obj|
        RString.from("#<#{obj.klass.name},#{obj.__id__}>")
      end
      rb_alias_method(cObject, :inspect, :to_s)

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
    end
  end
end
