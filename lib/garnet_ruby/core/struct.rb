module GarnetRuby
  class RStruct < RObject
    attr_reader :values

    def initialize(klass, flags)
      super
      @values = []
    end

    def len
      @values.length
    end
  end

  module Core
    class << self
      def anonymous_struct(klass)
        nstr = RClass.new_class(klass)
        nstr.make_metaclass
        # TODO: call inherited
        nstr
      end

      def new_struct(name, super_class)
        name = name.str_to_str
        # TODO: check const name?
        id = name.to_symbol.symbol_value
        # TODO: warn redefinition
        define_class_id_under(super_class, id, super_class)
      end

      def struct_alloc(klass)
        RStruct.new(klass, [:STRUCT])
      end

      def define_aref_method(nstr, name, off)
        rb_define_method(nstr, name) do |st|
          st.values[off]
        end
      end

      def define_aset_method(nstr, name, off)
        rb_define_method(nstr, name) do |st, val|
          st.values[off] = val
          val
        end
      end

      def setup_struct(nstr, members, keyword_init)
        new_func = method(:rb_class_new_instance)

        # TODO: keyword_init

        nstr.ivar_set(:__members__, members)

        rb_define_alloc_func(nstr, &method(:struct_alloc))
        rb_define_singleton_method(nstr, :new, &new_func)
        rb_define_singleton_method(nstr, :[], &new_func)
        # TODO: members
        # TODO: inspect

        members.array_value.each_with_index do |sym, i|
          id = sym.symbol_value
          define_aref_method(nstr, id, i)
          define_aset_method(nstr, :"#{id}=", i)
        end

        nstr
      end

      def struct_s_def(klass, *args)
        name = args[0]
        if name.type?(Symbol)
          name = Q_NIL
        else
          args.shift
        end

        # TODO: keyword_init kwarg

        tbl = {}
        args.each do |arg|
          mem = arg.to_symbol
          # TODO: attrset?
          if tbl.key?(mem.symbol_value)
            rb_raise(eArgError, "duplicate member: #{mem}")
          end
          tbl[mem.symbol_value] = true
        end
        rest = RArray.from(tbl.keys)
        st = name == Q_NIL ? anonymous_struct(klass) : new_struct(name, klass)
        setup_struct(st, rest, false)
        st.ivar_set(:__keyword_init__, Q_FALSE)
        if rb_block_given?
          mod_module_eval(st)
        end

        st
      end

      def num_members(st)
        members = st.ivar_get(:__members__)
        members.len
      end

      def struct_init(st, *args)
        klass = obj_class(st)
        n = num_members(klass)

        # TODO: keyword init

        if n < args.length
          rb_raise(eArgError, "struct size differs")
        end
        args.each_with_index do |arg, i|
          st.values[i] = arg
        end
        if n > args.length
          [args.length...n].each do |i|
            st.values[i] = Q_NIL
          end
        end

        Q_NIL
      end

      def struct_each(s)
        # TODO: return enumerator
        s.values.each do |v|
          rb_yield(v)
        end
        s
      end

      def struct_member_pos(s, name)
        members = obj_class(s).ivar_get(:__members__)
        ret = members.find_index do |mem|
          mem.symbol_value == name
        end
        ret || -1
      end

      def struct_pos(s, idx)
        if idx.type?(Symbol)
          retrun struct_member_pos(s, idx.symbol_value), idx
        elsif idx.type?(String)
          # check_symbol
          tmp = idx.check_string_type
          return -1, idx if tmp == Q_NIL
          sym = tmp.string_value.to_sym
          return struct_member_pos(s, sym), idx
        else
          len = s.len
          i = num2long(idx)
          if i < 0
            return -1, RPrimitive.from(i) if i + len < 0
            i += len
          elsif len <= i
            return -1, RPrimitive.from(i)
          end
          return i, idx
        end
      end

      def invalid_struct_pos(s, idx)
        if fixnum?(idx)
          i = idx.value
          len = s.len
          if i < 0
            rb_raise(eIndexError, "offset #{i} too small for struct(size:#{len})")
          else
            rb_raise(eIndexError, "offset #{i} too large for struct(size:#{len})")
          end
        else
          rb_raise(eNameError, "no member #{idx} in struct")
        end
      end

      def struct_aref(s, idx)
        i, idx = struct_pos(s, idx)
        invalid_struct_pos(s, idx) if i < 0
        s.values[i]
      end

      def struct_aset(s, idx, val)
        i, idx = struct_pos(s, idx)
        invalid_struct_pos(s, idx) if i < 0
        s.values[i] = val
        val
      end
    end

    def self.init_struct
      @cStruct = rb_define_class(:Struct, cObject)
      cStruct.include_module(mEnumerable)

      rb_undef_alloc_func(cStruct)
      rb_define_singleton_method(cStruct, :new, &method(:struct_s_def))

      rb_define_method(cStruct, :initialize, &method(:struct_init))
      # rb_define_method(cStruct, :initialize_copy, &method(:struct_init_copy))

      rb_define_method(cStruct, :each, &method(:struct_each))
      rb_define_method(cStruct, :[], &method(:struct_aref))
      rb_define_method(cStruct, :[]=, &method(:struct_aset))
    end
  end
end
