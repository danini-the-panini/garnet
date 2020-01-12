module GarnetRuby
  module Core
    class << self
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
            rb_add_method(klass, name, visi, ZSuperMethodDef.new)
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

      def mod_protected(mdl, *args)
        set_visibility(mdl, :PROTECTED, *args)
      end
    end

    def self.init_vm_method
      rb_define_private_method(cModule, :protected, &method(:mod_protected))
    end
  end
end