module GarnetRuby
  module Core
    class << self
      def marsh_dump(_, *args)
        RString.from("TODO")
      end

      def marsh_load(_, *args)
        RString.from("TODO")
      end
    end

    def self.init_marshal
      @mMarshal = rb_define_module(:Marshal)

      rb_define_module_function(mMarshal, :dump, &method(:marsh_dump))
      rb_define_module_function(mMarshal, :load, &method(:marsh_load))
      rb_define_module_function(mMarshal, :restore, &method(:marsh_load))
    end
  end
end