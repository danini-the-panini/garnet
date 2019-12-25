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
  end

  module Core
    class << self
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

      rb_define_global_function(:`) do |_, str|
        RString.from(`#{str.string_value}`)
      end

      @cIO = rb_define_class(:IO, cObject)

      rb_define_method(cIO, :flush) { |io| io.io_flush }

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
