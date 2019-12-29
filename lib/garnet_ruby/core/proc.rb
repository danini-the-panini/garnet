module GarnetRuby
  class RProc < RObject
    attr_accessor :block

    def initialize(klass, flags, block, is_lambda = false)
      super(klass, flags)
      @block = block
      block.proc = self
      @is_lambda = is_lambda
    end

    def type
      Proc
    end

    def type?(x)
      x == Proc
    end


    def lambda?
      @is_lambda
    end

    def to_s
      "<#Proc block=#{block}>"
    end
    alias inspect to_s
  end

  module Core
    class << self
      def new_proc(is_lambda)
        block = VM.instance.current_control_frame.block
        RProc.new(cProc, [], block, is_lambda)
      end

      def proc_call(proc, *args)
        VM.instance.execute_block(proc.block, args)
      end

      def f_proc(_)
        new_proc(false)
      end

      def f_lambda(_)
        new_proc(true)
      end
    end

    def self.init_proc
      @cProc = rb_define_class(:Proc, cObject)

      rb_define_method(cProc, :call, &method(:proc_call))
      rb_define_method(cProc, :[], &method(:proc_call))
      rb_define_method(cProc, :===, &method(:proc_call))
      rb_define_method(cProc, :yield, &method(:proc_call))

      rb_define_method(cProc, :to_proc) { |x| x }

      # utility functions
      rb_define_global_function(:proc, &method(:f_proc))
      rb_define_global_function(:lambda, &method(:f_lambda))
    end
  end
end
