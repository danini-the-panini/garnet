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
    end

    def self.init_eval
      rb_define_global_function(:catch, &method(:rb_catch))
      rb_define_global_function(:throw, &method(:rb_throw))
    end
  end
end