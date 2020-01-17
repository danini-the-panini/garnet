module GarnetRuby
  module Core
    class << self
      EXIT_SUCCESS = 0
      EXIT_FAILURE = 1

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

      def exit_status_code(status)
        case status
        when Q_TRUE then EXIT_SUCCESS
        when Q_FALSE then EXIT_FAILURE
        else num2long(status)
        end
      end

      def rb_exit(status)
        # TODO: raise SystemExit
        exit(status)
      end

      def rb_f_exit(*args)
        istatus = if args.length == 1
                    exit_status_code(args.first)
                  else
                    EXIT_SUCCESS
                  end

        rb_exit(istatus)
      end

      def f_exit(_, *args)
        rb_f_exit(*args)
      end

      def rb_f_abort(*args)
        unless args.empty?
          arg = args[0].str_to_str
          STDERR.puts(arg.string_value)
        end
        rb_exit(EXIT_FAILURE)
      end

      def f_abort(_, *args)
        rb_f_abort(*args)
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
      rb_define_global_function(:exit, &method(:f_exit))
      rb_define_global_function(:abort, &method(:f_abort))

      @mProcess = rb_define_module(:Process)

      rb_define_module_function(mProcess, :kill, &method(:proc_rb_f_kill))
    end
  end
end
