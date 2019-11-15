module RubyRuby
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
    def self.init_object
      @mKernel = rb_define_module(:Kernel)
      cObject.include_module(mKernel)

      rb_define_method(mKernel, :to_s) do |obj|
        RString.new(cString, 0, "#<#{obj.klass.name},#{obj.__id__}>")
      end

      @cNilClass = rb_define_class(:NilClass)
      ::RubyRuby.const_set(:Q_NIL, RPrimitive.new(@cNilClass, 0, nil))

      @cTrueClass = rb_define_class(:TrueClass)
      ::RubyRuby.const_set(:Q_TRUE, RPrimitive.new(@cTrueClass, 0, true))

      @cFalseClass = rb_define_class(:FalseClass)
      ::RubyRuby.const_set(:Q_FALSE, RPrimitive.new(@cFalseClass, 0, false))
    end
  end
end
