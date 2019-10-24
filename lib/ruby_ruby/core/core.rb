require "ruby_ruby/core/basic"
require "ruby_ruby/core/object"
require "ruby_ruby/core/class"

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

        cObject.set_const(:BasicObject, cBasicObject)
        cClass.klass = cClass
        cModule.klass = cClass
        cObject.klass = cClass
        cBasicObject.klass = cClass
      end

      def boot_defclass(name, super_class)
        obj = RClass.boot(super_class)

        obj.name = name
        (cObject || obj).set_const(name, obj)

        obj
      end
    end
  end
end
