module GarnetRuby
  module Core
    class << self
    end

    def self.init_vm
      @cRubyVM = rb_define_class(:RubyVM, cObject)
    end
  end
end