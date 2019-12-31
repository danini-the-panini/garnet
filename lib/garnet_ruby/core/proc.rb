module GarnetRuby
  class RProc < RObject
    attr_accessor :block
    attr_reader :is_lambda, :is_from_method

    def initialize(klass, flags, block, is_lambda = false, is_from_method = false)
      super(klass, flags)
      @block = block
      block.proc = self
      @is_lambda = is_lambda
      @is_from_method = is_from_method
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
  
  class RMethod < RObject
    attr_reader :method_entry, :recv

    def initialize(klass, flags, method_entry, recv = Q_UNDEF)
      super(klass, flags)
      @method_entry = method_entry
      @recv = recv
    end
  end

  module Core
    class << self
      def proc_s_new(_, *args)
        prc = new_proc(false)
        rb_funcall(prc, :initialize, *args)
        prc
      end

      def new_proc(is_lambda)
        block = VM.instance.current_control_frame.block
        RProc.new(cProc, [], block, is_lambda)
      end

      def proc_call(proc, *args)
        VM.instance.execute_block(proc.block, args, VM.instance.current_control_frame.block)
      end

      def f_proc(_)
        new_proc(false)
      end

      def f_lambda(_)
        new_proc(true)
      end

      def proc_clone(prc)
        # TODO: clone setup (I think it copies singleton classes)
        proc_dup(prc)
      end

      def proc_dup(prc)
        RProc.new(cProc, [], prc.block, prc.is_lambda, prc.is_from_method)
      end

      def method_call(m, *args)
        if m.recv == Q_UNDEF
          raise TypeError, "can't call unbound method; bind first"
        end
        block = VM.instance.current_control_frame.block
        VM.instance.dispatch_method(m.recv, m.method_entry, args, block)
      end

      def method_to_proc(m)
        env = VM.instance.current_control_frame.environment
        block = BuiltInBlock.new(env, m) do |*args|
          method_call(m, *args)
        end
        prc = RProc.new(cProc, [], block, true, true)
        prc
      end
    end

    def self.init_proc
      @cProc = rb_define_class(:Proc, cObject)
      rb_undef_alloc_func(cProc)
      rb_define_singleton_method(cProc, :new, &method(:proc_s_new))

      rb_define_method(cProc, :call, &method(:proc_call))
      rb_define_method(cProc, :[], &method(:proc_call))
      rb_define_method(cProc, :===, &method(:proc_call))
      rb_define_method(cProc, :yield, &method(:proc_call))

      rb_define_method(cProc, :to_proc) { |x| x }
      rb_define_method(cProc, :clone, &method(:proc_clone))
      rb_define_method(cProc, :dup, &method(:proc_dup))

      # Exceptions
      @eLocalJumpError = rb_define_class(:LocalJumpError, eStandardError)

      # utility functions
      rb_define_global_function(:proc, &method(:f_proc))
      rb_define_global_function(:lambda, &method(:f_lambda))

      # Method
      @cMethod = rb_define_class(:Method, cObject)
      rb_undef_alloc_func(cMethod)
      rb_define_method(cMethod, :call, &method(:method_call))
      rb_define_method(cMethod, :to_proc, &method(:method_to_proc))
    end
  end
end
