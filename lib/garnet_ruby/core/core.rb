module GarnetRuby
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

      attr_reader :env_table

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
        init_exception
        init_symbol
        init_numeric
        init_range
        init_string
        init_array
        init_hash
        init_regexp
        init_proc
        init_io

        @env_table = RHash.from(ENV)
        cObject.rb_const_set(:ENV, env_table)
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
        orig_class = obj.klass
        klass = RClass.new_class(orig_class)

        klass.flags |= [:SINGLETON]
        obj.klass = klass
        # obj.singleton_class_attached(klass) # TODO

        klass.metaclass = orig_class.real.metaclass
        klass
      end

      def singleton_class_of(obj)
        # TODO: do some checks

        if obj.is_a?(RPrimitive)
          raise TypeError, "can't define singleton"
        end
        # TODO: special const?
        # TODO: builtin type?

        klass = obj.klass
        unless klass.flags.include?(:SINGLETON)
          klass = rb_make_metaclass(obj)
        end

        klass
      end

      def rb_define_method(klass, name, &block)
        rb_add_method_cfunc(klass, name, :PUBLIC, &block)
      end

      def rb_alias_method(klass, alias_name, orig_name)
        orig_me = search_method(klass, orig_name)
        if !orig_me || orig_me.is_a?(UndefinedMethod)
          raise "undefined method #{orig_name} for #{klass}"
        end

        klass.method_table[alias_name] = AliasMethod.new(alias_name, klass, :PUBLIC, orig_me)
      end

      def search_method(klass, name)
        loop do
          m = klass.method_table[name]
          return m if m

          klass = klass.super_class
          return nil if klass.nil?
        end
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

      def rtest(value)
        value != Q_FALSE && value != Q_NIL
      end

      def check_match(target, pattern, type)
        if type == :rescue
          # TODO: check that pattern is kind_of?(Module)
        end
        case type
        when :rescue, :case
          rb_funcall(pattern, :===, target)
        else
          Q_NIL
        end
      end

      def ruby2garnet(value)
        case value
        when NilClass then Q_NIL
        when TrueClass then Q_TRUE
        when FalseClass then Q_FALSE
        when Symbol then RSymbol.from(value)
        when String then RString.from(value)
        when Integer, Float then RPrimitive.from(value)
        when Regexp then RRegexp.from(value)
        when Array then RArray.from(value)
        when Hash then RHash.from(value)
        when Range then RRange.from(value)
        when RBasic then value
        else raise "CANNOT CONVERT TO GARNET OBJECT: #{value}"
        end
      end
    end
  end
end
