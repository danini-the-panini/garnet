module RubyRuby
  class RBasic
    attr_accessor :klass, :flags

    def initialize(klass, flags)
      @klass = klass
      @flags = flags
    end
  end
end
