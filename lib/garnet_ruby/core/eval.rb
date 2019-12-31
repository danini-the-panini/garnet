module GarnetRuby
  module Core
    class << self
      def rb_mod_include(mod, *args)
        # TODO: check type if args (they must be Module)
        # TODO: check that module has not already been included
        # TODO: call hooks
        args.reverse_each do |arg|
          mod.include_module(arg)
        end
        mod
      end
    end

    def self.init_eval
      rb_define_method(cModule, :include, &method(:rb_mod_include))


    end
  end
end