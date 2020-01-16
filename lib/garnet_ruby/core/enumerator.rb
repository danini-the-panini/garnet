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

      def sized_enumerator(obj, args, size_fn)
        enumeratorize_with_size(obj, RSymbol.from(VM.instance.frame_this_func), args, size_fn)
      end
    end

    def self.init_enumerator
      @cEnumerator = rb_define_class(:Enumerator)
    end
  end
end