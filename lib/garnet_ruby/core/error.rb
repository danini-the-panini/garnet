module GarnetRuby
  module Core
    class << self
      def make_exception(*args)
        # TODO: parse args

        RObject.new(eRuntimeError, [])
      end

      def exc_to_s(exc)
        mesg = exc.ivar_get(:message) || Q_NIL

        return exc.klass.name if mesg == Q_NIL
        mesg.rb_string
      end

      def exc_message(exc)
        rb_funcall(exc, :to_s)
      end
    end

    def self.init_exception
      @eException = rb_define_class(:Exception, cObject)
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

      rb_define_global_function(:raise) do |*args|
        exception = make_exception(*args)
        VM.instance.do_raise(exception)
        Q_UNDEF
      end
    end
  end
end
