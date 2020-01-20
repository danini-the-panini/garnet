module GarnetRuby
  class RProc < RObject
    attr_accessor :block
    attr_reader :is_lambda, :is_from_method, :arity

    def initialize(klass, flags, block, is_lambda = false, is_from_method = false, arity = block&.arity)
      super(klass, flags)
      @block = block
      block.proc = self
      @is_lambda = is_lambda
      @is_from_method = is_from_method
      @arity = arity
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

    def description
      block.description
    end

    def proc
      self
    end
  end
  
  class RMethod < RObject
    attr_reader :method_entry, :recv

    def initialize(klass, flags, method_entry, recv = Q_UNDEF)
      super(klass, flags)
      @method_entry = method_entry
      @recv = recv
    end

    def arity
      method_entry.arity
    end
  end

  class RBinding < RObject
    attr_reader :cfp

    def initialize(klass, flags, cfp)
      super(klass, flags)
      @cfp = cfp
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
        unless rb_block_given?
          rb_raise(eArgError, 'tried to create Proc object without a block')
        end

        block = VM.instance.current_control_frame.block
        RProc.new(cProc, [], block, is_lambda)
      end

      def proc_call(proc, *args, block: nil, self_value: nil, klass: nil)
        vm = VM.instance
        block_block = block || vm.current_control_frame.block
        begin
          vm.execute_block(proc.block, args, args.length, block_block, self_value, nil, klass)
        rescue GarnetThrow => e
          case e
          when GarnetThrow::Break
            return e.value if proc.lambda?
            raise unless vm.is_block_orphan?(proc.block)

            vm.do_raise(make_localjump_error('break from proc-closure', e.value, :break))
          when GarnetThrow::Return
            raise unless proc.lambda?

            e.value
          else
            raise
          end
        end
      end

      def f_proc(_)
        new_proc(false)
      end

      def f_lambda(_)
        new_proc(true)
      end

      def proc_arity(prc)
        RPrimitive.from(prc.arity)
      end

      def proc_clone(prc)
        # TODO: clone setup (I think it copies singleton classes)
        proc_dup(prc)
      end

      def proc_to_s(prc)
        RString.from("#<Proc #{prc.description}>")
      end

      def proc_dup(prc)
        RProc.new(cProc, [], prc.block, prc.is_lambda, prc.is_from_method)
      end

      def make_localjump_error(message, value, reason)
        exc = RObject.new(eLocalJumpError, [])
        exc.ivar_set(:message, RString.from(message))
        exc.ivar_set(:@exit_value, value)
        exc.ivar_set(:@reason, RSymbol.from(reason))
        exc
      end

      def localjump_exit_value(exc)
        exc.ivar_get(:@exit_value)
      end

      def localjump_reason(exc)
        exc.ivar_get(:@reason)
      end

      def method_call(m, *args)
        if m.recv == Q_UNDEF
          rb_raise(eTypeError, "can't call unbound method; bind first")
        end
        block = VM.instance.current_control_frame.block
        VM.instance.dispatch_method(m.recv, m.method_entry, args, block)
      end

      def method_arity(m)
        RPrimitive.from(m.arity)
      end

      def method_to_proc(m)
        env = VM.instance.current_control_frame.environment
        block = BuiltInBlock.new(env, m) do |*args|
          method_call(m, *args)
        end
        prc = RProc.new(cProc, [], block, true, true, m.arity)
        prc
      end

      def obj_is_method(m)
        m.is_a?(RMethod)
      end

      def mod_define_method(mod, *args)
        name = args.first
        id = check_id(name)
        if args.length == 1
          body = VM.instance.current_control_frame.block
        else
          body = args[1]

          if body.is_a?(RMethod)
            is_method = true
          elsif body.is_a?(RProc)
            is_method = false
          else
            rb_raise(eTypeError, "wrong argument type #{body.klass} (expected Proc/Method/UnboundMethod)")
          end
        end

        if is_method
          # TODO
        else
          definition = ProcMethodDef.new(body.proc)
          rb_add_method(mod, id, :public, definition)
        end

        RSymbol.from(id)
      end

      def rb_binding_new
        vm = VM.instance
        vm.make_binding(vm.current_control_frame)
      end

      def rb_f_binding(_)
        rb_binding_new
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
      rb_define_method(cProc, :arity, &method(:proc_arity))
      rb_define_method(cProc, :clone, &method(:proc_clone))
      rb_define_method(cProc, :dup, &method(:proc_dup))
      rb_define_method(cProc, :to_s, &method(:proc_to_s))
      rb_alias_method(cProc, :inspect, :to_s)

      # Exceptions
      @eLocalJumpError = rb_define_class(:LocalJumpError, eStandardError)
      rb_define_method(eLocalJumpError, :exit_value, &method(:localjump_exit_value))
      rb_define_method(eLocalJumpError, :reason, &method(:localjump_reason))

      # utility functions
      rb_define_global_function(:proc, &method(:f_proc))
      rb_define_global_function(:lambda, &method(:f_lambda))

      # Method
      @cMethod = rb_define_class(:Method, cObject)
      rb_undef_alloc_func(cMethod)
      rb_define_method(cMethod, :call, &method(:method_call))
      rb_define_method(cMethod, :arity, &method(:method_arity))
      rb_define_method(cMethod, :to_proc, &method(:method_to_proc))

      # Module#*_method
      rb_define_method(cModule, :define_method, &method(:mod_define_method))

      # Init_Binding
      @cBinding = rb_define_class(:Binding, cObject)
      rb_undef_alloc_func(cBinding)
      rb_define_global_function(:binding, &method(:rb_f_binding))
    end
  end
end
