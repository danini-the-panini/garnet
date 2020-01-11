module GarnetRuby
  module Core
    class << self
      def dir_s_aref(_, *args)
        RArray.from(Dir[*args.map{ |s| s.obj_as_string.string_value }])
      end
    end

    def self.init_dir
      @cDir = rb_define_class(:Dir, cObject)

      rb_define_singleton_method(cDir, :[], &method(:dir_s_aref))
    end
  end
end