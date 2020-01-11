module GarnetRuby
  module Core
    class << self
      def rb_f_eval(_, *args)
        src = args.first.obj_as_string.string_value

        parser = Parser.new(src, "eval")
        node = parser.parse

        iseq = Iseq.new('eval', :eval)
        Compiler.new(iseq).compile_node(node)

        VM.instance.execute_eval_iseq(iseq)
      end

      def rb_catch(_, tag = RObject.new(Core.cObject, []))
        vm = VM.instance
        vm.current_control_frame.tag = tag
        begin
          vm.rb_yield(tag)
        rescue VM::GarnetThrow => e
          raise unless e.throw_type == :throw && e.tag == tag
          e.value
        end
      end

      def rb_throw(_, tag, value = Q_NIL)
        raise VM::GarnetThrow.new(:throw, value, VM.instance.current_control_frame, nil, tag)
        Q_UNDEF
      end

      def rb_f_block_given(_)
        vm = VM.instance
        if vm.caller_environment(vm.previous_control_frame).block.nil?
          return Q_FALSE
        end
        Q_TRUE
      end
    end

    def self.init_vm_eval
      rb_define_global_function(:eval, &method(:rb_f_eval))

      rb_define_global_function(:iterator?, &method(:rb_f_block_given))
      rb_define_global_function(:block_given?, &method(:rb_f_block_given))

      rb_define_global_function(:catch, &method(:rb_catch))
      rb_define_global_function(:throw, &method(:rb_throw))
    end
  end
end