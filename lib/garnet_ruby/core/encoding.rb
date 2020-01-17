module GarnetRuby
  module Core
    def self.init_encoding
      @cEncoding = rb_define_class(:Encoding, cObject)
    end
  end
end
