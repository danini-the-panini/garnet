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

      def rb_class_new_instance(klass, *args)
        obj = klass.alloc

        if rb_block_given?
          rb_funcall_with_block(obj, :initialize, rb_block, *args)
        else
          rb_funcall(obj, :initialize, *args)
        end
        obj
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

      def obj_class(obj)
        obj.klass.real
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

      def rb_any_to_s(obj)
        RString.from(obj.any_to_s)
      end

      def rb_obj_inspect(obj)
        # TODO: put ivars in
        RString.from(obj.any_to_s)
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

      def mod_name(mod)
        RString.from(mod.name)
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
    end

    def self.init_object
      rb_define_private_method(cBasicObject, :initialize) { Q_NIL }
      rb_define_alloc_func(cBasicObject, &method(:rb_class_allocate_instance))
      rb_define_method(cBasicObject, :==, &method(:obj_equal))
      rb_define_method(cBasicObject, :equal?, &method(:obj_equal))
      rb_define_method(cBasicObject, :'!', &method(:obj_not))
      rb_define_method(cBasicObject, :'!=', &method(:obj_not_equal))

      @mKernel = rb_define_module(:Kernel)
      cObject.include_module(mKernel)

      rb_define_method(mKernel, :nil?) { |_| Q_FALSE }
      rb_define_method(mKernel, :===, &method(:rb_equal))
      rb_define_method(mKernel, :=~) { Q_NIL }
      rb_define_method(mKernel, :'!~', &method(:obj_not_match))
      rb_define_method(mKernel, :eql?, &method(:obj_equal))
      rb_define_method(mKernel, :hash, &method(:obj_hash))
      rb_define_method(mKernel, :method, &method(:obj_method))

      rb_define_method(mKernel, :class, &method(:obj_class))
      rb_define_method(mKernel, :clone, &method(:obj_clone))
      rb_define_method(mKernel, :dup, &method(:obj_dup))
      rb_define_method(mKernel, :initialize_copy, &method(:obj_init_copy))
      rb_define_method(mKernel, :initialize_dup, &method(:obj_init_dup_clone))
      rb_define_method(mKernel, :initialize_clone, &method(:obj_init_dup_clone))

      rb_define_method(mKernel, :freeze, &method(:obj_freeze))

      rb_define_method(mKernel, :to_s, &method(:rb_any_to_s))
      rb_define_method(mKernel, :inspect, &method(:rb_obj_inspect))
      rb_define_method(mKernel, :instance_variables, &method(:rb_obj_instance_variables))
      rb_define_method(mKernel, :instance_variable_get, &method(:rb_obj_ivar_get))
      rb_define_method(mKernel, :instance_variable_set, &method(:rb_obj_ivar_set))
      rb_define_method(mKernel, :instance_variable_defined?, &method(:rb_obj_ivar_defined))
      rb_define_method(mKernel, :remove_instance_variable?, &method(:rb_obj_remove_instance_variable))

      rb_define_method(mKernel, :instance_of?, &method(:obj_is_instance_of))
      rb_define_method(mKernel, :kind_of?, &method(:obj_is_kind_of))
      rb_define_method(mKernel, :is_a?, &method(:obj_is_kind_of))

      rb_define_global_function(:sprintf, &method(:f_sprintf))

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
      rb_define_method(cNilClass, :&, &method(:false_and))
      rb_define_method(cNilClass, :|, &method(:false_or))
      rb_define_method(cNilClass, :'^', &method(:false_xor))
      rb_define_global_const(:NIL, Q_NIL)

      rb_define_method(cModule, :===) do |mod, arg|
        obj_is_kind_of(arg, mod)
      end
      rb_define_method(cModule, :<=>, &method(:mod_cmp))
      rb_define_method(cModule, :initialize_copy, &method(:mod_init_copy))
      rb_define_method(cModule, :name, &method(:mod_name))
      rb_define_method(cModule, :ancestors, &method(:mod_ancestors))

      rb_define_method(cModule, :attr_reader, &method(:mod_attr_reader))
      rb_define_method(cModule, :attr_writer, &method(:mod_attr_writer))
      rb_define_method(cModule, :attr_accessor, &method(:mod_attr_accessor))

      rb_define_alloc_func(cModule, &method(:rb_module_s_alloc))

      rb_define_method(cModule, :const_set, &method(:mod_const_set))
      rb_define_method(cModule, :const_defined?, &method(:mod_const_defined))

      rb_define_method(cClass, :new, &method(:rb_class_new_instance))
      rb_define_alloc_func(cClass, &method(:rb_class_s_alloc))

      @cTrueClass = rb_define_class(:TrueClass)
      ::GarnetRuby.const_set(:Q_TRUE, RPrimitive.new(@cTrueClass, [], true))
      rb_define_method(cTrueClass, :to_s) { |_| RString.from('true') }
      rb_alias_method(cTrueClass, :inspect, :to_s)
      rb_define_method(cTrueClass, :&, &method(:true_and))
      rb_define_method(cTrueClass, :|, &method(:true_or))
      rb_define_method(cTrueClass, :'^', &method(:true_xor))
      rb_define_global_const(:TRUE, Q_TRUE)

      @cFalseClass = rb_define_class(:FalseClass)
      ::GarnetRuby.const_set(:Q_FALSE, RPrimitive.new(@cFalseClass, [], false))
      rb_define_method(cFalseClass, :to_s) { |_| RString.from('false') }
      rb_alias_method(cFalseClass, :inspect, :to_s)
      rb_define_method(cFalseClass, :&, &method(:false_and))
      rb_define_method(cFalseClass, :|, &method(:false_or))
      rb_define_method(cFalseClass, :'^', &method(:false_xor))
      rb_define_global_const(:FALSE, Q_FALSE)

      rb_define_global_function(:caller, &method(:rb_caller))
    end
  end
end
