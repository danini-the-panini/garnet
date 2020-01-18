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
                  :eMathDomainError,
                  :mMarshal,
                  :mSignal

      attr_reader :env_table, :stdin, :stdout, :stderr

      def init
        @virtual_variables = {}

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
        init_top_self
        init_vm_eval
        init_vm_method
        init_eval
        init_symbol
        init_numeric
        init_math
        init_enum
        init_enumerator
        init_comparable
        init_range
        init_string
        init_encoding
        init_exception
        init_array
        init_hash
        init_regexp
        init_proc
        init_io
        init_file
        init_dir
        init_signal
        init_process
        init_marshal
        init_struct
        init_load
        init_version

        @env_table = RHash.new(cHash, [])
        cObject.rb_const_set(:ENV, env_table)

        @required_files = {}
      end

      def init_top_self
        @top_self = RObject.new(cObject, [])
        rb_define_singleton_method(@top_self, :to_s) { |_| RString.from("main") }
        rb_alias_method(singleton_class_of(@top_self), :inspect, :to_s)
      end

      def boot_defclass(name, super_class)
        obj = RClass.new_class(super_class)

        obj.name = name
        (cObject || obj).rb_const_set(name, obj)

        obj
      end

      def rb_define_class(name, super_class=cObject)
        if cObject.has_const_direct?(name)
          klass = cObject.rb_const_get(name, false)
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

      def rb_define_class_under(outer, name, super_class)
        define_class_id_under(outer, name, super_class)
      end

      def rb_define_module(name)
        if cObject.has_const_direct?(name)
          mdl = cObject.rb_const_get(name, false)
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

      def rb_vm_top_self
        @top_self
      end

      def method_entry_create(name, klass, visibility, definition)
        flags = ruby_running ? [] : [:basic]
        MethodEntry.new(name, klass, visibility, definition, flags)
      end

      def rb_define_method(klass, name, &block)
        rb_add_method_cfunc(klass, name, :public, &block)
      end

      def rb_undef_method(klass, name)
        definition = UndefinedMethodDef.new(&block)
        me = method_entry_create(name, klass, :public, definition)
        klass.method_table[name] = me
        me
      end

      def rb_define_alloc_func(klass, &func)
        klass.define_alloc_func(func)
      end

      def rb_undef_alloc_func(klass)
        klass.undef_alloc_func
      end

      def rb_alias_method(klass, alias_name, orig_name)
        orig_me, _ = search_method(klass, orig_name)
        if !orig_me || orig_me.definition.is_a?(UndefinedMethodDef)
          rb_raise(eNoMethodError, "undefined method #{orig_name} for #{klass}")
        end

        definition = AliasMethodDef.new(orig_me)
        klass.method_table[alias_name] = method_entry_create(alias_name, klass, :public, definition)
      end

      def search_method(klass, name)
        loop do
          m = klass.method_table[name]
          return m, klass if m

          klass = klass.super_class
          return nil, nil if klass.nil?
        end
      end

      def ruby_running
        VM.instance&.running
      end

      def rb_define_protected_method(klass, name, &block)
        rb_add_method_cfunc(klass, name, :protected, &block)
      end

      def rb_define_private_method(klass, name, &block)
        rb_add_method_cfunc(klass, name, :private, &block)
      end

      def rb_define_singleton_method(obj, name, &block)
        rb_define_method(singleton_class_of(obj), name, &block)
      end

      def rb_define_module_function(obj, name, &block)
        rb_define_private_method(obj, name, &block)
        rb_define_singleton_method(obj, name, &block)
      end

      def rb_add_method(klass, name, visibility, definition)
        me = method_entry_create(name, klass, visibility, definition)
        klass.method_table[name] = me
      end

      def rb_add_method_cfunc(klass, name, visibility, &block)
        klass ||= cObject

        # TODO: check re-definition

        # create method entry
        definition = BuiltInMethodDef.new(&block)

        # TODO: check mid

        rb_add_method(klass, name, visibility, definition)
      end

      def clone_method(old_klass, new_klass, mid, me)
        method_entry_create(mid, new_klass, me.visibility, me.definition)
      end

      def rb_define_global_function(name, &block)
        rb_define_module_function(mKernel, name, &block)
      end

      def rb_define_global_const(name, value)
        rb_define_const(cObject, name, value)
      end

      def rb_define_const(klass, name, value)
        klass.rb_const_set(name, value)
      end

      def rb_define_global_variable(name, value)
        @initial_gvars ||= {}
        @initial_gvars[name] = value
      end

      def rb_define_virtual_variable(name, getter, setter)
        @virtual_variables[name] = [getter, setter]
      end

      def virtual_variable_get(name)
        @virtual_variables[name][0].call
      end

      def virtual_variable?(name)
        @virtual_variables.key?(name)
      end

      def virtual_variable_set(name, value)
        setter = @virtual_variables[name][1]
        if setter
          setter.call(value)
        else
          rb_raise(eNameError, "#{name} is a read-only variable")
        end
        value
      end

      def inject_env(vm)
        ENV.each do |k, v|
          hash_aset(@env_table, RString.from(k), RString.from(v))
        end
      end

      def inject_global_variables(vm, cmd_gvars)
        @initial_gvars.each do |k, v|
          vm.set_global(k, v)
        end
        if cmd_gvars
          cmd_gvars.each do |k, v|
            val = case v
                  when TrueClass then Q_TRUE
                  else RString.from(v)
                  end
            vm.set_global("$#{k}".to_sym, val)
          end
        end
      end

      def rb_define_module_function(mdl, name, &block)
        rb_define_private_method(mdl, name, &block)
        rb_define_singleton_method(mdl, name, &block)
      end

      def find_method(klass, mid)
        method = klass.method_table[mid]
        while method.nil?
          klass = klass.super_class
          return nil if klass.nil?
          method = klass.method_table[mid]
        end
        method
      end

      def rb_funcall(recv, mid, *args)
        VM.instance.rb_call(recv, mid, *args)
      end

      def rb_funcall_with_block(recv, mid, block, *args)
        VM.instance.rb_call_with_block(recv, mid, block, *args)
      end

      def rb_check_funcall(recv, mid, *args)
        VM.instance.rb_check_funcall(recv, mid, *args)
      end

      def rb_check_funcall_default(recv, mid, df, *args)
        VM.instance.rb_check_funcall_default(recv, mid, df, *args)
      end

      def rb_respond_to?(value, mid)
        method = find_method(value.klass, mid)
        return false if method.nil? || method.definition.is_a?(UndefinedMethodDef)
        true
      end

      def rb_block
        VM.instance.current_control_frame.block
      end

      def rb_block_given?
        !rb_block.nil?
      end

      def rb_block_arity
        rb_block.arity
      end

      def rb_yield(*args)
        VM.instance.rb_yield(*args)
      end

      def rb_block_call(recv, mid, *args, &block)
        VM.instance.rb_block_call(recv, mid, *args, &block)
      end

      def rb_block_proc
        rb_block.proc
      end

      def proc_ptr(proc)
        -> (*args) {
          rb_funcall(proc, :call, *args.map { |a| ruby2garnet(a) })
        }
      end

      def rb_call_super(*args)
        VM.instance.call_super(*args)
      end

      def rb_method_basic_definition?(klass, mid)
        me = find_method(klass, mid)
        me.basic?
      end

      def rtest(value)
        value != Q_FALSE && value != Q_NIL
      end

      def check_match(target, pattern, type)
        if type == :rescue
          # TODO: check that pattern is kind_of?(Module)
        end
        case type
        when :when
          pattern
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
