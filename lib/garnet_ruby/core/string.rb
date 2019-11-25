module GarnetRuby
  class RString < RBasic
    attr_reader :string_value

    def initialize(klass, flags, string_value)
      super(klass, flags)
      @string_value = string_value
    end

    def to_s
      string_value.inspect
    end
  end

  module Core
    def self.init_string
      @cString = rb_define_class(:String)

      rb_define_method(cString, :to_s) do |x|
        x
      end
    end
  end
end
