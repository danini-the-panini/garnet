module GarnetRuby
  class RHash < RObject
    attr_reader :table

    def initialize(klass, flags)
      super(klass, flags)
      @table = {}
    end

    def type
      Hash
    end

    def type?(x)
      x == Hash
    end

    def self.from(h)
      return Q_NIL if h.nil?

      hsh = new(Core.cHash, [])
      h.each do |k, v|
        key = Core.ruby2garnet(k)
        value = Core.ruby2garnet(v)

        Core.hash_aset(hsh, key, value)
      end
      hsh
    end

    def entries
      @table.values.flatten
    end

    def size
      entries.length
    end

    class Entry
      attr_reader :key
      attr_accessor :value

      def initialize(key, value)
        @key = key
        @value = value
      end

      def hash_code
        Core.rb_funcall(key, :hash).value ^ Core.rb_funcall(value, :hash).value
      end

      def key_eql?(k)
        Core.rtest(Core.rb_funcall(key, :eql?, k))
      end
    end
  end

  module Core
    class << self
      def empty_hash_alloc(klass)
        RHash.new(klass, [])
      end

      def hash_inspect(hash)
        strings = hash.entries.map do |e|
          [rb_funcall(e.key, :inspect).string_value, rb_funcall(e.value, :inspect).string_value]
        end.to_h
        RString.from("{#{strings.map { |k, v| "#{k}=>#{v}" }.join(', ')}}")
      end

      def hash_aset(hash, k, v)
        kh = rb_funcall(k, :hash).value
        entries = hash.table[kh] ||= []
        entry = entries.find { |e| e.key_eql?(k) }
        if entry
          entry.value = v
        else
          entries << RHash::Entry.new(k, v)
        end
      end

      def hash_aref(hash, k)
        kh = rb_funcall(k, :hash).value
        entry = hash.table[kh]&.find { |e| e.key_eql?(k) }
        entry&.value || Q_NIL
      end

      def hash_has_key(hash, k)
        kh = rb_funcall(k, :hash).value
        entries = hash.table[kh]
        return Q_FALSE unless entries

        entries.any? { |e| e.key_eql?(k) } ? Q_TRUE : Q_FALSE
      end

      def hash_delete_entry(hash, key)
        kh = rb_funcall(key, :hash).value
        entries = hash.table[kh]
        return Q_UNDEF if entries.nil?

        entry = entries.find { |e| e.key_eql?(key) }
        return Q_UNDEF if entry.nil?

        entries.delete(entry)
        hash.table.delete(kh) if entries.empty?

        entry.value
      end

      def hash_size(hash)
        RPrimitive.from(hash.size)
      end

      def hash_equal(hash1, hash2)
        hash_equal_internal(hash1, hash2, false)
      end

      def hash_eql(hash1, hash2)
        hash_equal_internal(hash1, hash2, true)
      end

      def hash_equal_internal(hash1, hash2, eql)
        return Q_TRUE if hash1 == hash2

        if !hash2.type?(Hash)
          if !VM.instance.rb_respond_to(hash2, :to_hash)
            return Q_FALSE
          end
          if eql
            return rb_eql(hash2, hash1)
          else
            return rb_equal(hash2, hash1)
          end
        end
        return Q_FALSE if hash1.entries.size != hash2.entries.size
        return Q_TRUE if hash1.entries.empty? && hash2.entries.empty?

        hash1.entries.each do |e|
          return Q_FALSE unless rtest(hash_has_key(hash2, e.key))

          value2 = hash_aref(hash2, e.key)
          result = eql ? rb_eql(e.value, value2) : rb_equal(e.value, value2)
          return Q_FALSE unless rtest(result)
        end

        Q_TRUE
      end

      def hash_hash(hash)
        RPrimitive.from(hash.entries.reduce(0) { |h, e| h + e.hash_code })
      end

      def hash_each_pair(hash)
        if rb_block_arity > 1
          hash.entries.each do |e|
            rb_yield(e.key, e.value)
          end
        else
          hash.entries.each do |e|
            rb_yield(RArray.from([e.key, e.value]))
          end
        end
        hash
      end

      def hash_keys(hash)
        RArray.from(hash.entries.map(&:key))
      end

      def hash_values(hash)
        RArray.from(hash.entries.map(&:value))
      end

      def hash_values_at(hash, *args)
        result = RArray.from([])

        args.each do |arg|
          ary_push(result, hash_aref(hash, arg))
        end

        result
      end

      def hash_shift(hash)
        # TODO: default value
        return Q_NIL if hash.size.zero?

        entry = hash.entries.first
        hash_delete_entry(hash, entry.key)

        RArray.from([entry.key, entry.value])
      end

      def hash_has_value(hash, value)
        hash.entries.each do |entry|
          return Q_TRUE if rb_equal(entry.value, value) == Q_TRUE
        end
        Q_FALSE
      end
    end

    def self.init_hash
      @cHash = rb_define_class(:Hash)

      cHash.include_module(mEnumerable)

      rb_define_alloc_func(cHash, &method(:empty_hash_alloc))

      rb_define_method(cHash, :inspect, &method(:hash_inspect))
      rb_alias_method(cHash, :to_s, :inspect)

      rb_define_method(cHash, :==, &method(:hash_equal))
      rb_define_method(cHash, :[], &method(:hash_aref))
      rb_define_method(cHash, :hash, &method(:hash_hash))
      rb_define_method(cHash, :eql?, &method(:hash_eql))
      rb_define_method(cHash, :[]=, &method(:hash_aset))
      rb_define_method(cHash, :size, &method(:hash_size))
      rb_define_method(cHash, :length, &method(:hash_size))

      rb_define_method(cHash, :each_pair, &method(:hash_each_pair))
      rb_define_method(cHash, :each, &method(:hash_each_pair))

      rb_define_method(cHash, :keys, &method(:hash_keys))
      rb_define_method(cHash, :values, &method(:hash_values))
      rb_define_method(cHash, :values_at, &method(:hash_values_at))

      rb_define_method(cHash, :shift, &method(:hash_shift))

      rb_define_method(cHash, :include?, &method(:hash_has_key))
      rb_define_method(cHash, :member?, &method(:hash_has_key))
      rb_define_method(cHash, :has_key?, &method(:hash_has_key))
      rb_define_method(cHash, :has_value?, &method(:hash_has_value))
      rb_define_method(cHash, :key?, &method(:hash_has_key))
      rb_define_method(cHash, :value?, &method(:hash_has_value))
    end
  end
end
