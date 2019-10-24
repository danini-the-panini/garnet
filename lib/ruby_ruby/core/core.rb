module RubyRuby
  module Core
    class << self
      attr_reader :mKernel,
                  :mComparable,
                  :mEnumerable,
                  :mErrno,
                  :mFileTest,
                  :mGC,
                  :mMath,
                  :mProcess,
                  :mWaitReadable,
                  :mWaitWritable,
                  :cBasicObject,
                  :cObject,
                  :cArray,
                  :cBignum,
                  :cBinding,
                  :cClass,
                  :cCont,
                  :cData,
                  :cDir,
                  :cEncoding,
                  :cEnumerator,
                  :cFalseClass,
                  :cFile,
                  :cFixnum,
                  :cComplex,
                  :cFloat,
                  :cHash,
                  :cIO,
                  :cInteger,
                  :cMatch,
                  :cMethod,
                  :cModule,
                  :cNameErrorMesg,
                  :cNilClass,
                  :cNumeric,
                  :cProc,
                  :cRandom,
                  :cRange,
                  :cRational,
                  :cRegexp,
                  :cStat,
                  :cString,
                  :cStruct,
                  :cSymbol,
                  :cThread,
                  :cTime,
                  :cTrueClass,
                  :cUnboundMethod,
                  :eException,
                  :eStandardError,
                  :eSystemExit,
                  :eInterrupt,
                  :eSignal,
                  :eFatal,
                  :eArgError,
                  :eEOFError,
                  :eIndexError,
                  :eStopIteration,
                  :eKeyError,
                  :eRangeError,
                  :eIOError,
                  :eRuntimeError,
                  :eFrozenError,
                  :eSecurityError,
                  :eSystemCallError,
                  :eThreadError,
                  :eTypeError,
                  :eZeroDivError,
                  :eNotImpError,
                  :eNoMemError,
                  :eNoMethodError,
                  :eFloatDomainError,
                  :eLocalJumpError,
                  :eSysStackError,
                  :eRegexpError,
                  :eEncodingError,
                  :eEncCompatError,
                  :eScriptError,
                  :eNameError,
                  :eSyntaxError,
                  :eLoadError,
                  :eMathDomainError

      def init
        @cBasicObject = boot_defclass(:BasicObject, nil)
        @cObject = boot_defclass(:Object, cBasicObject)
        # rb_gc_register_mark_object(rb_cObject) # TODO

        # resolve class name ASAP for order-independence
        # rb_class_name(rb_cObject); #TODO ??

        @cModule = boot_defclass(:Module, cObject)
        @cClass = boot_defclass(:Class, cModule)

        cObject.rb_const_set(:BasicObject, cBasicObject)
        cClass.klass = cClass
        cModule.klass = cClass
        cObject.klass = cClass
        cBasicObject.klass = cClass

        init_object
        init_numeric
        init_io
      end

      def boot_defclass(name, super_class)
        obj = RClass.new_class(super_class)

        obj.name = name
        (cObject || obj).rb_const_set(name, obj)

        obj
      end

      def rb_define_class(name, super_class=cObject)
        if cObject.rb_const_defined?(name)
          klass = cObject.rb_const_get(name)
          raise TypeError, "#{name} is not a class (#{klass})" unless klass.flags.include?(:CLASS)
          raise TypeError, "superclass mismatch for class #{name}" if klass.super_class != super_class
          return klass
        end

        klass = RClass.new_class(super_class)
        # rb_vm_add_root_module(id, klass)
        klass.name = name
        cObject.rb_const_set(name, klass)
        # super_class.rb_class_inherited(klass)

        klass
      end

      def rb_define_module(name)
        if cObject.rb_const_defined?(name)
          mdl = cObject.rb_const_get(name)
          raise TypeError, "#{name} is not a module (#{mdl})" unless mdl.flags.include?(:MODULE)

          return mdl
        end

        mdl = RClass.new_module
        mdl.name = name

        cObject.rb_const_set(name, mdl)

        mdl
      end

      def rb_make_metaclass(obj)
        if obj.flags.include?(:CLASS)
          obj.make_metaclass
        else
          make_singleton_class(obj)
        end
      end

      def make_singleton_class(obj)
      end

      def singleton_class_of(obj)
        # TODO: do some checks

        klass = obj.klass
        unless klass.flags.include?(:SINGLETON)
          klass = rb_make_metaclass(obj)
        end

        klass
      end

      def rb_define_method(klass, name, &block)
        rb_add_method_cfunc(klass, name, :PUBLIC, &block)
      end

      def rb_define_protected_method(klass, name, &block)
        rb_add_method_cfunc(klass, name, :PROTECTED, &block)
      end

      def rb_define_private_method(klass, name, &block)
        rb_add_method_cfunc(klass, name, :PRIVATE, &block)
      end

      def rb_define_singleton_method(obj, name, &block)
        rb_define_method(singleton_class_of(obj), name, &block)
      end

      def rb_add_method_cfunc(klass, name, visibility, &block)
        klass ||= cObject

        # TODO: check re-definition

        # create method entry
        me = BuiltInMethod.new(name, klass, visibility, &block)

        # TODO: check mid

        klass.method_table[name] = me

        me
      end

      def rb_define_global_function(name, &block)
        rb_define_module_method(mKernel, name, &block)
      end

      def rb_define_module_method(mdl, name, &block)
        rb_define_private_method(mdl, name, &block)
        rb_define_singleton_method(mdl, name, &block)
      end

      def rb_funcall(recv, mid, *args)
        VM.instance.rb_call(recv, mid, *args)
      end
    end
  end
end
