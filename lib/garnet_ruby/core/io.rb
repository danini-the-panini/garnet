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
    end

    def io_close
      io.close
    end

    def io_gets(*args)
      case args.length
      when 3
        sep, limit, getline_args = args
      when 2
        if args.first.type?(Integer)
          sep = VM.instance.get_global(:'$/')
          limit = args.first.value
        else
          sep = args.first
          limit = args[1].type?(Integer) ? args[1].value : -1
        end
      when 1
        if args.first.type?(Integer)
          sep = VM.instance.get_global(:'$/')
          limit = args.first.value
        else
          sep = args.first
          limit = -1
        end
      else
        sep = VM.instance.get_global(:'$/')
        limit = -1
      end

      sep = sep.is_a?(RString) ? sep.string_value : nil

      # TODO: extract getline_args
      RString.from(io.gets(sep, limit))
    end
  end

  module Core
    class << self
      def io_alloc(klass)
        RIO.new(klass, [], nil)
      end

      def io_s_read(_, *args)
        name = args.first.obj_as_string.string_value
        # TODO: more args

        RString.from(IO::read(name))
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
    end

    def self.init_io
      rb_define_global_function(:open) { |_, *args| rb_open(*args) }
      rb_define_global_function(:print) { |_, *args| @stdout.io_print(*args) }
      rb_define_global_function(:puts) { |_, *args| @stdout.io_puts(*args) }
      rb_define_global_function(:printf) { |_, *args| rb_printf(*args) }

      rb_define_global_function(:'`') do |_, str|
        result = `#{str.string_value}`
        RString.from(result)
      end

      rb_define_global_function(:p) { |_, *args| rb_f_p(*args) }

      @cIO = rb_define_class(:IO, cObject)

      rb_define_alloc_func(cIO, &method(:io_alloc))
      rb_define_singleton_method(cIO, :read, &method(:io_s_read))

      rb_define_global_variable(:'$/', RString.from($/))

      rb_define_method(cIO, :print) { |io, *args| io.io_print(*args) }

      rb_define_method(cIO, :gets) { |io, *args| io.io_gets(*args) }
      rb_define_method(cIO, :flush) { |io| io.io_flush }
      rb_define_method(cIO, :eof?) { |io| io.io.eof? ? Q_TRUE : Q_FALSE }

      rb_define_method(cIO, :close) { |io| io.io_close }

      @stdin = RIO.from(STDIN)
      @stdout = RIO.from(STDOUT)
      @stderr = RIO.from(STDERR)

      rb_define_global_const(:STDIN, stdin)
      rb_define_global_const(:STDOUT, stdout)
      rb_define_global_const(:STDERR, stderr)
    end
  end
end
