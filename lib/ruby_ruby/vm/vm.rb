module RubyRuby
  class VM
    class << self
      attr_reader :instance

      def new
        @instance ||= super
      end
    end

    def initialize
      @stack = []
      @control_frames = []
    end

    def execute_main(iseq)
      main = RObject.new(Core.cObject, [])
      control_frame = ControlFrame.new(main, Environment.new(Core.cObject, nil))
      @control_frames.push(control_frame)

      until @control_frames.empty?
        execute(iseq)
      end
    end

    def execute(iseq)
      control_frame = @control_frames.last
      insn = iseq.instructions[control_frame.pc]

      puts "executing: #{insn.type}"

      case insn.type
      when :leave
        @control_frames.pop
      when :put_object
        push_stack insn.arguments[0]
        control_frame.pc += 1
      when :put_self
        push_stack control_frame.self_value
        control_frame.pc += 1
      when :send
        mid = insn.arguments[0]
        argc = insn.arguments[1]
        args = pop_stack_multi(argc)
        target = pop_stack
        method = find_method(target, mid)
        ret = dispatch_method(target, method, args)
        push_stack(ret)
        control_frame.pc += 1
      else
        raise "unknown instruction: #{insn.type}"
      end
    end

    def push_stack(obj)
      control_frame = @control_frames.last
      @stack[control_frame.sp] = obj
      control_frame.sp += 1
    end

    def pop_stack
      control_frame = @control_frames.last
      obj = @stack[control_frame.sp - 1]
      control_frame.sp -= 1
      obj
    end

    def pop_stack_multi(n)
      control_frame = @control_frames.last
      objects = @stack[(control_frame.sp - n)...control_frame.sp]
      control_frame.sp -= n
      objects
    end

    def rb_call(recv, mid, *args)
      method = find_method(recv, mid)
      dispatch_method(recv, method, args)
    end

    def find_method(target, mid)
      klass = target.klass
      method = klass.method_table[mid]
      while method.nil?
        klass = klass.super_class
        if klass.nil?
          # method_missing
          raise "undefined method #{mid} for #{target}"
        end
        method = klass.method_table[mid]
      end
      method
    end

    def dispatch_method(target, method, args)
      case method
      when BuiltInMethod
        method.block.call(target, *args)
      else
        raise "NOT IMPLEMENTED: #{method.class} dispatch"
      end
    end
  end
end
