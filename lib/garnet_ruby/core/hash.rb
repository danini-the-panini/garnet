module GarnetRuby
  class RHash < RObject
    attr_accessor :table, :ifnone, :proc_default

    def initialize(klass, flags)
      super(klass, flags)
      @table = {}
      @ifnone = Q_NIL
      @proc_default = false
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

        hsh.update(key, value)
      end
      hsh
    end

    def entries
      @table.values.flatten
    end

    def size
      entries.length
    end

    def default=(ifnone)
      @ifnone = ifnone
      @proc_default = false
    end

    def default_proc=(ifnone)
      @ifnone = ifnone
      @proc_default = true
    end

    def key?(key)
      !get(key).nil?
    end

    def get(key)
      hash = Core.hash_of(key)
      lookup(hash, key)
    end

    def lookup(hash, key)
      entry = table[hash]&.find { |e| e.key_eql?(key) }
      entry&.value
    end

    def aset(hash, key, value)
      entries = table[hash] ||= []
      entry = entries.find { |e| e.key_eql?(key) }
      if entry
        entry.value = value
      else
        entries << RHash::Entry.new(k, value)
      end
    end

    def update(key, value)
      hash = Core.hash_of(key)
      entries = table[hash] ||= []
      entry = entries.find { |e| e.key_eql?(key) }
      if entry
        entry.value = value
      else
        entries << RHash::Entry.new(key, value)
      end
    end

    def delete_entry(key)
      hash = Core.hash_of(key)
      entries = table[hash] ||= []
      entry, = entries.delete_if { |e| e.key_eql?(key) }
      entry
    end

    class Entry
      attr_reader :key
      attr_accessor :value

      def initialize(key, value)
        @key = key
        @value = value
      end

      def hash_code
        Core.hash_of(key) ^ Core.hash_of(value)
      end

      def key_eql?(k)
        Core.rtest(Core.rb_funcall(key, :eql?, k))
      end
    end
  end

  module Core
    class << self
      def hash_of(obj)
        rb_funcall(obj, :hash).value
      end

      def hash_alloc_flags(klass, flags, ifnone)
        hash = RHash.new(klass, flags)
        hash.ifnone = ifnone
        hash
      end

      def hash_alloc(klass)
        hash_alloc_flags(klass, [], Q_NIL)
      end

      def empty_hash_alloc(klass)
        hash_alloc(klass)
      end

      def hash_s_create(klass, *args)
        if args.length == 1
          tmp = hash_s_try_convert(Q_NIL, args[0])
          if tmp != Q_NIL
            hash = hash_alloc(klass)
            hash.table = table_copy(tmp.table)
            return hash
          end

          tmp = args[0].check_array_type
          if tmp != Q_NIL
            hash = hash_alloc(klass)
            tmp.array_value.each_with_index do |e, i|
              v = e.check_array_type
              val = Q_NIL

              if v == Q_NIL
                rb_raise(eArgError, "wrong element type #{e.klass.name} at #{i} (expected array)")
              end
              l = v.len
              if l < 1 || l > 2
                rb_raise(eArgError, "invalid anumber of elements at #{i} (#{l} for 1..2)")
              end
              if l >= 1
                key = v.array_value[0]
                if l == 2
                  val = v.array_value[1]
                end
                hash_aset(hash, key, val)
              end
            end
            return hash
          end
        end
        if args.length.odd?
          rb_raise(eArgError, 'odd number of arguments for Hash')
        end

        hash = hash_alloc(klass)
        hash_bulk_insert(hash, *args)
        return hash
      end

      def table_copy(table)
        new_table = {}
        table.each do |k, v|
          new_table[k] = v.map { |e| RHash::Entry.new(e.key, e.value) }
        end
        new_table
      end

      def hash_bulk_insert(hash, *args)
        return if args.empty?

        args.each_slice(2) do |k, v|
          hash_aset(hash, k, v)
        end
      end

      def hash_s_try_convert(_, hash)
        hash.check_hash_type
      end

      def hash_initialize(hash, *args)
        if rb_block_given?
          hash.ifnone = rb_block_proc
          hash.proc_default = true
        else
          hash.ifnone = args.length == 0 ? Q_NIL : args.first
          hash.proc_default = false
        end
      end

      def hash_inspect(hash)
        strings = hash.entries.map do |e|
          [rb_funcall(e.key, :inspect).string_value, rb_funcall(e.value, :inspect).string_value]
        end.to_h
        RString.from("{#{strings.map { |k, v| "#{k}=>#{v}" }.join(', ')}}")
      end

      def hash_aset(hash, k, v)
        hash.update(k, v)
        v
      end

      def hash_lookup(hash, k)
        kh = hash_of(k)
        hash.lookup(kh, k)
      end

      def hash_aref(hash, k)
        hash_lookup(hash, k) || hash_default_value(hash, k)
      end

      def hash_default_value(hash, key = Q_UNDEF)
        if rb_method_basic_definition?(hash.klass, :default)
          ifnone = hash.ifnone
          return ifnone unless hash.proc_default
          return Q_NIL if key == Q_UNDEF

          rb_funcall(ifnone, :yield, hash, key)
        else
          rb_funcall(hash, :default, key)
        end
      end

      def hash_set_default(hash, ifnone)
        hash.default = ifnone
        ifnone
      end

      def hash_default_proc(hash)
        return hash.ifnone if hash.proc_default
        Q_NIL
      end

      def hash_set_default_proc(hash, prc)
        if prc == Q_NIL
          hash_set_default(hash, prc)
          return prc
        end
        b = prc.rb_check_convert_type_with_id(Proc, "Proc", :to_proc)
        if b == Q_NIL || !b.type?(Proc)
          rb_raise(eTypeError, "wrong default_proc type #{prc.klass} (expected Proc)")
        end
        prc = b
        hash.default_proc = prc
        prc
      end

      def hash_has_key(hash, k)
        kh = hash_of(k)
        entries = hash.table[kh]
        return Q_FALSE unless entries

        entries.any? { |e| e.key_eql?(k) } ? Q_TRUE : Q_FALSE
      end

      def hash_delete_entry(hash, key)
        kh = hash_of(key)
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

      def hash_empty_p(hash)
        hash.size.zero? ? Q_TRUE : Q_FALSE
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

      def hash_fetch(hash, *args)
        key = args[0]

        block_given = rb_block_given?
        if block_given && args.length == 2
          puts 'WARNING: block supersedes default value argument'
        end

        if val = hash_lookup(hash, key)
          val
        elsif block_given
          rb_yield(key)
        elsif args.length == 1
          rb_raise(eKeyError, "key not found: #{key}")
        else
          args[1]
        end
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
        return hash_default_value(hash) if hash.size.zero?

        entry = hash.entries.first
        hash_delete_entry(hash, entry.key)

        RArray.from([entry.key, entry.value])
      end

      def hash_invert(hash)
        h = RHash.from({})

        hash.entries.each do |e|
          h.update(e.value, e.key)
        end

        h
      end

      def hash_delete(hash, key)
        entry = hash.delete_entry(key)

        if entry
          entry.value
        else
          return rb_yield(key) if rb_block_given?

          Q_NIL
        end
      end

      def hash_update_block_i(hash, entry)
        val = entry.value
        if oldval = hash.get(entry.key)
          val = rb_yield(entry.key, oldval, val)
        end
        hash.update(entry.key, val)
      end

      def hash_update(hash, *args)
        block_given = rb_block_given?

        args.each do |other_hash|
          if block_given
            other_hash.entries.each do |e|
              hash_update_block_i(hash, e)
            end
          else
            other_hash.entries.each do |e|
              hash.update(e.key, e.value)
            end
          end
        end

        hash
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
      rb_define_singleton_method(cHash, :[], &method(:hash_s_create))
      rb_define_method(cHash, :initialize, &method(:hash_initialize))

      rb_define_method(cHash, :inspect, &method(:hash_inspect))
      rb_alias_method(cHash, :to_s, :inspect)

      rb_define_method(cHash, :==, &method(:hash_equal))
      rb_define_method(cHash, :[], &method(:hash_aref))
      rb_define_method(cHash, :hash, &method(:hash_hash))
      rb_define_method(cHash, :eql?, &method(:hash_eql))
      rb_define_method(cHash, :fetch, &method(:hash_fetch))
      rb_define_method(cHash, :[]=, &method(:hash_aset))
      rb_define_method(cHash, :default, &method(:hash_default_value))
      rb_define_method(cHash, :default=, &method(:hash_set_default))
      rb_define_method(cHash, :default_proc, &method(:hash_default_proc))
      rb_define_method(cHash, :default_proc=, &method(:hash_set_default_proc))
      rb_define_method(cHash, :size, &method(:hash_size))
      rb_define_method(cHash, :length, &method(:hash_size))
      rb_define_method(cHash, :empty?, &method(:hash_empty_p))

      rb_define_method(cHash, :each_pair, &method(:hash_each_pair))
      rb_define_method(cHash, :each, &method(:hash_each_pair))

      rb_define_method(cHash, :keys, &method(:hash_keys))
      rb_define_method(cHash, :values, &method(:hash_values))
      rb_define_method(cHash, :values_at, &method(:hash_values_at))

      rb_define_method(cHash, :shift, &method(:hash_shift))
      rb_define_method(cHash, :delete, &method(:hash_delete))
      rb_define_method(cHash, :invert, &method(:hash_invert))
      rb_define_method(cHash, :update, &method(:hash_update))
      rb_define_method(cHash, :merge!, &method(:hash_update))

      rb_define_method(cHash, :include?, &method(:hash_has_key))
      rb_define_method(cHash, :member?, &method(:hash_has_key))
      rb_define_method(cHash, :has_key?, &method(:hash_has_key))
      rb_define_method(cHash, :has_value?, &method(:hash_has_value))
      rb_define_method(cHash, :key?, &method(:hash_has_key))
      rb_define_method(cHash, :value?, &method(:hash_has_value))
    end
  end
end
