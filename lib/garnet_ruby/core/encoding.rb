module GarnetRuby
  class REncoding < RObject
    attr_accessor :enc_value

    def initialize(klass, flags, enc_value)
      super(klass, flags)
      @enc_value = enc_value
    end

    def self.from(enc)
      return Q_NIL if enc.nil?

      raise "NOT AN ENCODING: #{enc.inspect}" unless enc.is_a?(Encoding)

      new(Core.cEncoding, [], enc)
    end
  end

  module Core
    class << self
      def str_to_encoding(enc)
        REncoding.from(Encoding.find(enc.string_value))
      rescue ArgumentError => e
        rb_raise(eArgError, e.message)
      end

      def rb_to_encoding(enc)
        return enc if enc.is_a?(REncoding)
        str_to_encoding(enc)
      end

      def enc_to_s(enc)
        RString.from(enc.enc_value.to_s)
      end

      def enc_name(enc)
        RString.from(enc.enc_value.name)
      end

      def enc_names(enc)
        RArray.from(enc.enc_value.names)
      end

      def enc_inspect(enc)
        RString.from("#<#{enc.klass.real.name}:#{enc.enc_value}>")
      end

      def enc_list(_)
        RArray.from(@encodings)
      end
    end

    def self.init_encoding
      @cEncoding = rb_define_class(:Encoding, cObject)
      rb_define_method(cEncoding, :to_s, &method(:enc_to_s))
      rb_define_method(cEncoding, :name, &method(:enc_name))
      rb_define_method(cEncoding, :names, &method(:enc_names))
      rb_define_method(cEncoding, :inspect, &method(:enc_inspect))
      rb_define_singleton_method(cEncoding, :list, &method(:enc_list));

      @encodings = []

      Encoding.list.each do |encoding|
        enc = REncoding.from(encoding)
        encoding.names.each do |s|
          s = "#{s[0].upcase}#{s[1..].gsub(/-/, '_')}"
          id = s.to_sym
          id2 = s.upcase.to_sym
          rb_define_const(cEncoding, id, enc)
          rb_define_const(cEncoding, id2, enc) if id != id2
        end
        @encodings << enc
      end
    end
  end
end
