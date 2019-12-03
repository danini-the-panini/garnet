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
    end

    def self.init_object
      @mKernel = rb_define_module(:Kernel)
      cObject.include_module(mKernel)

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

      @cTrueClass = rb_define_class(:TrueClass)
      ::GarnetRuby.const_set(:Q_TRUE, RPrimitive.new(@cTrueClass, [], true))

      @cFalseClass = rb_define_class(:FalseClass)
      ::GarnetRuby.const_set(:Q_FALSE, RPrimitive.new(@cFalseClass, [], false))
    end
  end
end
