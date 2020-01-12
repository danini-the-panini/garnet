module GarnetRuby
  module Core
    class << self
      def math_exp(_, x)
        RPrimitive.from(Math.exp(x.num_to_dbl))
      end
    end

    def self.init_math
      mMath = rb_define_module(:Math)

      rb_define_module_function(mMath, :exp, &method(:math_exp))
    end
  end
end