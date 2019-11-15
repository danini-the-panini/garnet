module RubyRuby
  class RHash < RBasic
    attr_reader :hash_value

    def initialize(klass, flags, hash_value)
      super(klass, flags)
      @hash_value = hash_value
    end
  end

  module Core
    def self.init_hash
      @cHash = rb_define_class(:Hash)

      rb_define_method(cHash, :inspect) do |hash|
        strings = hash.hash_value.map do |key, value|
          [rb_funcall(key, :inspect).string_value, rb_funcall(value, :inspect).string_value]
        end.to_h
        RString.new(cString, 0, "{#{strings.map { |k, v| "#{k}=>#{v}" }.join(', ')}}")
      end
      rb_alias_method(cHash, :to_s, :inspect)
    end
  end
end
