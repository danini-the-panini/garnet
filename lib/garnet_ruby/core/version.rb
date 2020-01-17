module GarnetRuby
  module Core
    def self.init_version
      rb_define_global_const(:RUBY_VERSION, RString.from(EQ_RUBY_VERSION))
      rb_define_global_const(:RUBY_ENGINE, RString.from(ENGINE_NAME))
      rb_define_global_const(:RUBY_ENGINE_VERSION, RString.from(VERSION))
    end
  end
end
