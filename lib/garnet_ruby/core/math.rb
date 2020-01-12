module GarnetRuby
  module Core
    class << self
      def math_exp(_, x)
        RPrimitive.from(Math.exp(x.num_to_dbl))
      end

      def math_sqrt(_, x)
        # TODO: handle complex
        d = x.num_to_dbl
        domain_error("sqrt") if d.negative?
        return RPrimitive.from(0.0) if d.zero?
        RPrimitive.from(Math.sqrt(d))
      end

      def domain_error(msg)
        rb_raise(eMathDomainError, "Numerical argument is out of bounds - #{msg}")
      end
    end

    def self.init_math
      mMath = rb_define_module(:Math)

      rb_define_module_function(mMath, :exp, &method(:math_exp))
      rb_define_module_function(mMath, :sqrt, &method(:math_sqrt))
    end
  end
end