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
        print Core.rb_funcall(arg, :to_s).string_value
        print "\n"
      end
      Q_NIL
    end
  end

  module Core
    def self.init_io
      rb_define_global_function(:print) { |_, *args| @stdout.io_print(*args) }
      rb_define_global_function(:puts) { |_, *args| @stdout.io_puts(*args) }

      rb_define_global_function(:`) do |_, str|
        RString.from(`#{str.string_value}`)
      end

      @cIO = rb_define_class(:IO, cObject)

      @stdin = RIO.from(STDIN)
      @stdout = RIO.from(STDOUT)
      @stderr = RIO.from(STDERR)

      rb_define_global_const(:STDIN, stdin)
      rb_define_global_const(:STDOUT, stdout)
      rb_define_global_const(:STDERR, stderr)
    end
  end
end
