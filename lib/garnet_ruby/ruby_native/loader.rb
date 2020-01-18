module GarnetRuby
  module Core
    class RNative < RObject
      attr_accessor :value

      def initialize(klass, flags, value)
        super(klass, flags)
        @value = value
      end
    end
    
    @native_classes = {}

    class << self
      def call_native_method(obj, mid, *args)
        blk = nil
        if rb_block_given?
          blk = ->(*blargs) { rb_yield(*blargs) }
        end
        rb_args = args.map { |a| garnet2ruby(a) }
        ret = obj.value.__send__(mid, *rb_args, &blk)
        ruby2garnet(ret)
      end

      alias_method :orig_ruby2garnet, :ruby2garnet
      def ruby2garnet(value)
        return orig_ruby2garnet(value) unless @native_classes.key?(value.class)

        RNative.new(@native_classes[value.class], [], value)
      end

      def load_native_class(native, super_class = cObject, outer = cObject)
        name = native.name.split('::').last.to_sym
        klass = @native_classes[native] = rb_define_class_under(outer, name, super_class)
        rb_define_alloc_func(klass) do |k|
          RNative.new(k, [], native.allocate)
        end

        native.instance_methods(false).each do |mid|
          rb_define_method(klass, mid) { |obj, *args|
            call_native_method(obj, mid, *args)
          }
        end

        native.private_instance_methods(false).each do |mid|
          rb_define_private_method(klass, mid) { |obj, *args|
            call_native_method(obj, mid, *args)
          }
        end

        native.protected_instance_methods(false).each do |mid|
          # TODO: define protected method
          rb_define_method(klass, mid) { |obj, *args|
            call_native_method(obj, mid, *args)
          }
        end

        native.methods(false).each do |mid|
          rb_define_singleton_method(klass, mid) { |obj, *args|
            call_native_method(obj, mid, *args)
          }
        end

        native.private_methods(false).each do |mid|
          # TODO: define private method
          rb_define_singleton_method(klass, mid) { |obj, *args|
            call_native_method(obj, mid, *args)
          }
        end

        native.protected_methods(false).each do |mid|
          # TODO: define protected method
          rb_define_singleton_method(klass, mid) { |obj, *args|
            call_native_method(obj, mid, *args)
          }
        end
      end
    end
  end
end