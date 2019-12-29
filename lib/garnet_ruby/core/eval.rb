module GarnetRuby
  module Core
    class << self
      def rb_catch(_, tag = RObject.new(Core.cObject, []))
        vm = VM.instance
        vm.current_control_frame.tag = tag
        ret = vm.rb_yield(tag)
        ret = vm.pop_stack if ret.nil?
        ret
      end

      def rb_throw(_, tag, value = Q_NIL)
        vm = VM.instance
        vm.find_tag(tag)
        vm.push_stack(value)

        Q_UNDEF
      end

      def rb_f_block_given(_)
        return Q_FALSE if VM.instance.previous_control_frame.block.nil?
        Q_TRUE
      end
    end

    def self.init_eval
      rb_define_global_function(:iterator?, &method(:rb_f_block_given))
      rb_define_global_function(:block_given?, &method(:rb_f_block_given))

      rb_define_global_function(:catch, &method(:rb_catch))
      rb_define_global_function(:throw, &method(:rb_throw))
    end
  end
end