module GarnetRuby
  module Core
    class << self
      def check_dirname(dir)
        # TODO
        rb_get_path(dir)
      end

      def dir_s_getwd(_)
        RString.from(Dir.pwd)
      end

      def dir_s_rmdir(obj, dir)
        dir = check_dirname(dir)

        Dir.delete(dir.string_value)

        RPrimitive.from(0)
      rescue SystemCallError => e
        rb_raise(@syserr_tbl[e.errno], e.message)
      end

      def dir_s_aref(_, *args)
        RArray.from(Dir[*args.map{ |s| s.obj_as_string.string_value }])
      rescue SystemCallError => e
        rb_raise(@syserr_tbl[e.errno], e.message)
      end
    end

    def self.init_dir
      @cDir = rb_define_class(:Dir, cObject)

      rb_define_singleton_method(cDir, :pwd, &method(:dir_s_getwd))
      rb_define_singleton_method(cDir, :delete, &method(:dir_s_rmdir))

      rb_define_singleton_method(cDir, :[], &method(:dir_s_aref))
    end
  end
end
