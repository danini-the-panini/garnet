require 'pathname'

module GarnetRuby
  module Core
    class << self
      def rb_f_load(_, *args)
        fname, wrap = args

        fname = rb_get_path(fname)
        path = fname.string_value

        full_path = resolve_file_for_require(path)

        if full_path.nil?
          rb_raise(eLoadError, "cannot load such file -- #{path}")
        end

        load_internal(full_path, rtest(wrap))
      end

      def rb_f_require(_, fname)
        rb_require_string(fname)
      end

      def rb_f_require_relative(_, fname)
        base = current_realfilepath
        rb_raise(eLoadError, 'cannot infer basepath') if base == Q_NIL

        base = file_dirname(base)
        rb_require_string(rb_file_absolute_path(fname, base))
      end

      def rb_require_string(fname)
        fname = rb_get_path(fname)
        path = fname.string_value

        path = add_rb_extension(path)
        full_path = resolve_file_for_require(path)

        if full_path.nil?
          rb_raise(eLoadError, "cannot load such file -- #{path}")
        end

        return Q_FALSE if @required_files[full_path]

        @required_files[full_path] = true

        load_internal(full_path)

        Q_TRUE
      end

      def load_internal(full_path, wrap=false)
        if File.extname(full_path) == ".rbo"
          ret = load(full_path)
          return ret ? Q_TRUE : Q_FALSE
        end

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

        # TODO: wrap
        VM.instance.execute_load_iseq(iseq)
      end

      def resolve_file_for_require(path)
        if Pathname.new(path).absolute?
          return File.exist?(path) ? path : nil
        end

        load_path.array_value.each do |load_path|
          load_path = load_path.str_to_str.string_value
          full_path = File.join(load_path, path)
          return full_path if File.exist?(full_path)
        end
        nil
      end

      def add_rb_extension(path)
        return "#{path}.rb" unless ['.rb', '.rbo'].include?(File.extname(path))

        path
      end

      attr_accessor :load_path
    end

    def self.init_load
      @load_path = RArray.new(cArray, [], $LOAD_PATH.map { |s| RString.from(s) })
      @load_path.array_value.unshift(RString.from(File.expand_path('../../../garnet_lib', __dir__)))

      rb_define_virtual_variable(:'$:', method(:load_path), method(:load_path=))
      rb_define_virtual_variable(:'$-I', method(:load_path), method(:load_path=))
      rb_define_virtual_variable(:$LOAD_PATH, method(:load_path), method(:load_path=))

      get_loaded_features = -> { RArray.from(@required_files.keys) }
      rb_define_virtual_variable(:'$"', get_loaded_features, nil)
      rb_define_virtual_variable(:$LOADED_FEATURES, get_loaded_features, nil)

      rb_define_global_variable(:'$:', $LOAD_PATH)

      rb_define_global_function(:load, &method(:rb_f_load))
      rb_define_global_function(:require, &method(:rb_f_require))
      rb_define_global_function(:require_relative, &method(:rb_f_require_relative))
    end
  end
end
