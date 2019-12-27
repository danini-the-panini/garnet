module GarnetRuby
  class RArray < RObject
    attr_reader :array_value

    def initialize(klass, flags, array_value)
      super(klass, flags)
      @array_value = array_value
    end

    def to_s
      "[#{array_value.map(&:to_s).join(', ')}]"
    end

    def self.from(ary)
      return Q_NIL if ary.nil?

      new(Core.cArray, [], ary.map { |x| Core.ruby2garnet(x) })
    end

    def type
      Array
    end

    def type?(x)
      x == Array
    end

    def len
      array_value.length
    end
  end

  module Core
    class << self
      def ary_inspect(ary)
        strings = ary.array_value.map do |item|
          rb_funcall(item, :to_s).string_value
        end
        RString.from("[#{strings.join(', ')}]")
      end

      def ary_entry(ary, offset)
        len = ary.len
        return Q_NIL if len.zero?
        if offset.negative?
          offset += len
          return Q_NIL if offset.negative?
        elsif len <= offset
          return Q_NIL
        end
        ary.array_value[offset]
      end

      def ary_subseq(ary, beg, len)
        alen = ary.len

        return Q_NIL if beg > alen
        return Q_NIL if beg.negative? || len.negative?

        if alen < len || alen < beg + len
          len = alen - beg
        end
        klass = ary.klass
        return RArray.new(klass, [], []) if len.zero?

        RArray.new(klass, [], ary.array_value[beg, len])
      end

      def ary_aref2(ary, b, e)
        beg = num2long(b)
        ed = num2long(e)
        beg += ary.len if beg.negative?
        ary_subseq(ary, beg, ed)
      end

      def ary_aref1(ary, arg)
        return ary_entry(ary, arg.value) if fixnum?(arg)

        result, beg, len = range_beg_len(arg, ary.len, 0)
        return Q_NIL if result == Q_NIL
        return ary_subseq(ary, beg, len) unless result == Q_FALSE

        return ary_entry(ary, num2long(arg))
      end

      def ary_aref(ary, *args)
        if args.length == 2
          return ary_aref2(ary, args[0], args[1])
        end
        ary_aref1(ary, args[0])
      end

      def ary_splice(ary, beg, len, rpl)
        ary.array_value[beg, len] = rpl.array_value
      end

      def ary_mem_clear(ary, beg, size)
        size.times do |i|
          ary.array_value[beg + i] = Q_NIL
        end
      end

      def ary_store(ary, idx, val)
        len = ary.len

        if idx.negative?
          idx += len
          if idx.negative?
            raise IndexError, "index #{idx - len} too small for array; minimum #{-len}"
          end
          # TODO: check against ARY_MAX_SIZE
        end

        if idx > len
          ary_mem_clear(ary, len, idx - len + 1)
        end

        ary.array_value[idx] = val
      end

      def ary_aset(ary, *args)
        if args.length == 3
          beg = num2long(args[0])
          len = num2long(args[1])
          ary_splice(ary, beg, len, args.last.ary_to_ary)
          return args.last
        end

        if fixnum?(args[0])
          ary_store(ary, args[0].value, args[1])
          return args[1]
        end

        result, beg, len = range_beg_len(range, ary.len, 1)
        if rtest(result)
          ary_splice(ary, beg, len, args.last.ary_to_ary)
          return args.last
        end

        ary_store(ary, num2long(args[0]), args[1])
        args[1]
      end

      def ary_includes(ary, item)
        ary.array_value.any? { |e| rb_equal(item, e) } ? Q_TRUE : Q_FALSE
      end

      def ary_includes_by_eql(ary, item)
        ary.array_value.any? { |e| rb_eql(item, e) } ? Q_TRUE : Q_FALSE
      end

      def ary_join(ary, sep)
        return RString.from("") if ary.len.zero?

        if sep != Q_NIL
          sep = sep.str_to_str
        end
        strings = ary.array_value.map do |v|
          next v if v.type?(String)
          next ary_join_recursive(ary, sep, v) if v.type?(Array)

          tmp = v.check_string_type
          next tmp unless tmp == Q_NIL

          tmp = v.check_array_type
          next ary_join_recursive(ary, sep, v) unless tmp == Q_NIL

          v.obj_as_string
        end

        RString.from(strings.map(&:string_value).join(sep.string_value))
      end

      def ary_join_recursive(ary, sep, v)
        # TODO: exec recursively
        ary_join(v, sep)
      end

      def ary_pop(ary)
        ary.array_value.pop
      end

      def ary_empty_p(ary)
        ary.array_value.empty? ? Q_TRUE : Q_FALSE
      end

      def ary_plus(x, y)
        RArray.from(x.array_value + y.to_array_type.array_value)
      end

      def ary_times(ary, times)
        tmp = times.check_string_type
        
        return ary_join(ary, tmp) if tmp != Q_NIL

        len = times.value
        return RArray.from([]) if len.zero?
        raise ArgumentError, "negative argument" if len.negative?
        # TODO: check ARY_MAX_SIZE

        RArray.from(ary.array_value * len)
      end

      def ary_hash(ary)
        h = ary.array_value.reduce(1) do |result, element|
          result = 31 * result + Core.rb_funcall(element, :hash).value
        end
        RPrimitive.from(h)
      end

      def ary_diff(ary1, ary2)
        ary2 = ary2.to_array_type
        ary3 = RArray.from([])

        ary1.array_value.each do |elt|
          next if ary_includes_by_eql(ary2, elt)

          ary3.array_value.push(elt)
        end
        
        # TODO: use a hash for big arrays

        ary3
      end

      def ary_and(ary1, ary2)
        ary2 = ary2.to_array_type
        ary3 = RArray.from([])
        return ary3 if ary1.array_value.empty? || ary2.array_value.empty?

        ary1.array_value.each do |v|
          next if !ary_includes_by_eql(ary2, v)
          next if ary_includes_by_eql(ary3, v)
          ary3.array_value.push(v)
        end
        
        # TODO: use a hash for big arrays

        ary3
      end

      def ary_or(ary1, ary2)
        ary2 = ary2.to_array_type
        ary3 = RArray.from([])

        ary_union(ary3, ary1)
        ary_union(ary3, ary2)

        # TODO: use a hash for big arrays

        ary3
      end

      def ary_union(ary_union, ary)
        ary.array_value.each do |elt|
          next if ary_includes_by_eql(ary_union, elt)
          ary_union.array_value.push(elt)
        end
      end

      def ary_dup(ary)
        RArray.new(ary.class, [], ary.array_value)
      end

      def ary_make_hash(ary)
        hash = RHash.from({})
        ary.array_value.each do |elt|
          hash_aset(hash, elt, elt)
        end
        hash
      end

      def ary_make_hash_by(ary)
        hash = RHash.from({})
        ary.array_value.each do |v|
          k = rb_yield(v)
          hash_aset(hash, k, v)
        end
        hash
      end

      def ary_uniq_bang(ary)
        return Q_NIL if ary.len <= 1

        hash = if rb_block_given?
                 ary_make_hash_by(ary)
               else
                 ary_make_hash(ary)
               end
      
        hash_size = hash.size
        return Q_NIL if ary.len == hash_size
        
        ary.array_value.clear
        hash.entries.each do |ent|
          ary.array_value.push(ent.value)
        end

        ary
      end

      def ary_uniq(ary)
        if ary.len <= 1
          uniq = ary_dup(ary)
        elsif rb_block_given?
          hash = ary_make_hash_by(ary)
          uniq = hash_values(hash)
        else
          hash = ary_make_hash(ary)
          uniq = hash_values(hash)
        end
        uniq.klass = ary.klass

        uniq
      end

      def ary_compact_bang(ary)
        alen = ary.len
        ary.array_value.delete_if { |e| e == Q_NIL }
        return Q_NIL if alen == ary.len
        ary
      end

      def ary_compact(ary)
        ary = ary_dup(ary)
        ary_compact_bang(ary)
        ary
      end
    end

    def self.init_array
      @cArray = rb_define_class(:Array)

      rb_define_method(cArray, :inspect, &method(:ary_inspect))
      rb_alias_method(cArray, :to_s, :inspect)

      rb_define_method(cArray, :hash, &method(:ary_hash))

      rb_define_method(cArray, :[], &method(:ary_aref))
      rb_define_method(cArray, :[]=, &method(:ary_aset))
      rb_define_method(cArray, :pop, &method(:ary_pop))
      rb_define_method(cArray, :empty?, &method(:ary_empty_p))

      rb_define_method(cArray, :+, &method(:ary_plus))
      rb_define_method(cArray, :*, &method(:ary_times))
      
      rb_define_method(cArray, :-, &method(:ary_diff))
      rb_define_method(cArray, :&, &method(:ary_and))
      rb_define_method(cArray, :|, &method(:ary_or))

      rb_define_method(cArray, :uniq, &method(:ary_uniq))
      rb_define_method(cArray, :uniq!, &method(:ary_uniq_bang))
      rb_define_method(cArray, :compact, &method(:ary_compact))
      rb_define_method(cArray, :compact!, &method(:ary_compact_bang))
    end
  end
end
