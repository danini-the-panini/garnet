module GarnetRuby
  module Core
    def self.init_transcode
      @eUndefinedConversionError = rb_define_class_under(cEncoding, :UndefinedConversionError, eEncodingError)
      @eInvalidByteSequenceError = rb_define_class_under(cEncoding, :InvalidByteSequenceError, eEncodingError)
      @eConverterNotFoundError = rb_define_class_under(cEncoding, :ConverterNotFoundError, eEncodingError)
    end
  end
end