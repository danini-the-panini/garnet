module GarnetRuby
  module Core
    class << self
      def str_encode(str, *args)
        # TODO: kwargs, src/dst encoding
        enc = rb_to_encoding(args.first).enc_value
        RString.from(str.string_value.encode(enc))
      end

      def str_encode_bang(str, *args)
        # TODO: kwargs, src/dst encoding
        enc = rb_to_encoding(args.first).enc_value
        enc = rb_to_encoding(args.first).enc_value
        str.string_value.encode!(enc)

        str
      end
    end

    def self.init_transcode
      @eUndefinedConversionError = rb_define_class_under(cEncoding, :UndefinedConversionError, eEncodingError)
      @eInvalidByteSequenceError = rb_define_class_under(cEncoding, :InvalidByteSequenceError, eEncodingError)
      @eConverterNotFoundError = rb_define_class_under(cEncoding, :ConverterNotFoundError, eEncodingError)
      
      rb_define_method(cString, :encode, &method(:str_encode))
      rb_define_method(cString, :encode!, &method(:str_encode_bang))
    end
  end
end