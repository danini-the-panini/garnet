module GarnetRuby
  class RIO < RObject
    attr_reader :io

    def initialize(klass, flags, io)
      super(klass, flags)
      @io = io
    end

    def self.from(io)
      RIO.new(Core.cIO, [], io)
    end

    def io_print(*args)
      args.each do |arg|
        io.print(Core.rb_funcall(arg, :to_s).string_value)
      end
      Q_NIL
    end

    def io_puts(*args)
      if args.empty?
        print("\n")
        return Q_NIL
      end

      args.each do |arg|
        if arg.is_a?(RArray)
          io_puts(*arg.array_value)
        else
          print Core.rb_funcall(arg, :to_s).string_value
          print "\n"
        end
      end
      Q_NIL
    end

    def io_flush
      io.flush
      self
    end

    def io_close
      io.close
      self
    end

    def io_gets(*args)
      case args.length
      when 3
        sep, limit, getline_args = args
      when 2
        if args.first.type?(Integer)
          sep = Core.rs
          limit = args.first.value
        else
          sep = args.first
          limit = args[1].type?(Integer) ? args[1].value : -1
        end
      when 1
        if args.first.type?(Integer)
          sep = Core.rs
          limit = args.first.value
        else
          sep = args.first
          limit = -1
        end
      else
        sep = Core.rs
        limit = -1
      end

      sep = sep.is_a?(RString) ? sep.string_value : nil

      # TODO: extract getline_args
      line = RString.from(io.gets(sep, limit))
      Core.last_read_line = line
      line
    end
  end

  module Core
    class << self
      def rb_f_backquote(_, str)
        result = `#{str.string_value}`
        RString.from(result)
      end

      def io_alloc(klass)
        RIO.new(klass, [], nil)
      end

      def io_s_open(klass, *args)
        io = rb_class_new_instance(klass, *args)

        if rb_block_given?
          begin
            return rb_yield(io)
          ensure
            io.io_close
          end
        end

        io
      end

      def io_s_read(_, *args)
        name = args.first.obj_as_string.string_value
        # TODO: more args

        RString.from(IO.read(name))
      end

      def io_s_binread(_, *args)
        name = args.first.obj_as_string.string_value
        # TODO: more args

        RString.from(IO.binread(name))
      end

      def rb_printf(*args)
        return Q_NIL if args.length.zero?

        if args.first.is_a?(RString)
          out = @stdout
        else
          out = args.first
          _, *args = args
        end
        out.io_print(rb_sprintf(*args))
        Q_NIL
      end

      def rb_p(obj)
        str = rb_funcall(obj, :inspect).obj_as_string
        puts str.string_value
      end

      def rb_f_p(*args)
        args.each do |arg|
          rb_p(arg)
        end
        if args.length == 1
          args[0]
        elsif args.length > 1
          RArray.from(args)
        else
          Q_NIL
        end
      end

      def rb_open(path, mode = "r", perm = nil, opt = nil)
        if path.string_value.start_with?('|')
          # TODO
        else
          RFile.open(path, mode, perm, opt)
        end
      end

      def io_isatty(io)
        io.io.tty? ? Q_TRUE : Q_FALSE
      end

      attr_accessor :output_fs, :output_rs, :rs, :last_read_line
    end

    def self.init_io
      @eIOError = rb_define_class(:IOError, eStandardError)
      @eEOFError = rb_define_class(:EOFError, eIOError)

      rb_define_global_function(:syscall, &method(:TODO_not_implemented))

      rb_define_global_function(:open) { |_, *args| rb_open(*args) }
      rb_define_global_function(:printf) { |_, *args| rb_printf(*args) }
      rb_define_global_function(:print) { |_, *args| @stdout.io_print(*args) }
      rb_define_global_function(:putc, &method(:TODO_not_implemented))
      rb_define_global_function(:puts) { |_, *args| @stdout.io_puts(*args) }
      rb_define_global_function(:gets, &method(:TODO_not_implemented))
      rb_define_global_function(:readline, &method(:TODO_not_implemented))
      rb_define_global_function(:select, &method(:TODO_not_implemented))

      rb_define_global_function(:readlines, &method(:TODO_not_implemented))

      rb_define_global_function(:'`', &method(:rb_f_backquote))

      rb_define_global_function(:p) { |_, *args| rb_f_p(*args) }
      rb_define_method(mKernel, :display, &method(:TODO_not_implemented))

      @cIO = rb_define_class(:IO, cObject)
      cIO.include_module(mEnumerable)

      @mWaitReadable = rb_define_module_under(cIO, :WaitReadable)
      @mWaitWritable = rb_define_module_under(cIO, :WaitWritable)

      rb_define_alloc_func(cIO, &method(:io_alloc))
      rb_define_singleton_method(cIO, :new, &method(:TODO_not_implemented))
      rb_define_singleton_method(cIO, :open, &method(:io_s_open))
      rb_define_singleton_method(cIO, :sysopen, &method(:TODO_not_implemented))
      rb_define_singleton_method(cIO, :for_fd, &method(:TODO_not_implemented))
      rb_define_singleton_method(cIO, :popen, &method(:TODO_not_implemented))
      rb_define_singleton_method(cIO, :foreach, &method(:TODO_not_implemented))
      rb_define_singleton_method(cIO, :readlines, &method(:TODO_not_implemented))
      rb_define_singleton_method(cIO, :read, &method(:io_s_read))
      rb_define_singleton_method(cIO, :binread, &method(:io_s_binread))
      rb_define_singleton_method(cIO, :write, &method(:TODO_not_implemented))
      rb_define_singleton_method(cIO, :binwrite, &method(:TODO_not_implemented))
      rb_define_singleton_method(cIO, :select, &method(:TODO_not_implemented))
      rb_define_singleton_method(cIO, :pipe, &method(:TODO_not_implemented))
      rb_define_singleton_method(cIO, :try_convert, &method(:TODO_not_implemented))
      rb_define_singleton_method(cIO, :copy_stream, &method(:TODO_not_implemented))

      rb_define_method(cIO, :initialize, &method(:TODO_not_implemented))

      @output_fs = Q_NIL
      rb_define_virtual_variable(:'$,', method(:output_fs), method(:output_fs=))

      @default_rs = RString.from("\n")
      @rs = @default_rs
      @output_rs = Q_NIL
      rb_define_virtual_variable(:'$/', method(:rs), method(:rs=))
      rb_define_virtual_variable(:'$-0', method(:rs), method(:rs=))
      rb_define_virtual_variable(:'$\\', method(:output_rs), method(:output_rs=))

      @last_read_line = Q_NIL
      rb_define_virtual_variable(:'$_', method(:last_read_line), method(:last_read_line=))

      rb_define_method(cIO, :initialize_copy, &method(:TODO_not_implemented))
      rb_define_method(cIO, :reopen, &method(:TODO_not_implemented))

      rb_define_method(cIO, :print) { |io, *args| io.io_print(*args) }
      rb_define_method(cIO, :putc, &method(:TODO_not_implemented))
      rb_define_method(cIO, :puts) { |io, *args| io.io_puts(*args) }
      rb_define_method(cIO, :printf, &method(:TODO_not_implemented))

      rb_define_method(cIO, :each, &method(:TODO_not_implemented))
      rb_define_method(cIO, :each_line, &method(:TODO_not_implemented))
      rb_define_method(cIO, :each_byte, &method(:TODO_not_implemented))
      rb_define_method(cIO, :each_char, &method(:TODO_not_implemented))
      rb_define_method(cIO, :each_codepoint, &method(:TODO_not_implemented))
      rb_define_method(cIO, :lines, &method(:TODO_not_implemented))
      rb_define_method(cIO, :bytes, &method(:TODO_not_implemented))
      rb_define_method(cIO, :chars, &method(:TODO_not_implemented))
      rb_define_method(cIO, :codepoints, &method(:TODO_not_implemented))

      rb_define_method(cIO, :syswrite, &method(:TODO_not_implemented))
      rb_define_method(cIO, :sysread, &method(:TODO_not_implemented))

      rb_define_method(cIO, :pread, &method(:TODO_not_implemented))
      rb_define_method(cIO, :pwrite, &method(:TODO_not_implemented))

      rb_define_method(cIO, :fileno, &method(:TODO_not_implemented))
      rb_alias_method(cIO, :to_i, :fileno)
      rb_define_method(cIO, :to_io, &method(:TODO_not_implemented))

      rb_define_method(cIO, :fsync, &method(:TODO_not_implemented))
      rb_define_method(cIO, :fdatasync, &method(:TODO_not_implemented))
      rb_define_method(cIO, :sync, &method(:TODO_not_implemented))
      rb_define_method(cIO, :sync=, &method(:TODO_not_implemented))

      rb_define_method(cIO, :lineno, &method(:TODO_not_implemented))
      rb_define_method(cIO, :lineno=, &method(:TODO_not_implemented))

      rb_define_method(cIO, :readlines, &method(:TODO_not_implemented))

      rb_define_method(cIO, :readpartial, &method(:TODO_not_implemented))
      rb_define_method(cIO, :read, &method(:TODO_not_implemented))
      rb_define_method(cIO, :write, &method(:TODO_not_implemented))
      rb_define_method(cIO, :gets) { |io, *args| io.io_gets(*args) }
      rb_define_method(cIO, :readline, &method(:TODO_not_implemented))
      rb_define_method(cIO, :getc, &method(:TODO_not_implemented))
      rb_define_method(cIO, :getbyte, &method(:TODO_not_implemented))
      rb_define_method(cIO, :readchar, &method(:TODO_not_implemented))
      rb_define_method(cIO, :readbyte, &method(:TODO_not_implemented))
      rb_define_method(cIO, :ungetbyte, &method(:TODO_not_implemented))
      rb_define_method(cIO, :ungetc, &method(:TODO_not_implemented))
      rb_define_method(cIO, :<<, &method(:TODO_not_implemented))
      rb_define_method(cIO, :flush) { |io| io.io_flush }
      rb_define_method(cIO, :tell, &method(:TODO_not_implemented))
      rb_define_method(cIO, :seek, &method(:TODO_not_implemented))
      rb_define_method(cIO, :rewind, &method(:TODO_not_implemented))
      rb_define_method(cIO, :pos, &method(:TODO_not_implemented))
      rb_define_method(cIO, :pos=, &method(:TODO_not_implemented))
      rb_define_method(cIO, :eof, &method(:TODO_not_implemented))
      rb_define_method(cIO, :eof?) { |io| io.io.eof? ? Q_TRUE : Q_FALSE }

      rb_define_method(cIO, :close_on_exec?, &method(:TODO_not_implemented))
      rb_define_method(cIO, :close_on_exec=, &method(:TODO_not_implemented))

      rb_define_method(cIO, :close) { |io| io.io_close }
      rb_define_method(cIO, :closed?, &method(:TODO_not_implemented))
      rb_define_method(cIO, :close_read, &method(:TODO_not_implemented))
      rb_define_method(cIO, :close_write, &method(:TODO_not_implemented))

      rb_define_method(cIO, :isatty, &method(:io_isatty))
      rb_define_method(cIO, :tty?, &method(:io_isatty))
      rb_define_method(cIO, :binmode, &method(:TODO_not_implemented))
      rb_define_method(cIO, :binmode?, &method(:TODO_not_implemented))
      rb_define_method(cIO, :sysseek, &method(:TODO_not_implemented))
      rb_define_method(cIO, :advise, &method(:TODO_not_implemented))

      rb_define_method(cIO, :ioctl, &method(:TODO_not_implemented))
      rb_define_method(cIO, :fcntl, &method(:TODO_not_implemented))
      rb_define_method(cIO, :pid, &method(:TODO_not_implemented))
      rb_define_method(cIO, :inspect, &method(:TODO_not_implemented))

      rb_define_method(cIO, :external_encoding, &method(:TODO_not_implemented))
      rb_define_method(cIO, :internal_encoding, &method(:TODO_not_implemented))
      rb_define_method(cIO, :set_encoding, &method(:TODO_not_implemented))
      rb_define_method(cIO, :set_encoding_by_bom, &method(:TODO_not_implemented))

      rb_define_method(cIO, :autoclose?, &method(:TODO_not_implemented))
      rb_define_method(cIO, :autoclose=, &method(:TODO_not_implemented))

      @stdin = RIO.from(STDIN)

      rb_define_global_variable(:$stdin, @stdin)
      @stdout = RIO.from(STDOUT)
      rb_define_virtual_variable(:$stdout, -> { @stdout }, ->(x) { @stdout = x })
      @stderr = RIO.from(STDERR)
      rb_define_virtual_variable(:$stderr, -> { @stderr }, ->(x) { @stderr = x })
      @orig_stdout = @stdout
      @orig_stderr = @stderr

      rb_define_global_const(:STDIN, stdin)
      rb_define_global_const(:STDOUT, stdout)
      rb_define_global_const(:STDERR, stderr)
    end
  end
end
