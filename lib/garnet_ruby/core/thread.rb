module GarnetRuby
  module Core
    def self.init_thread
      @cThread = rb_define_class(:Thread)
    end
  end
end