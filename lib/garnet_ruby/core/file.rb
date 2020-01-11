module GarnetRuby
  class RFile < RIO
    def initialize(klass, flags, file_value)
      super(klass, flags, file_value)
    end

    def self.from(file)
      return Q_NIL if file.nil?

      new(Core.cFile, [], file)
    end

    def self.open(filename, mode="r", perm = nil, opt = nil)
      m = if mode.type?(Integer)
            mode.value
          else
            mode.string_value
          end

      # TODO: perm and opt
      from(File.new(filename.string_value, m))
    end
  end

  module Core
    class << self
      def file_s_unlink(_, *args)
        args.each { |f| File.unlink(f.string_value) }
      end

      def define_filetest_function(name)
        x = -> (_, *args) { File.__send__(name, *args.map(&:string_value)) ? Q_TRUE : Q_FALSE }
        rb_define_module_function(mFileTest, name, &x)
        rb_define_singleton_method(cFile, name, &x)
      end
    end

    def self.init_file
      @mFileTest = rb_define_module(:FileTest)
      @cFile = rb_define_class(:File, cIO)

      define_filetest_function(:directory?)
      define_filetest_function(:exist?)
      define_filetest_function(:exists?)
      define_filetest_function(:readable?)
      define_filetest_function(:readable_real?)
      define_filetest_function(:world_readable?)
      define_filetest_function(:writable?)
      define_filetest_function(:writable_real?)
      define_filetest_function(:world_writable?)
      define_filetest_function(:executable?)
      define_filetest_function(:executable_real?)
      define_filetest_function(:file?)
      define_filetest_function(:zero?)
      define_filetest_function(:empty?)
      define_filetest_function(:size?)
      define_filetest_function(:size)
      define_filetest_function(:owned?)
      define_filetest_function(:grpowned?)

      define_filetest_function(:pipe?)
      define_filetest_function(:symlink?)
      define_filetest_function(:socket?)

      define_filetest_function(:blockdev?)
      define_filetest_function(:chardev?)

      define_filetest_function(:setuid?)
      define_filetest_function(:setgid?)
      define_filetest_function(:sticky?)

      define_filetest_function(:identical?)

      rb_define_singleton_method(cFile, :unlink, &method(:file_s_unlink))
    end
  end
end
