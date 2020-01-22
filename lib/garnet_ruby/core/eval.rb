  module GarnetRuby
  module Core
    class << self
      def errinfo_getter
        VM.instance.get_errinfo
      end

      def f_current_dirname(_)
        base = current_realfilepath
        return Q_NIL if base == Q_NIL

        base = file_dirname(base)
        base
      end

      def rb_mod_include(mod, *args)
        # TODO: check type if args (they must be Module)
        # TODO: check that module has not already been included
        # TODO: call hooks
        args.reverse_each do |arg|
          mod.include_module(arg)
        end
        mod
      end

      def top_include(self_value, *args)
        rb_mod_include(cObject, *args)
      end

      def obj_extend(obj, *args)
        rb_mod_include(singleton_class_of(obj), *args)
      end

      def rb_f_at_exit(_)
        unless rb_block_given?
          rb_raise(eArgError, 'called without block')
        end

        prc = rb_block_proc
        VM.instance.add_end_proc(prc)
        prc
      end
    end

    def self.init_eval
      rb_define_virtual_variable(:'$!', method(:errinfo_getter), nil)

      rb_define_global_function(:__dir__, &method(:f_current_dirname))

      rb_define_method(cModule, :include, &method(:rb_mod_include))

      rb_define_private_method(singleton_class_of(rb_vm_top_self),
                               :include, &method(:top_include))

      rb_define_method(mKernel, :extend, &method(:obj_extend))

      rb_define_global_function(:trace_var) { |*| Q_NIL } # TODO
      rb_define_global_function(:untrace_var) { |*| Q_NIL } # TODO

      rb_define_global_function(:at_exit, &method(:rb_f_at_exit))
    end
  end
end
