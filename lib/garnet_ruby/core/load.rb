module GarnetRuby
  module Core
    class << self
      def rb_f_require(_, fname)
        rb_require_string(fname)
      end

      def rb_require_string(fname)
        fname = rb_get_path(fname)
        path = fname.string_value

        full_path = resolve_file_for_require(path)

        if full_path.nil?
          rb_raise(eLoadError, "cannot load such file -- #{path}")
        end

        return Q_FALSE if @required_files[full_path]

        @required_files[full_path] = true

        source = File.read(full_path)

        parser = Parser.new(source, full_path)
        node = parser.parse
        if __grb_debug__?
          puts '-eval-'
          pp node
          puts '------'
        end

        iseq = Iseq.new('<top (required)>', :top)
        Compiler.new(iseq).compile_node(node)

        VM.instance.execute_load_iseq(iseq)

        Q_TRUE
      end

      def resolve_file_for_require(path)
        path = add_rb_extension(path)
        $LOAD_PATH.each do |load_path|
          full_path = File.join(load_path, path)
          return full_path if File.exists?(full_path)
        end
        nil
      end

      def add_rb_extension(path)
        return path if File.extname(path) == '.rb'

        "#{path}.rb"
      end
    end

    def self.init_load
      $GARNET_LOAD_PATH = RArray.new(cArray, [], $LOAD_PATH.map { |s| RString.from(s) })

      lp_getter = -> { $GARNET_LOAD_PATH }
      lp_setter = -> (v) { $GARNET_LOAD_PATH = v }
      rb_define_virtual_variable(:'$:', lp_getter, lp_setter)
      rb_define_virtual_variable(:$-I, lp_getter, lp_setter)
      rb_define_virtual_variable(:$LOAD_PATH, lp_getter, lp_setter)

      rb_define_global_variable(:'$:', $LOAD_PATH)

      rb_define_global_function(:require, &method(:rb_f_require))
    end
  end
end
