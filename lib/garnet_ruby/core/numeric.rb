module GarnetRuby
  module Core
    def self.init_numeric
      @cNumeric = rb_define_class(:Numeric, cObject)

      @cInteger = rb_define_class(:Integer, cNumeric)
      rb_define_method(cInteger, :+) do |x, y|
        # TODO: type coersion
        RPrimitive.new(cInteger, 0, x.value + y.value)
      end
      rb_define_method(cInteger, :to_s) do |x, base = 10|
        RString.new(cString, 0, x.value.to_s(base))
      end
      rb_alias_method(cInteger, :inspect, :to_s)
    end
  end
end
