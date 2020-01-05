module GarnetRuby
  module Core
    class << self
      def exc_new(type, message)
        exc = type.alloc
        rb_funcall(exc, :initialize, message)
        exc
      end

      def exc_init(exc, message = Q_NIL)
        exc.ivar_set(:message, message)
        exc
      end

      def make_exception(*args)
        exception_call = nil
        mesg = Q_NIL
        case args.length
        when 1
          exc = args.first
          if exc != Q_NIL
            mesg = exc.check_string_type
            if mesg != Q_NIL
              mesg = exc_new(eRuntimeError, mesg)
            else
              exception_call = []
            end
          end
        when 2..3
          exc = args.first
          exception_call = [args[1]]
        else
          # arity error
        end

        if exception_call
          p exc.name
          p exception_call
          p VM.instance.rb_respond_to(exc, :exception)
          mesg = rb_check_funcall(exc, :exception, *exception_call)
          if mesg == Q_UNDEF
            raise mesg
            rb_raise(eTypeError, "exception class/object expected")
          end
        end

        if args.length > 0
          if !obj_is_kind_of(mesg, eException)
            rb_raise(eTypeError, "exception object expected")
          end
          # TODO: set backtrace
        end

        mesg
      end

      def exc_exception(exc, *args)
        return exc if args.length == 0
        return exc if args.length == 1 && exc == args[0]
        exc = rb_obj_clone(exc)
        exc.ivar_set(:message, args[0])
        exc
      end

      def exc_to_s(exc)
        mesg = exc.ivar_get(:message) || Q_NIL

        return RString.from(exc.klass.name.to_s) if mesg == Q_NIL
        mesg.rb_string
      end

      def exc_message(exc)
        rb_funcall(exc, :to_s)
      end

      def rb_raise(exc, mesg = nil)
        VM.instance.do_raise(make_exception(exc, RString.from(mesg || "")))
      end
    end

    def self.init_exception
      @eException = rb_define_class(:Exception, cObject)
      rb_define_singleton_method(eException, :exception, &method(:rb_class_new_instance))
      rb_define_method(eException, :exception, &method(:exc_exception))
      rb_define_method(eException, :to_s, &method(:exc_to_s))
      rb_define_method(eException, :message, &method(:exc_message))

      @eSystemExit = rb_define_class(:SystemExit, eException)

      @eFatal  	    = rb_define_class(:fatal, eException)
      @eSignal      = rb_define_class(:SignalException, eException)
      @eInterrupt   = rb_define_class(:Interrupt, eSignal)

      @eStandardError = rb_define_class(:StandardError, eException)
      @eTypeError     = rb_define_class(:TypeError, eStandardError)
      @eArgError      = rb_define_class(:ArgumentError, eStandardError)
      @eIndexError    = rb_define_class(:IndexError, eStandardError)
      @eKeyError      = rb_define_class(:KeyError, eIndexError)
      #
      @eRangeError    = rb_define_class(:RangeError, eStandardError)

      @eScriptError = rb_define_class(:ScriptError, eException)
      @eSyntaxError = rb_define_class(:SyntaxError, eScriptError)

      @eLoadError   = rb_define_class(:LoadError, eScriptError)

      @eNotImpError = rb_define_class(:NotImplementedError, eScriptError)

      @eNameError     = rb_define_class(:NameError, eStandardError)
      #
      @eNoMethodError = rb_define_class(:NoMethodError, eNameError)

      @eRuntimeError = rb_define_class(:RuntimeError, eStandardError)

      # TODO: more errors

      rb_define_global_function(:raise) do |_, *args|
        exception = make_exception(*args)
        VM.instance.do_raise(exception)
        Q_UNDEF
      end
    end
  end
end
