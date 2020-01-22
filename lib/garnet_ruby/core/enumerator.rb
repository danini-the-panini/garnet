module GarnetRuby
  class REnumerator < RObject
    attr_accessor :obj, :meth, :args, :fix, :dst, :lookahead, :feedvalue, :stop_exc, :size, :size_fn

    def initialize(klass, flags)
      super(klass, flags)
    end

    def size
      return size_fn.call if size_fn
      size
    end
  end

  module Core
    class << self
      def enumerator_allocate(klass)
        REnumerator.new(klass, [])
      end

      def enumerator_init(enum, obj, meth, args, size_fn, size)
        enum.obj = obj
        enum.meth = meth.to_id
        enum.args = RArray.from(args)
        enum.dst = Q_NIL
        enum.lookahead = Q_UNDEF
        enum.feedvalue = Q_UNDEF
        enum.stop_exc = Q_FALSE
        enum.size = size
        enum.size_fn = size_fn
        
        enum
      end

      def enumeratorize(obj, meth, args)
        enumeratorize_with_size(obj, meth, args, nil)
      end

      def enumeratorize_with_size(obj, meth, args, size_fn)
        # TODO: support lazy

        enumerator_init(enumerator_allocate(cEnumerator),
                        obj, meth, args, size_fn, Q_NIL)
      end

      def enumerator(obj, args)
        sized_enumerator(obj, args, nil)
      end

      def sized_enumerator(obj, args, size_fn)
        enumeratorize_with_size(obj, RSymbol.from(VM.instance.frame_this_func), args, size_fn)
      end

      def enumerator_allocate(klass)
        enum_obj = REnumerator.new(klass, [])
        enum_obj.obj = Q_UNDEF

        enum_obj
      end

      def enumerator_initialize(obj, *args)
        if rb_block_given?
          # TODO: Enumerator.new(size = nil) { |yielder| ... }
        else
          recv = args.unshift
          meth = args.unshift unless args.empty?
        end

        enumerator_init(obj, recv, meth, args, nil, size)
      end

      def enumerator_init_copy(obj, orig)
        return obj unless obj != orig && rtest(obj_init_copy(obj, orig))

        obj.obj = orig.obj
        obj.meth = orig.meth
        obj.args = orig.args
        obj.lookahead = Q_UNDEF
        obj.feedvalue = Q_UNDEF
        obj.size = orig.size
        obj.size_fn = orig.size_fn

        obj
      end

      def enumerator_each(obj, *argv)
        unless argv.empty?
          obj = obj_dup(obj)
          args = obj.args
          if args
            args = ary_dup(args)
            args.array_value += argv
          else
            args = RArray.from([])
          end
          obj.args = args
          obj.size = Q_NIL
          obj.size_fn = nil
        end
        return obj unless rb_block_given?
        enumerator_block_call(obj)
      end

      def enumerator_block_call(obj)
        target = obj.obj
        mid = obj.meth
        args = obj.args.array_value
        block = rb_block
        rb_funcall_with_block(target, mid, block, *args)
      end
    end

    def self.init_enumerator
      @cEnumerator = rb_define_class(:Enumerator)
      cEnumerator.include_module(mEnumerable)

      rb_define_alloc_func(cEnumerator, &method(:enumerator_allocate))
      rb_define_method(cEnumerator, :initialize, &method(:enumerator_initialize))
      rb_define_method(cEnumerator, :initialize_copy, &method(:enumerator_init_copy))
      rb_define_method(cEnumerator, :each, &method(:enumerator_each))
    end
  end
end