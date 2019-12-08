module GarnetRuby
  class RHash < RObject
    attr_reader :hash_value

    def initialize(klass, flags, hash_value)
      super(klass, flags)
      @hash_value = hash_value
    end

    def self.from(h)
      return Q_NIL if h.nil?

      new(Core.cHash, [], h.map { |k, v| [Core.ruby2garnet(k), Core.ruby2garnet(v)] }.to_h)
    end
  end

  module Core
    class << self
      def hash_inspect(hash)
        strings = hash.hash_value.map do |key, value|
          [rb_funcall(key, :inspect).string_value, rb_funcall(value, :inspect).string_value]
        end.to_h
        RString.from("{#{strings.map { |k, v| "#{k}=>#{v}" }.join(', ')}}")
      end

      def hash_aref(hash, key)
        # TODO: call default
        hash.hash_value[key] || Q_NIL
      end
    end

    def self.init_hash
      @cHash = rb_define_class(:Hash)

      rb_define_method(cHash, :inspect, &method(:hash_inspect))
      rb_alias_method(cHash, :to_s, :inspect)

      rb_define_method(cHash, :[], &method(:hash_aref))
    end
  end
end
