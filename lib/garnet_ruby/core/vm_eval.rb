module GarnetRuby
  module Core
    class << self
      def rb_f_eval(_, *args)
        vm = VM.instance

        src = args[0].obj_as_string.string_value

        if args.length > 1 && args[1] != Q_NIL
          cfp = args[1].cfp
        else
          cfp = vm.previous_control_frame
        end

        if args.length > 2
          fname = args[2].obj_as_string.string_value
        else
          fname = "(eval)"
        end

        if args.length > 3
          lineno = num2long(args[3])
        else
          lineno = 1
        end

        iseq = compile_for_eval(src, fname, lineno, cfp.iseq)

        vm.execute_eval_iseq(iseq, cfp)
      end

      def compile_for_eval(src, fname, lineno, parent)
        parser = Parser.new(src, fname)
        node = parser.parse
        if __grb_debug__?
          puts '-eval-'
          pp node
          puts '------'
        end

        iseq = Iseq.new('eval', :eval, parent)
        Compiler.new(iseq).compile_node(node)

        iseq
      end

      def rb_f_block_given(_)
        vm = VM.instance
        if vm.caller_environment(vm.previous_control_frame).block.nil?
          return Q_FALSE
        end
        Q_TRUE
      end

      def rb_catch(_, tag = RObject.new(Core.cObject, []))
        vm = VM.instance
        vm.current_control_frame.tag = tag
        begin
          vm.rb_yield(tag)
        rescue GarnetThrow::Throw => e
          raise unless e.tag == tag
          e.value
        end
      end

      def rb_throw(_, tag, value = Q_NIL)
        raise GarnetThrow::Throw.new(value, VM.instance.current_control_frame, nil, tag)
        Q_UNDEF
      end

      def rb_loop(_)
        loop do
          rb_yield
        end
      rescue GarnetThrow::Break => e
        e.value
      end

      def rb_instance_eval(slf, *args)
        klass = singleton_class_for_eval(slf)
        specific_eval(klass, slf, *args)
      end

      def specific_eval(klass, slf, *args)
        return yield_under(klass, slf, *args) if rb_block_given?

        src = args[0].obj_as_string.string_value
        
        if args.length > 1
          fname = args[1].obj_as_string.string_value
        else
          fname = "(eval)"
        end

        if args.length > 2
          lineno = num2long(args[2])
        else
          lineno = 1
        end
        
        vm = VM.instance

        cfp = vm.previous_control_frame

        iseq = compile_for_eval(src, fname, lineno, cfp.iseq)

        vm.execute_eval_iseq(iseq, cfp, klass, slf)
      end

      def rb_f_send(obj, name, *args)
        id = check_id(name)

        if rb_block_given?
          rb_funcall_with_block(obj, id, rb_block, *args)
        else
          rb_funcall(obj, id, *args)
        end
      end
    end

    def self.init_vm_eval
      rb_define_global_function(:eval, &method(:rb_f_eval))
      rb_define_global_function(:iterator?, &method(:rb_f_block_given))
      rb_define_global_function(:block_given?, &method(:rb_f_block_given))

      rb_define_global_function(:catch, &method(:rb_catch))
      rb_define_global_function(:throw, &method(:rb_throw))

      rb_define_global_function(:loop, &method(:rb_loop))
      
      rb_define_method(cBasicObject, :instance_eval, &method(:rb_instance_eval))

      rb_define_method(cBasicObject, :__send__, &method(:rb_f_send))
      rb_define_method(mKernel, :send, &method(:rb_f_send))
    end
  end
end
