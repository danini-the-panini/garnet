module GarnetRuby
  class RRegexp < RBasic
    attr_reader :regexp_value

    def initialize(klass, flags, value)
      super(klass, flags)
      @regexp_value = value
    end
  end

  module Core
    class << self
      def reg_match(re, str)
         # TODO: convert str to string
         pos = re.regexp_value =~ str.string_value
         return Q_NIL if pos.nil?
         RPrimitive.from(pos)
      end
    end

    def self.init_regexp
      @cRegexp = rb_define_class(:Regexp, cObject)

      rb_define_method(cRegexp, :=~, &method(:reg_match))
    end
  end
end
