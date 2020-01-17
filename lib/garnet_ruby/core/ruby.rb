module GarnetRuby
  module Core
    def self.prog_init(vm, options)
      inject_env(vm)

      rb_define_global_variable(:$0, RString.from(options[:script_name]))

      inject_global_variables(vm, options[:global_variables])

      rb_define_global_const(:ARGV, RArray.from(options[:argv]))
    end
  end
end
