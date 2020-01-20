module GarnetRuby
  module Core
    class << self
      def exc_new(type, *args)
        message = args.empty? ? RString.from('') : args.first
        exc = type.alloc
        rb_funcall(exc, :initialize, message)
        exc
      end

      def exc_initialize(exc, message = Q_NIL)
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
          mesg = rb_check_funcall(exc, :exception, *exception_call)
          if mesg == Q_UNDEF
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

      def exc_backtrace(exc)
        exc.ivar_get(:backtrace) || Q_NIL
      end

      def exit_initialize(exc, *args)
        unless args.empty?
          status = args[0]

          case status
          when Q_TRUE
            status = RPrimitive.from(EXIT_SUCCESS)
            args.shift
          when Q_FALSE
            status = RPrimitive.from(EXIT_FAILURE)
            args.shift
          else
            status = status.check_to_int
            if status == Q_NIL
              status = RPrimitive.from(EXIT_SUCCESS)
            else
              args.shift
            end
          end
        else
          status = RPrimitive.from(EXIT_SUCCESS)
        end
        rb_call_super(*args)
        exc.ivar_set(:status, status)
        exc
      end

      def exit_status(exc)
        exc.ivar_get(:status) || Q_NIL
      end

      def exit_success_p(exc)
        status_val = exit_status(exc)

        return Q_TRUE if status_val == Q_NIL

        status = num2long(status_val)
        return Q_TRUE if status == EXIT_SUCCESS

        Q_FALSE
      end

      def rb_raise(exc, mesg = nil)
        rb_exc_raise(make_exception(exc, RString.from(mesg || '')))
      end

      def rb_exc_raise(exc)
        VM.instance.do_raise(exc)
      end
    end

    def self.init_exception
      @eException = rb_define_class(:Exception, cObject)
      rb_define_singleton_method(eException, :exception, &method(:rb_class_new_instance))
      rb_define_method(eException, :exception, &method(:exc_exception))
      rb_define_method(eException, :initialize, &method(:exc_initialize))
      rb_define_method(eException, :to_s, &method(:exc_to_s))
      rb_define_method(eException, :message, &method(:exc_message))
      rb_define_method(eException, :backtrace, &method(:exc_backtrace))

      @eSystemExit = rb_define_class(:SystemExit, eException)
      rb_define_method(eSystemExit, :initialize, &method(:exit_initialize))
      rb_define_method(eSystemExit, :status, &method(:exit_status))
      rb_define_method(eSystemExit, :success?, &method(:exit_success_p))

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
      @eFrozenError = rb_define_class(:FrozenError, eRuntimeError)
      @eSecurityError = rb_define_class(:SecurityError, eException)
      @eNoMemError = rb_define_class(:NoMemoryError, eException)
      @eEncodingError = rb_define_class(:EncodingError, eStandardError)
      @eEncCompatError = rb_define_class_under(cEncoding, :CompatibilityError, eEncodingError)
      @eNoMatchingPatternError = rb_define_class(:NoMatchingPatternError, eRuntimeError)

      @eSystemCallError = rb_define_class(:SystemCallError, eStandardError)

      @mErrno = rb_define_module(:Errno)

      @syserr_tbl = {}
      Errno.constants.each do |name|
        n = Errno.const_get(name)::Errno
        @syserr_tbl[n] = error = rb_define_class_under(mErrno, name, eSystemCallError)
        rb_define_const(error, :Errno, RPrimitive.from(n))
      end

      # TODO: more errors

      rb_define_global_function(:raise) do |_, *args|
        exception = make_exception(*args)
        VM.instance.do_raise(exception)
        Q_UNDEF
      end
    end
  end
end
