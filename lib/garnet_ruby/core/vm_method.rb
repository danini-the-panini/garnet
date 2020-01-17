module GarnetRuby
  module Core
    class << self
      def obj_respond_to(obj, symbol, include_all = Q_FALSE)
        # TODO: respond_to_missing
        mid = check_id(symbol)
        me = find_method(obj.klass, mid)
        return Q_FALSE if me.nil? || me.undefined?
        Q_TRUE
      end

      def scope_visibility_set(visi)
        VM.instance.set_visibility(visi)
      end

      def export_method(klass, name, visi)
        me, defined_klass = search_method(klass, name)
        if !me && klass.flags.include?(:MODULE)
          me, defined_klass = search_method(cObject, name)
        end

        if me.nil? || me.definition.kind_of?(UndefinedMethodDef)
          rb_raise(eNameError, "undefined method #{name} for #{klass}")
        end

        if me.visibility != visi
          if klass == defined_klass || klass.origin == defined_klass
            me.visibility = visi
          else
            rb_add_method(klass, name, visi, ZSuperMethodDef.new(name))
          end
        end
      end

      def set_method_visibility(mdl, visi, *args)
        # check frozen
        # check arity?

        args.each do |arg|
          # check_id
          id = arg.to_symbol.symbol_value
          if !id
            rb_raise(eNameError, "undefined method #{id} for #{mdl}")
          end
        end
      end

      def set_visibility(mdl, visi, *args)
        if args.empty?
          # TODO: scope_visibility_check
          scope_visibility_set(visi)
        else
          set_method_visibility(mdl, visi, *args)
        end
        mdl
      end

      def mod_alias_method(mod, newname, oldname)
        oldid = check_id(oldname)
        unless oldid
          rb_raise(eNameError, "undefined method #{oldname} for #{mod}")
        end
        rb_alias(mod, newname.to_id, oldid)
        mod
      end

      def rb_alias(klass, alias_name, original_name)
        target_klass = klass
        visi = :undef

        if klass == Q_NIL
          rb_raise(eTypeError, 'no class to make alias')
        end

        1.times do
          orig_me = find_method(klass, original_name)
          if orig_me.nil? || orig_me.undefined?
            rb_raise(eNameError, "undefined method #{original_name} for #{klass}")
          end

          if orig_me.definition.is_a?(ZSuperMethodDef)
            klass = klass.super_class
            original_name = me.definition.original_id
            visi = orig_me.visibility
            redo
          end

          visi = orig_me.visibility if visi == :undef

          definition = AliasMethodDef.new(orig_me)
          me = method_entry_create(alias_name, target_klass, visi, definition)
          # method_added(target_klass, alias_name)
          target_klass.method_table[alias_name] = me
        end
      end

      def mod_public(mdl, *args)
        set_visibility(mdl, :public, *args)
      end

      def mod_protected(mdl, *args)
        set_visibility(mdl, :protected, *args)
      end

      def mod_private(mdl, *args)
        set_visibility(mdl, :private, *args)
      end
    end

    def self.init_vm_method
      rb_define_method(mKernel, :respond_to?, &method(:obj_respond_to))

      rb_define_method(cModule, :alias_method, &method(:mod_alias_method))
      rb_define_private_method(cModule, :public, &method(:mod_public))
      rb_define_private_method(cModule, :protected, &method(:mod_protected))
      rb_define_private_method(cModule, :private, &method(:mod_private))
    end
  end
end
