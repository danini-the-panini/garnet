module GarnetRuby
  module Core
    def self.init_version
      rb_define_global_const(:RUBY_VERSION, RString.from(GARNET_RUBY_VERSION))
      rb_define_global_const(:RUBY_PLATFORM, RString.from(GARNET_PLATFORM))
      rb_define_global_const(:RUBY_ENGINE, RString.from(GARNET_ENGINE))
      rb_define_global_const(:RUBY_ENGINE_VERSION, RString.from(GARNET_VERSION))
      rb_define_global_const(:RUBY_DESCRIPTION, RString.from(GARNET_DESCRIPTION))
    end
  end
end
