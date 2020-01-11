module GarnetRuby
  module Core
    NSIG = 64

    SIGHUP    = 1
    SIGINT    = 2
    SIGQUIT   = 3
    SIGILL    = 4
    SIGTRAP   = 5
    SIGABRT   = 6
    SIGIOT    = 6
    SIGBUS    = 7
    SIGFPE    = 8
    SIGKILL   = 9
    SIGUSR1   = 10
    SIGSEGV   = 11
    SIGUSR2   = 12
    SIGPIPE   = 13
    SIGALRM   = 14
    SIGTERM   = 15
    SIGSTKFLT = 16
    SIGCHLD   = 17
    SIGCONT   = 18
    SIGSTOP   = 19
    SIGTSTP   = 20
    SIGTTIN   = 21
    SIGTTOU   = 22
    SIGURG    = 23
    SIGXCPU   = 24
    SIGXFSZ   = 25
    SIGVTALRM = 26
    SIGPROF   = 27
    SIGWINCH  = 28
    SIGIO     = 29
    SIGPOLL   = SIGIO

    SIGLOST   = 29
    SIGPWR    = 30
    SIGSYS    = 31
    SIGUNUSED = 31

    SIGRTMIN  = 32
    SIGRTMAX  = NSIG

    RUBY_SIGCHLD = SIGCHLD

    Sig = Struct.new(:signm, :signo)
    SIGLIST = [
      Sig.new("EXIT",    0),
      Sig.new("HUP",     SIGHUP),
      Sig.new("INT",     SIGINT),
      Sig.new("QUIT",    SIGQUIT),
      Sig.new("ILL",     SIGILL),
      Sig.new("TRAP",    SIGTRAP),
      Sig.new("ABRT",    SIGABRT),
      Sig.new("IOT",     SIGIOT),
      # Sig.new("EMT",     SIGEMT),
      Sig.new("FPE",     SIGFPE),
      Sig.new("KILL",    SIGKILL),
      Sig.new("BUS",     SIGBUS),
      Sig.new("SEGV",    SIGSEGV),
      Sig.new("SYS",     SIGSYS),
      Sig.new("PIPE",    SIGPIPE),
      Sig.new("ALRM",    SIGALRM),
      Sig.new("TERM",    SIGTERM),
      Sig.new("URG",     SIGURG),
      Sig.new("STOP",    SIGSTOP),
      Sig.new("TSTP",    SIGTSTP),
      Sig.new("CONT",    SIGCONT),
      Sig.new("CHLD",    RUBY_SIGCHLD),
      Sig.new("CLD",     RUBY_SIGCHLD),
      Sig.new("TTIN",    SIGTTIN),
      Sig.new("TTOU",    SIGTTOU),
      Sig.new("IO",      SIGIO),
      Sig.new("XCPU",    SIGXCPU),
      Sig.new("XFSZ",    SIGXFSZ),
      Sig.new("VTALRM",  SIGVTALRM),
      Sig.new("PROF",    SIGPROF),
      Sig.new("WINCH",   SIGWINCH),
      Sig.new("USR1",    SIGUSR1),
      Sig.new("USR2",    SIGUSR2),
      # Sig.new("LOST",    SIGLOST),
      # Sig.new("MSG",     SIGMSG),
      Sig.new("PWR",     SIGPWR),
      Sig.new("POLL",    SIGPOLL),
      # Sig.new("DANGER",  SIGDANGER),
      # Sig.new("MIGRATE", SIGMIGRATE),
      # Sig.new("PRE",     SIGPRE),
      # Sig.new("GRANT",   SIGGRANT),
      # Sig.new("RETRACT", SIGRETRACT),
      # Sig.new("SOUND",   SIGSOUND),
      # Sig.new("INFO",    SIGINFO),
    ]

    SIGNAME_PREFIX = "SIG"
    SIGNAME_PREFIX_LEN = SIGNAME_PREFIX.length
    LONGEST_SIGNAME = SIGLIST.map{ |s| s.signm.length }.max

    class << self
      def signo2signm(no)
        SIGLIST.each do |sigs|
          return sigs.signm if sigs.signo == no
        end
        nil
      end

      def signm2signo(vsig, negative, exit, prefix)
        prefix = 0

        if vsig.type?(Symbol)
          vsig = vsig.sym2str
        elsif !vsig.type?(String)
          str = vsig.check_string_type
          if str == Q_NIL
            rb_raise(eArgError, "bad signal type #{vsig.klass}")
          end
          vsig = str
        end

        nm = vsig.string_value
        len = vsig.length
        if nm.include?("\0")
          rb_raise(eArgError, "signal name with null byte")
        end

        if len.positive? && nm[0] == '-'
          if !negative
            rb_raise(eArgError, "negative symbol name: #{vsig}")
          end
          prefix = 1
        else
          negative = false
        end
        if len >= prefix + SIGNAME_PREFIX_LEN
          if nm[prefix, SIGNAME_PREFIX_LEN] == SIGNAME_PREFIX
            prefix += SIGNAME_PREFIX_LEN
          end
        end
        if len > prefix
          nm = nm[prefix..]
          SIGLIST.each do |sigs|
            next if sigs.signo == 0 && !exit

            if sigs.signm == nm
              return negative ? -sigs.signo : sigs.signo
            end
          end
        end

        if prefix == SIGNAME_PREFIX_LEN
          prefix = 0
        elsif prefix > SIGNAME_PREFIX_LEN
          prefix -= SIGNAME_PREFIX_LEN
          len -= prefix
          vsig = RString.from(vsig.subseq(prefix, len))
          prefix = 0
        else
          len -= prefix
          vsig = RString.from(vsig.subseq(prefix, len))
          prefix = SIGNAME_PREFIX_LEN
        end
        rb_raise(eArgError, "unsupported signal #{SIGNAME_PREFIX[0, prefix]}#{vsig}")
      end

      def trap_signm(vsig)
        if fixnum?(vsig)
          sig = vsig.value
          if sig.negative? || sig > NSIG
            rb_raise(eArgError, "invalid signal number (#{sig})")
          end
        else
          sig = signm2signo(vsig, false, true, nil)
        end
        sig
      end

      def reserved_signal?(signo)
        [SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGVTALRM].include?(signo)
      end

      def trap_handler(cmd, sig)
        return "SIG_IGN" if cmd == Q_NIL

        command = cmd.check_string_type
        if command == Q_NIL && cmd.type?(Symbol)
          command = cmd.sym2str.string_value
          rb_raise(eArgError, "bad handler") if !command
        end
        if command != Q_NIL
          case command.string_value
          when "", "SIG_IGN", "IGNORE"
            "SIG_IGN"
          when "SYSTEM_DEFAULT"
            if sig == RUBY_SIGCHLD
              "SIG_DFL"
            else
              "SYSTEM_DEFAULT"
            end
          when "SIG_DFL", "DEFAULT"
            "SIG_DFL"
          when "EXIT"
            "EXIT"
          else
            command.string_value
          end
        else
          proc_ptr(cmd)
        end
      end

      def sig_trap(_, *args)
        sig = trap_signm(args[0])
        if reserved_signal?(sig)
          name = signo2signm(sig)
          if name
            rb_raise(eArgError, "can't trap reserved signal: SIG#{name}")
          else
            rb_raise(eArgError, "can't trap reserved signal: #{sig}")
          end
        end

        if args.length == 1
          cmd = proc_ptr(rb_block_proc)
        else
          cmd = trap_handler(args[1], sig)
        end

        trap(sig, cmd)
      end
    end

    def self.init_signal
      rb_define_global_function(:trap, &method(:sig_trap))
    end
  end
end