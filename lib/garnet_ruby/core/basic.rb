module GarnetRuby
  class RBasic
    attr_accessor :klass, :flags

    def initialize(klass, flags)
      @klass = klass
      @flags = flags
    end

    def to_s
      "<##{klass.name}>"
    end
    alias inspect to_s

    def type
      nil
    end

    def type?(_)
      false
    end
  end
end
