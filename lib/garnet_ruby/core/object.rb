module GarnetRuby
  class RObject < RBasic
    attr_reader :ivars

    def initialize(klass, flags)
      super
      @ivars = {}
    end

    def ivar_set(k, v)
      @ivars[k] = v
    end

    def ivar_get(k)
      @ivars[k]
    end

    def ivar_defined?(k)
      @ivars.key?(k)
    end

    def ivar_remove(k)
      @ivars.delete(k)
    end
  end

  module Core
    class << self
      def rb_class_allocate_instance(klass)
        RObject.new(klass, [])
      end

      def rb_module_s_alloc(_)
        RClass.new(cModule, [:MODULE])
      end

      def rb_class_s_alloc(_)
        RClass.new(cClass, [:CLASS])
      end

      def rb_class_alloc_m(klass)
        # TODO: check if klass respond_to? allocate
        obj = klass.alloc_func.call(klass)
        # TODO: check class of obj
        obj
      end

      def rb_class_new_instance(klass, *args)
        obj = klass.alloc

        if rb_block_given?
          rb_funcall_with_block(obj, :initialize, rb_block, *args)
        else
          rb_funcall(obj, :initialize, *args)
        end
        obj
      end

      def rb_class_initialize(klass, *args)
        if !klass.super_class.nil? || klass == cBasicObject
          rb_raise(eTypeError, 'already initialized class')
        end
        if args.length == 0
          sup = cObject
        else
          sup = args.first
          if sup != cBasicObject && sup.super_class.nil?
            rb_raise(eTypeError, "can't inherit uninitialized class")
          end
        end

        klass.super_class = sup
        rb_make_metaclass(klass)
        # rb_class_inherited
        mod_initialize(klass)

        klass
      end

      def class_superclass(klass)
        sup = klass.super_class

        unless sup
          return Q_NIL if klass == cBasicObject

          rb_raise(eTypeError, 'uninitialized class')
        end
        sup = sup.super_class while sup.flags.include?(:ICLASS)
        return Q_NIL unless sup

        sup
      end

      def mod_initialize(mod)
        mod_module_exec(mod, mod) if rb_block_given?
        Q_NIL
      end

      def mod_initialize_clone(clone, orig)
        ret = obj_init_dup_clone(clone, orig)
        # rb_class_name(clone) if orig.flags.include?(:frozen) # TODO
        ret
      end

      def singleton_class_clone(obj)
        singleton_class_clone_and_attach(obj, Q_UNDEF)
      end

      def singleton_class_clone_and_attach(obj, attach)
        klass = obj.klass

        if !klass.flags.include?(:SINGLETON)
          return klass
        end

        clone = RClass.new(nil, klass.flags)
        if obj.flags.include?(:CLASS)
          clone.klass = clone
        else
          clone.klass = singleton_class_clone(klass)
        end

        clone.super_class = klass.super_class
        clone.allocator = klass.allocator
        # TODO: copy iv table?
        if klass.const_table
          klass.const_table.each do |k,v|
            clone.const_table[k] = v
          end
        end
        # if attach != Q_UNDEF
        #   rb_singleton_class_attached(clone, attach)
        # end

        klass.method_table.each do |k,v|
          clone.method_table[k] = clone_method(klass, clone, k, v)
        end
        # rb_singleton_class_attached(clone.klass, clone)
        clone.flags |= [:SINGLETON]

        clone
      end

      def rb_obj_clone(obj)
        return obj if obj.is_a?(RPrimitive) || obj.is_a?(RSymbol)

        clone = obj_class(obj).alloc

        singleton = singleton_class_clone_and_attach(obj, clone)
        clone.klass = singleton
        # TODO
        # if singleton.flags.include?(:SINGLETON)
        #   rb_singleton_class_attached(singleton, clone)
        # end

        init_copy(clone, obj)
        rb_funcall(clone, :initialize_clone, obj)

        clone
      end

      def obj_dup(obj)
        dup = obj_class(obj).alloc
        init_copy(dup, obj)
        rb_funcall(dup, :initialize_dup, obj)

        dup
      end

      def obj_yield_self(obj)
        rb_yield(obj)
      end

      def init_copy(clone, obj)
        rb_copy_generic_ivar(clone, obj)
      end

      def rb_copy_generic_ivar(clone, obj)
        obj.ivars.each do |k, v|
          clone.ivar_set(k, obj)
        end
      end

      def rb_iv_tbl_copy(dst, src)
        dst.ivars.clear
        src.ivars.each do |k, v|
          dst.ivars[k] = v
        end
      end

      def obj_is_instance_of(obj, c)
        # TODO: check c is class/module
        return Q_TRUE if obj_class(obj) == c

        Q_FALSE
      end

      def obj_is_kind_of(obj, c)
        cl = obj.klass

        # TODO: make sure c is a module/class
        c.search_ancestor(cl) ? Q_TRUE : Q_FALSE
      end

      def obj_tap(obj)
        rb_yield(obj)
        obj
      end

      def f_sprintf(_, *args)
        rb_sprintf(*args)
      end

      def rb_f_integer(obj, *args)
        # TODO: a lot of other things
        args.first.to_integer(:to_i)
      end

      def rb_f_float(obj, arg)
        # TODO: a lot of other things
        arg.rb_convert_type_with_id(Float, 'Float', :to_f)
      end

      def rb_String(val)
        tmp = val.check_string_type
        if tmp == Q_NIL
          tmp = val.rb_convert_type_with_id(String, 'String', :to_s)
        end
        tmp
      end

      def rb_f_string(obj, val)
        rb_String(val)
      end

      def rb_Array(val)
        tmp = val.check_array_type

        if tmp == Q_NIL
          tmp = val.check_to_array
          return RArray.from([val]) if tmp == Q_NIL
        end
        tmp
      end

      def rb_f_array(obj, arg)
        rb_Array(arg)
      end

      def rb_Hash(val)
        return RHash.from({}) if val == Q_NIL
        tmp = val.check_hash_type(val)
        if tmp == Q_NIL
          return RHash.new({}) if val.type?(Array) && val.len.zero?
          rb_raise(eTypeError, "can't convert #{val.klass.name} into Hash")
        end
        tmp
      end

      def rb_f_hash(obj, arg)
        rb_Hash(arg)
      end

      def true_and(obj, obj2)
        rtest(obj2) ? Q_TRUE : Q_FALSE
      end

      def true_or(obj, obj2)
        Q_TRUE
      end

      def true_xor(obj, obj2)
        rtest(obj2) ? Q_FALSE : Q_TRUE
      end

      def false_and(obj, obj2)
        Q_FALSE
      end

      def false_or(obj, obj2)
        rtest(obj2) ? Q_TRUE : Q_FALSE
      end

      def false_xor(obj, obj2)
        rtest(obj2) ? Q_TRUE : Q_FALSE
      end

      def obj_not_match(obj1, obj2)
        result = rb_funcall(obj1, :=~, obj2)
        rtest(result) ? Q_FALSE : Q_TRUE
      end

      def obj_equal(obj1, obj2)
        obj1 == obj2 ? Q_TRUE : Q_FALSE
      end

      def obj_not(obj)
        rtest(obj) ? Q_FALSE : Q_TRUE
      end

      def obj_not_equal(obj1, obj2)
        result = rb_funcall(obj1, :==, obj2)
        rtest(result) ? Q_FALSE : Q_TRUE
      end

      def obj_hash(obj)
        v = obj.__id__
        RPrimitive.from(v ^ (v >> 32))
      end

      def check_id(name)
        if name.type?(Symbol)
          name.symbol_value
        elsif name.type?(String)
          name.string_value.to_sym
        else
          tmp = name.check_string_type
          if tmp == Q_NIL
            rb_raise(eTypeError, "#{name} is not a symbol or a string")
          end
          tmp.string_value.to_sym
        end
      end

      def obj_method(obj, vid)
        id = check_id(vid)
        klass = obj.klass
        mclass = cMethod

        me = find_method(klass, id)

        if me.nil? || me.undefined?
          rb_raise(eNameError, "undefined method `#{id}' for class `#{klass}'")
        end

        RMethod.new(mclass, [], me, obj)
      end

      def obj_cmp(obj1, obj2)
        return RPrimitive.from(0) if obj1 == obj2 || rtest(rb_equal(obj1, obj2))
        Q_NIL
      end

      def obj_class(obj)
        obj.klass.real
      end

      def obj_singleton_class(obj)
        klass = singleton_class_of(obj)

        klass.ensure_eigenclass if obj.flags.include?(:CLASS)

        klass
      end

      def obj_clone(obj)
        # TODO: freeze kwarg
        rb_obj_clone(obj)
      end

      def obj_init_copy(obj, orig)
        return obj if obj == orig

        # TODO: check frozen
        if obj.type != orig.type || obj_class(obj) != obj_class(orig)
          rb_raise(eTypeError, 'initialize_copy should take same class object')
        end
        obj
      end

      def obj_init_dup_clone(obj, orig)
        rb_funcall(obj, :initialize_copy, orig)
        obj
      end

      def obj_freeze(obj)
        obj.flags |= [:freeze]
        obj
      end

      def mod_freeze(mod)
        # TODO: something else?
        obj_freeze(mod)
      end

      def any_to_s(obj)
        RString.from(obj.any_to_s)
      end

      def obj_inspect(obj)
        # TODO: put ivars in
        RString.from(obj.any_to_s)
      end

      def obj_singleton_methods(obj)
        ary = RArray.from([])
        obj.klass.method_table.map do |mid, me|
          next unless %i[public protected].include?(me.visibility)

          ary_push(ary, RSymbol.from(mid))
        end
        ary
      end

      def obj_methods(obj, *args)
        if !args.empty? && !rtest(args[0])
          return obj_singleton_methods(obj)
        end
        obj.klass.instance_method_list(true, %i[public protected])
      end

      def obj_protected_methods(obj, *args)
        all = args.empty? || rtest(args[0])
        obj.klass.instance_method_list(all, %i[protected])
      end

      def obj_private_methods(obj, *args)
        all = args.empty? || rtest(args[0])
        obj.klass.instance_method_list(all, %i[private])
      end

      def obj_public_methods(obj, *args)
        all = args.empty? || rtest(args[0])
        obj.klass.instance_method_list(all, %i[public])
      end

      def rb_obj_instance_variables(obj)
        ary = RArray.from([])
        obj.ivars.each do |k, _|
          ary.array_value << RSymbol.from(k)
        end
        ary
      end

      def rb_obj_ivar_get(obj, iv)
        id = check_id(iv)

        return Q_NIL unless id

        obj.ivar_get(id) || Q_NIL
      end

      def rb_obj_ivar_set(obj, iv, val)
        id = check_id(iv)
        # if (!id) id = rb_intern_str(iv)
        obj.ivar_set(id, val)
        val
      end

      def rb_obj_ivar_defined(obj)
        id = check_id(obj)

        return Q_FALSE unless id

        obj.ivar_defined?(id) ? Q_TRUE : Q_FALSE
      end

      def rb_obj_remove_instance_variable(obj)
        id = check_id(obj)

        return Q_NIL unless id

        obj.ivar_remove(id) || Q_NIL
      end

      def rb_caller(_, *args)
        VM.instance.backtrace_to_ary(args, 1, true)
      end

      def rb_obj_id(obj)
        RPrimitive.from(obj.__id__)
      end

      def rb_equal(obj1, obj2)
        return Q_TRUE if obj1 == obj2

        result = rb_funcall(obj1, :==, obj2)
        rtest(result) ? Q_TRUE : Q_FALSE
      end

      def rb_eql(obj1, obj2)
        return Q_TRUE if obj1 == obj2

        result = rb_funcall(obj1, :eql?, obj2)
        rtest(result) ? Q_TRUE : Q_FALSE
      end

      def mod_eqq(mod, arg)
        obj_is_kind_of(arg, mod)
      end

      def mod_cmp(mod, arg)
        return RPrimitive.from(0) if mod == arg
        return Q_NIL unless arg.is_a?(RClass)

        cmp = mod.inherited?(arg)
        return Q_NIL if cmp == Q_NIL
        if rtest(cmp)
          RPrimitive.from(-1)
        else
          RPrimitive.from(1)
        end
      end

      def mod_lt(mod, arg)
        return Q_FALSE if mod == arg
        mod.inherited?(arg)
      end

      def mod_le(mod, arg)
        mod.inherited?(arg)
      end

      def mod_gt(mod, arg)
        return Q_FALSE if mod == arg
        mod_ge(mod, arg)
      end

      def mod_ge(mod, arg)
        rb_raise(eTypeError, 'compared with non class/module') unless arg.is_a?(RClass)

        arg.inherited?(mod)
      end

      def mod_init_copy(clone, orig)
        # TODO: cloned flag for const inline cache

        if clone.flags.include?(:CLASS)
          # class_init_copy_check(clone, orig) # TODO
        end
        return clonse if clone == orig
        obj_init_copy(clone, orig)
        if !clone.klass.flags.include?(:SINGLETON)
          clone.klass = singleton_class_clone(orig)
          # rb_singleton_class_attached(clone.klass, clone)
        end
        clone.super_class = orig.super_class
        clone.allocator = orig.allocator
        if clone.ivars
          clone.ivars.clear
        end
        if clone.const_table
          clone.const_table.clear
        end
        clone.method_table.clear
        if orig.ivars
          rb_iv_tbl_copy(clone, orig)
          clone.ivars.delete(:__tmp_classpath__)
          clone.ivars.delete(:__classpath__)
          clone.ivars.delete(:__classid__)
        end
        if orig.const_table
          orig.const_table.each do |k,v|
            clone.const_table[k] = v
          end
        end
        if orig.method_table
          orig.method_table.each do |k,v|
            clone.method_table[k] = clone_method(orig, clone, k, v)
          end
        end
        
        clone
      end

      def mod_to_s(mod)
        # TODO: fully qualified name?
        mod_name(mod)
      end

      def mod_name(mod)
        RString.from(mod.name.to_s)
      end

      def mod_ancestors(mod)
        ary = RArray.from([])

        p = mod
        while p
          # TODO: something to do with origin
          next if p != p.origin

          if p.flags.include?(:ICLASS)
            ary_push(ary, p.klass)
          else
            ary_push(ary, p)
          end

          p = p.super_class
        end

        ary
      end

      def mod_attr(mod, *args)
        if args.length == 2
          case args.last
          when Q_TRUE
            return mod_attr_accessor(mod, args.first)
          when Q_FALSE
            return mod_attr_writer(mod, args.first)
          end
        end
        mod_attr_reader(mod, *args)
      end

      def mod_attr_reader(mod, *args)
        args.each do |arg|
          id = check_id(arg)
          definition = IvarMethodDef.new(:"@#{id}")
          rb_add_method(mod, id, :public, definition)
        end
      end

      def mod_attr_writer(mod, *args)
        args.each do |arg|
          id = check_id(arg)
          definition = AttrsetMethodDef.new(:"@#{id}")
          rb_add_method(mod, :"#{id}=", :public, definition)
        end
      end

      def mod_attr_accessor(mod, *args)
        mod_attr_reader(mod, *args)
        mod_attr_writer(mod, *args)

        Q_NIL
      end

      def mod_instance_methods(mod, *args)
        include_super = args.empty? ? true : rtest(args.first)

        mod.instance_method_list(include_super, %i[public protected])
      end

      def mod_public_instance_methods(mod, *args)
        include_super = args.empty? ? true : rtest(args.first)

        mod.instance_method_list(include_super, %i[public])
      end

      def mod_private_instance_methods(mod, *args)
        include_super = args.empty? ? true : rtest(args.first)

        mod.instance_method_list(include_super, %i[private])
      end

      def mod_protected_instance_methods(mod, *args)
        include_super = args.empty? ? true : rtest(args.first)

        mod.instance_method_list(include_super, %i[protected])
      end

      def mod_constants(mod, *args)
        inherit = args.empty? ? true : rtest(args.first)

        tbl = mod.consts(inherit)

        RArray.from(tbl)
      end

      def mod_const_get(mod, name)
        id = check_id(name)
        mod.rb_const_get(id)
      end

      def mod_const_set(mod, name, value)
        id = check_id(name)
        mod.rb_const_set(id, value)
        value
      end

      def mod_const_defined(mod, *args)
        name = args[0]
        recur = args.length == 1 ? Q_TRUE : args[1]

        if name.type?(Symbol)
          # const_sym --> wrong_name
          id = check_id(name)

          return Q_FALSE unless id

          result = rtest(recur) ? mod.has_const?(id) : mod.has_const_direct?(id)
          return result ? Q_TRUE : Q_FALSE
        end

        # TODO: string stuff
        Q_FALSE
      end

      def mod_remove_const(mod, name)
        id = check_id(name)

        mod.rb_const_remove(id)
      end

      def mod_remove_cvar(mod, iv)
        id = check_id(iv)
        mod.cvar_remove(id)
      end

      def mod_cvar_set(mod, iv, val)
        id = check_id(iv)
        mod.cvar_set(id, val)
        val
      end

      def mod_cvar_get(mod, iv)
        id = check_id(iv)
        mod.cvar_get(id)
      end

      def mod_class_variables(mod, *args)
        inherit = args.empty? ? true : rtest(args.first)

        tbl = mod.cvars(inherit)

        RArray.from(tbl)
      end

      def mod_cvar_defined(mod, iv)
        id = check_id(iv)
        mod.cvar_defined?(id) ? Q_TRUE : Q_FALSE
      end

      def mod_public_constant(mod, *args)
        # TODO: actually do something
        mod
      end

      def mod_private_constant(mod, *args)
        # TODO: actually do something
        mod
      end

      def mod_deprecate_constant(mod, *args)
        # TODO: actually do something
        mod
      end

      def mod_singleton_class(mod)
        mod.flags.include?(:SINGLETON) ? Q_TRUE : Q_FALSE
      end
    end

    def self.init_object
      rb_define_private_method(cBasicObject, :initialize) { |_| Q_NIL }
      rb_define_alloc_func(cBasicObject, &method(:rb_class_allocate_instance))
      rb_define_method(cBasicObject, :==, &method(:obj_equal))
      rb_define_method(cBasicObject, :equal?, &method(:obj_equal))
      rb_define_method(cBasicObject, :'!', &method(:obj_not))
      rb_define_method(cBasicObject, :'!=', &method(:obj_not_equal))
      
      rb_define_private_method(cBasicObject, :singleton_method_added) { |_| Q_NIL }
      rb_define_private_method(cBasicObject, :singleton_method_removed) { |_| Q_NIL }
      rb_define_private_method(cBasicObject, :singleton_method_undefined) { |_| Q_NIL }

      @mKernel = rb_define_module(:Kernel)
      cObject.include_module(mKernel)
      rb_define_private_method(cClass, :inherited) { |_| Q_NIL }
      rb_define_private_method(cModule, :included) { |_| Q_NIL }
      rb_define_private_method(cModule, :extended) { |_| Q_NIL }
      rb_define_private_method(cModule, :prepended) { |_| Q_NIL }
      rb_define_private_method(cModule, :method_added) { |_| Q_NIL }
      rb_define_private_method(cModule, :method_removed) { |_| Q_NIL }
      rb_define_private_method(cModule, :method_undefined) { |_| Q_NIL }

      rb_define_method(mKernel, :nil?) { |_| Q_FALSE }
      rb_define_method(mKernel, :===, &method(:rb_equal))
      rb_define_method(mKernel, :=~) { |_| Q_NIL }
      rb_define_method(mKernel, :'!~', &method(:obj_not_match))
      rb_define_method(mKernel, :eql?, &method(:obj_equal))
      rb_define_method(mKernel, :hash, &method(:obj_hash))
      rb_define_method(mKernel, :method, &method(:obj_method))
      rb_define_method(mKernel, :<=>, &method(:obj_cmp))

      rb_define_method(mKernel, :class, &method(:obj_class))
      rb_define_method(mKernel, :singleton_class, &method(:obj_singleton_class))
      rb_define_method(mKernel, :clone, &method(:obj_clone))
      rb_define_method(mKernel, :dup, &method(:obj_dup))
      rb_define_method(mKernel, :itself) { |obj| obj }
      rb_define_method(mKernel, :yield_self, &method(:obj_yield_self))
      rb_define_method(mKernel, :then, &method(:obj_yield_self))
      rb_define_method(mKernel, :initialize_copy, &method(:obj_init_copy))
      rb_define_method(mKernel, :initialize_dup, &method(:obj_init_dup_clone))
      rb_define_method(mKernel, :initialize_clone, &method(:obj_init_dup_clone))

      rb_define_method(mKernel, :taint, &method(:TODO_not_implemented))
      rb_define_method(mKernel, :tainted?, &method(:TODO_not_implemented))
      rb_define_method(mKernel, :untaint, &method(:TODO_not_implemented))
      rb_define_method(mKernel, :untrust, &method(:TODO_not_implemented))
      rb_define_method(mKernel, :untrusted?, &method(:TODO_not_implemented))
      rb_define_method(mKernel, :trust, &method(:TODO_not_implemented))
      rb_define_method(mKernel, :freeze, &method(:obj_freeze))
      rb_define_method(mKernel, :frozen?, &method(:TODO_not_implemented))

      rb_define_method(mKernel, :to_s, &method(:any_to_s))
      rb_define_method(mKernel, :inspect, &method(:obj_inspect))
      rb_define_method(mKernel, :methods, &method(:obj_methods))
      rb_define_method(mKernel, :singleton_methods, &method(:obj_singleton_methods))
      rb_define_method(mKernel, :protected_methods, &method(:obj_protected_methods))
      rb_define_method(mKernel, :private_methods, &method(:obj_private_methods))
      rb_define_method(mKernel, :public_methods, &method(:obj_public_methods))
      rb_define_method(mKernel, :instance_variables, &method(:rb_obj_instance_variables))
      rb_define_method(mKernel, :instance_variable_get, &method(:rb_obj_ivar_get))
      rb_define_method(mKernel, :instance_variable_set, &method(:rb_obj_ivar_set))
      rb_define_method(mKernel, :instance_variable_defined?, &method(:rb_obj_ivar_defined))
      rb_define_method(mKernel, :remove_instance_variable?, &method(:rb_obj_remove_instance_variable))

      rb_define_method(mKernel, :instance_of?, &method(:obj_is_instance_of))
      rb_define_method(mKernel, :kind_of?, &method(:obj_is_kind_of))
      rb_define_method(mKernel, :is_a?, &method(:obj_is_kind_of))
      rb_define_method(mKernel, :tap, &method(:obj_tap))

      rb_define_global_function(:sprintf, &method(:f_sprintf))
      rb_define_global_function(:format, &method(:f_sprintf))

      rb_define_global_function(:Integer, &method(:rb_f_integer))
      rb_define_global_function(:Float, &method(:rb_f_float))

      rb_define_global_function(:String, &method(:rb_f_string))
      rb_define_global_function(:Array, &method(:rb_f_array))
      rb_define_global_function(:Hash, &method(:rb_f_hash))

      @cNilClass = rb_define_class(:NilClass)
      ::GarnetRuby.const_set(:Q_NIL, RPrimitive.new(@cNilClass, [], nil))
      rb_define_method(cNilClass, :to_i) { |_| RPrimitive.from(0) }
      rb_define_method(cNilClass, :to_f) { |_| RPrimitive.from(0.0) }
      rb_define_method(cNilClass, :to_s) { |_| RString.from('') }
      rb_define_method(cNilClass, :to_a) { |_| RArray.from([]) }
      rb_define_method(cNilClass, :to_h) { |_| RHash.from([]) }
      rb_define_method(cNilClass, :inspect) { |_| RString.from('nil') }
      rb_define_method(cNilClass, :=~) { |_| Q_NIL }
      rb_define_method(cNilClass, :&, &method(:false_and))
      rb_define_method(cNilClass, :|, &method(:false_or))
      rb_define_method(cNilClass, :'^', &method(:false_xor))
      rb_define_method(cNilClass, :===, &method(:rb_equal))

      rb_define_method(cNilClass, :nil?) { |_| Q_TRUE }
      rb_undef_alloc_func(cNilClass)
      rb_define_global_const(:NIL, Q_NIL)

      rb_define_method(cModule, :freeze, &method(:mod_freeze))
      rb_define_method(cModule, :===, &method(:mod_eqq))
      rb_define_method(cModule, :==, &method(:obj_equal))
      rb_define_method(cModule, :<=>, &method(:mod_cmp))
      rb_define_method(cModule, :<, &method(:mod_lt))
      rb_define_method(cModule, :<=, &method(:mod_le))
      rb_define_method(cModule, :>, &method(:mod_gt))
      rb_define_method(cModule, :>=, &method(:mod_ge))
      rb_define_method(cModule, :initialize_copy, &method(:mod_init_copy))
      rb_define_method(cModule, :to_s, &method(:mod_to_s))
      rb_alias_method(cModule, :inspect, :to_s)
      rb_define_method(cModule, :included_modules, &method(:TODO_not_implemented))
      rb_define_method(cModule, :include?, &method(:TODO_not_implemented))
      rb_define_method(cModule, :name, &method(:mod_name))
      rb_define_method(cModule, :ancestors, &method(:mod_ancestors))

      rb_define_method(cModule, :attr, &method(:mod_attr))
      rb_define_method(cModule, :attr_reader, &method(:mod_attr_reader))
      rb_define_method(cModule, :attr_writer, &method(:mod_attr_writer))
      rb_define_method(cModule, :attr_accessor, &method(:mod_attr_accessor))

      rb_define_alloc_func(cModule, &method(:rb_module_s_alloc))
      rb_define_method(cModule, :initialize, &method(:mod_initialize))
      rb_define_method(cModule, :initialize_clone, &method(:mod_initialize_clone))
      rb_define_method(cModule, :instance_methods, &method(:mod_instance_methods))
      rb_define_method(cModule, :public_instance_methods, &method(:TODO_not_implemented))
      rb_define_method(cModule, :protected_instance_methods, &method(:TODO_not_implemented))
      rb_define_method(cModule, :private_instance_methods, &method(:TODO_not_implemented))

      rb_define_method(cModule, :constants, &method(:mod_constants))
      rb_define_method(cModule, :const_get, &method(:mod_const_get))
      rb_define_method(cModule, :const_set, &method(:mod_const_set))
      rb_define_method(cModule, :const_defined?, &method(:mod_const_defined))
      rb_define_method(cModule, :const_source_location, &method(:TODO_not_implemented))
      rb_define_method(cModule, :remove_const, &method(:mod_remove_const))
      rb_define_method(cModule, :const_missing, &method(:TODO_not_implemented))
      rb_define_method(cModule, :class_variables, &method(:mod_class_variables))
      rb_define_method(cModule, :remove_class_variable, &method(:mod_remove_cvar))
      rb_define_method(cModule, :class_variable_get, &method(:mod_cvar_get))
      rb_define_method(cModule, :class_variable_set, &method(:mod_cvar_set))
      rb_define_method(cModule, :class_variable_defined?, &method(:mod_cvar_defined))
      rb_define_method(cModule, :public_constant, &method(:mod_public_constant))
      rb_define_method(cModule, :private_constant, &method(:mod_private_constant))
      rb_define_method(cModule, :deprecate_constant, &method(:mod_deprecate_constant))
      rb_define_method(cModule, :singleton_class?, &method(:mod_singleton_class))

      rb_define_method(cClass, :allocate, &method(:rb_class_alloc_m))
      rb_define_method(cClass, :new, &method(:rb_class_new_instance))
      rb_define_method(cClass, :initialize, &method(:rb_class_initialize))
      rb_define_method(cClass, :superclass, &method(:class_superclass))
      rb_define_alloc_func(cClass, &method(:rb_class_s_alloc))
      rb_define_method(cClass, :extend_object, &method(:TODO_not_implemented))
      rb_define_method(cClass, :append_features, &method(:TODO_not_implemented))
      rb_define_method(cClass, :prepend_features, &method(:TODO_not_implemented))
      
      @cData = rb_define_class(:Data, cObject)
      rb_undef_alloc_func(cData)

      @cTrueClass = rb_define_class(:TrueClass)
      ::GarnetRuby.const_set(:Q_TRUE, RPrimitive.new(@cTrueClass, [], true))
      rb_define_method(cTrueClass, :to_s) { |_| RString.from('true') }
      rb_alias_method(cTrueClass, :inspect, :to_s)
      rb_define_method(cTrueClass, :&, &method(:true_and))
      rb_define_method(cTrueClass, :|, &method(:true_or))
      rb_define_method(cTrueClass, :'^', &method(:true_xor))
      rb_define_method(cTrueClass, :===, &method(:rb_equal))
      rb_undef_alloc_func(cTrueClass)
      rb_define_global_const(:TRUE, Q_TRUE)

      @cFalseClass = rb_define_class(:FalseClass)
      ::GarnetRuby.const_set(:Q_FALSE, RPrimitive.new(@cFalseClass, [], false))
      rb_define_method(cFalseClass, :to_s) { |_| RString.from('false') }
      rb_alias_method(cFalseClass, :inspect, :to_s)
      rb_define_method(cFalseClass, :&, &method(:false_and))
      rb_define_method(cFalseClass, :|, &method(:false_or))
      rb_define_method(cFalseClass, :'^', &method(:false_xor))
      rb_define_method(cFalseClass, :===, &method(:rb_equal))
      rb_undef_alloc_func(cFalseClass)
      rb_define_global_const(:FALSE, Q_FALSE)

      rb_define_global_function(:caller, &method(:rb_caller))
      rb_define_method(cBasicObject, :__id__, &method(:rb_obj_id))
      rb_define_method(mKernel, :object_id, &method(:rb_obj_id))
    end
  end

end
