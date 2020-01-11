module GarnetRuby
  module Core
    class << self
      def get_process_id
        RPrimitive.from($$)
      end

      def rb_time_interval(num)
        if num.numeric?
          num.value
        else
          num2long(num)
        end
      end

      def rb_f_sleep(_, *args)
        ret = if args.empty?
                sleep
              else
                sleep(rb_time_interval(args.first))
              end

        RPrimitive.from(ret)
      end

      def proc_rb_f_kill(_, *args)
        rb_f_kill(*args)
      end

      def rb_f_kill(*args)
        if fixnum?(args[0])
          sig = args[0].value
        else
          sig = signm2signo(args[0], true, false, nil)
        end

        return RPrimitive.from(0) if args.length <= 1

        pids = args[1..].map { |a| num2long(a) }

        ret = Process.kill(sig, *pids)

        RPrimitive.from(ret)
      end
    end

    def self.init_process
      rb_define_virtual_variable(:'$$', method(:get_process_id), nil)
      rb_define_global_function(:sleep, &method(:rb_f_sleep))

      @mProcess = rb_define_module(:Process)

      rb_define_module_function(mProcess, :kill, &method(:proc_rb_f_kill))
    end
  end
end