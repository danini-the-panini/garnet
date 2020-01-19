module GarnetRuby
  class GarnetThrow < StandardError
    attr_reader :throw_type, :value, :cfp, :exc, :tag

    def initialize(value, cfp, exc = nil, tag = nil)
      super(throw_type.to_s)
      @value = value
      @cfp = cfp
      @exc = exc
      @tag = tag
    end

    def self.of_type(type)
      case type
      when :throw then Throw
      when :raise then Raise
      when :break then Break
      when :retry then Retry
      when :continue then Continue
      when :next then Next
      when :return then Return
      when :redo then Redo
      else
        raise "Unknown throw type #{type}"
      end
    end

    def handle(vm, cfp)
      false
    end

    class Throw < GarnetThrow
    end

    class Raise < GarnetThrow
      def handle(vm, cfp)
        cr = cfp.iseq.catch_table.find do |x|
          (x.type == :rescue || x.type == :ensure) && (x.st..x.ed).include?(cfp.pc)
        end
        if cr
          cfp.pc = cr.cont
          vm.execute_rescue_iseq(cr.iseq, self)
          return true
        end
      end
    end

    class Break < GarnetThrow
      def handle(vm, cfp)
        cr = cfp.iseq.catch_table.find do |x|
          next false unless (x.st..x.ed).include?(cfp.pc)
          (x.type == :ensure && x.iseq != self.cfp.iseq) || (x.type == :break && x.iseq == self.cfp.iseq)
        end
        if cr
          cfp.pc = cr.cont
          case cr.type
          when :break
            cfp.push_stack(self.value)
          when :ensure
            vm.execute_rescue_iseq(cr.iseq, self, cfp)
          end
          return true
        end
      end
    end

    class Retry < GarnetThrow
      def handle(vm, cfp)
        cr = cfp.iseq.catch_table.find do |x|
          x.type == :retry && x.iseq == self.cfp.iseq && (x.st..x.ed).include?(cfp.pc)
        end
        if cr
          cfp.pc = cr.cont
          return true
        end
      end
    end

    class Continue < GarnetThrow
      def handle(vm, cfp)
        vm.pop_control_frame
        raise self.cfp.throw_data
      end
    end

    class Next < GarnetThrow
      def handle(vm, cfp)
        case cfp.iseq.type
        when :main, :top, :class
          Core.rb_raise(Core.eLocalJumpError, 'Invalid next')
        when :block
          cr = cfp.iseq.catch_table.find do |x|
            x.type == :ensure && (x.st..x.ed).include?(cfp.pc)
          end
          if cr
            cfp.pc = cr.cont
            vm.execute_rescue_iseq(cr.iseq, self)
            return true
          end

          vm.push_stack(self.value)
          vm.pop_control_frame
          return true
        end
      end
    end

    class Return < GarnetThrow
      def handle(vm, cfp)
        if cfp.iseq.type == :class
          Core.rb_raise(Core.eLocalJumpError, 'Invalid return in class/module body')
        end

        cr = cfp.iseq.catch_table.find do |x|
          x.type == :ensure && (x.st..x.ed).include?(cfp.pc)
        end
        if cr
          cfp.pc = cr.cont
          vm.execute_rescue_iseq(cr.iseq, self)
          return
        end

        case cfp.iseq.type
        when :main, :top
          vm.pop_control_frame
          return true
        when :method
          if cfp == self.cfp || cfp.environment == self.cfp.environment.method_entry
            vm.push_stack(self.value)
            vm.pop_control_frame
            return true
          end
        end
      end
    end

    class Redo < GarnetThrow
      def handle(vm, cfp)
        if cfp.iseq.start_label
          cfp.pc = cfp.iseq.start_label.line
          return true
        end
      end
    end
  end
end