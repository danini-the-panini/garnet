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
    def self.init_file
      @cFile = rb_define_class(:File, cIO)
    end
  end
end
