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
      def empty_ary_alloc(klass)
        RArray.new(klass, [], [])
      end

      def ary_initialize(ary, *args)
        if args.empty?
          puts "WARNING: given block not used" if rb_block_given?
          return ary
        end
        size, val = *args
        if args.length == 1 && !fixnum?(args[0])
          val = args[0].check_array_type
          if val != Q_NIL
            ary_replace(ary, val)
            return ary
          end
        end

        len = num2long(size)
        rb_raise(eArgError, 'negative array size') if len.negative?

        if rb_block_given?
          if args.length == 2
            puts "WARNING: block supersedes default value argument"
          end
          len.times do |i|
            ary.array_value[i] = rb_yield(RPrimitive.from(i))
          end
        else
          ary_mem_fill(ary, 0, len, val)
        end
        ary
      end

      def ary_inspect(ary)
        strings = ary.array_value.map do |item|
          rb_funcall(item, :inspect).string_value
        end
        RString.from("[#{strings.join(', ')}]")
      end

      def ary_to_h(ary)
        hash = RHash.from({})
        block_given = rb_block_given?

        ary.array_value.each_with_index do |e, i|
          elt = block_given ? rb_yield(e) : e
          key_value_pair = elt.check_array_type
          if key_value_pair == Q_NIL
            rb_raise(eTypeError, "wrong element type #{elt.klass.name} at #{i} (expected array)")
          end
          if key_value_pair.len != 2
            rb_raise(eArgError, "wrong array length at #{i} (expected 2, was #{key_value_pair.len})")
          end
          hash_aset(hash, key_value_pair.array_value[0], key_value_pair.array_value[1])
        end
        hash
      end

      def ary_check_equality(ary1, ary2, &block)
        return Q_TRUE if ary1 == ary2
        ary2 = ary2.check_to_array
        return Q_FALSE if ary2 == Q_NIL
        return Q_FALSE if ary1.len != ary2.len
        result = ary1.array_value.zip(ary2.array_value).all?(&block)
        result ? Q_TRUE : Q_FALSE
      end

      def ary_equal(ary1, ary2)
        ary_check_equality(ary1, ary2) do |elt1, elt2|
          rtest(rb_equal(elt1, elt2))
        end
      end
      
      def ary_eql(ary1, ary2)
        ary_check_equality(ary1, ary2) do |elt1, elt2|
          rtest(rb_eql(elt1, elt2))
        end
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

      def ary_splice(ary, beg, len, replacement)
        rb_raise(eIndexError, "negative length (#{len})") if len.negative?
        olen = ary.len
        if beg.negative?
          beg += olen
          if beg.negative?
            rb_raise(eIndexError, "index #{beg - olen} too small for array; minimum: #{-olen}")
          end
        end

        if beg >= olen
          ary_mem_clear(ary, olen, beg - olen)
        end

        ary.array_value[beg, len] = replacement.array_value
      end

      def ary_mem_clear(ary, beg, size)
        size.times do |i|
          ary.array_value[beg + i] = Q_NIL
        end
      end

      def ary_mem_fill(ary, beg, size, val)
        size.times do |i|
          ary.array_value[beg + i] = val
        end
      end

      def ary_store(ary, idx, val)
        len = ary.len

        if idx.negative?
          idx += len
          if idx.negative?
            rb_raise(eIndexError, "index #{idx - len} too small for array; minimum #{-len}")
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

        result, beg, len = range_beg_len(args[0], ary.len, 1)
        if rtest(result)
          ary_splice(ary, beg, len, args.last.ary_to_ary)
          return args.last
        end

        ary_store(ary, num2long(args[0]), args[1])
        args[1]
      end

      def ary_first(ary, *args)
        if args.empty?
          ary.array_value.first || Q_NIL
        else
          n = num2long(args.first)
          RArray.from(ary.array_value.first(n))
        end
      end

      def ary_last(ary, *args)
        if args.empty?
          ary.array_value.last || Q_NIL
        else
          n = num2long(args.first)
          RArray.from(ary.array_value.last(n))
        end
      end

      def ary_includes(ary, item)
        ary.array_value.any? { |e| rtest(rb_equal(item, e)) } ? Q_TRUE : Q_FALSE
      end

      def ary_includes_by_eql(ary, item)
        ary.array_value.any? { |e| rtest(rb_eql(item, e)) } ? Q_TRUE : Q_FALSE
      end

      def ary_join(ary, sep = nil)
        return RString.from("") if ary.len.zero?

        sep ||= VM.instance.get_global(:'$,')

        if sep != Q_NIL
          sep = sep.str_to_str
        else
          sep = RString.from('')
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

      def ary_reverse_bang(ary)
        ptr = ary.array_value
        (ary.len / 2).times do |i|
          ptr[i], ptr[-i - 1] = ptr[-i - 1], ptr[i]
        end
        ary
      end

      def ary_reverse(ary)
        new_ary = []
        ary.array_value.reverse_each do |elt|
          new_ary.push(elt)
        end
        
        RArray.new(ary.klass, [], new_ary)
      end

      def ary_append(x, y)
        x.array_value[x.len, 0] = y.array_value
        x
      end

      def ary_concat(x, y)
        ary_append(x, y.to_array_type)
      end

      def ary_concat_multi(ary, *argv)
        if argv.length == 1
          ary_concat(ary, argv[0])
        elsif argv.length > 1
          args = RArray.from([])
          argv.each do |arg|
            ary_concat(args, arg)
          end
          ary_append(ary, args)
        end

        ary
      end

      def ary_push(ary, item)
        ary.array_value << item
        ary
      end

      def ary_cat(ary, *args)
        ary.array_value.concat(args)
        ary
      end

      def ary_pop(ary)
        ary.array_value.pop || Q_NIL
      end

      def ary_shift(ary, *args)
        return ary.array_value.shift if args.empty?

        n = num2long(args.first)
        RArray.from(ary.array_value.shift(n))
      end

      def ary_unshift(ary, *args)
        if args.empty?
          return ary
        end

        ary.array_value.unshift(*args)
        ary
      end

      def ary_shift(ary)
        ary.array_value.shift || Q_NIL
      end

      ARRAY_ENUM_LENGTH = -> (ary, args, eobj) { ary_length(ary) }

      def ary_each(ary)
        unless rb_block_given?
          return sized_enumerator(ary, [], ARRAY_ENUM_LENGTH)
        end
        ary.array_value.each do |elt|
          rb_yield(elt)
        end
        ary
      end

      def ary_reverse_each(ary)
        unless rb_block_given?
          return sized_enumerator(ary, [], ARRAY_ENUM_LENGTH)
        end
        ary.array_value.reverse_each do |elt|
          rb_yield(elt)
        end
        ary
      end

      def ary_length(ary)
        RPrimitive.from(ary.len)
      end

      def ary_empty_p(ary)
        ary.array_value.empty? ? Q_TRUE : Q_FALSE
      end

      def ary_sort_bang(ary)
        if ary.len > 1
          if rb_block_given?
            ary.array_value.sort! do |a, b|
              rb_cmpint(rb_yield(a, b), a, b)
            end
          else
            ary.array_value.sort! do |a, b|
              rb_cmpint(rb_funcall(a, :<=>, b), a, b)
            end
          end
        end
        ary
      end

      def ary_sort(ary)
        ary = ary_dup(ary)
        ary_sort_bang(ary)
        ary
      end

      def ary_collect(ary)
        unless rb_block_given?
          return sized_enumerator(ary, [], ARRAY_ENUM_LENGTH)
        end
        collect = RArray.from([])
        i = 0
        loop do
          break if i >= ary.len

          ary_push(collect, rb_yield(ary.array_value[i]))
          i += 1
        end
        collect
      end

      def ary_collect_bang(ary)
        unless rb_block_given?
          return sized_enumerator(ary, [], ARRAY_ENUM_LENGTH)
        end
        i = 0
        loop do
          break if i >= ary.len

          ary.array_value[i] = rb_yield(ary.array_value[i])
          i += 1
        end
        ary
      end

      def ary_select(ary)
        unless rb_block_given?
          return sized_enumerator(ary, [], ARRAY_ENUM_LENGTH)
        end

        result = RArray.from([])
        ary.array_value.each do |elt|
          ary_push(result, elt) if rtest(rb_yield(elt))
        end
        result
      end

      def ary_select_bang(ary)
        unless rb_block_given?
          return sized_enumerator(ary, [], ARRAY_ENUM_LENGTH)
        end

        result = ary.array_value.select! do |elt|
          rtest(rb_yield(elt))
        end
        result.nil? ? Q_NIL : ary
      end


      def ary_delete_if(ary)
        unless rb_block_given?
          return sized_enumerator(ary, [], ARRAY_ENUM_LENGTH)
        end
        ary_reject_bang(ary)
      end

      def ary_reject_bang(ary)
        unless rb_block_given?
          return sized_enumerator(ary, [], ARRAY_ENUM_LENGTH)
        end
        ret = ary.array_value.reject! do |v|
          rtest(rb_yield(v))
        end
        return Q_NIL if ret.nil?

        ary
      end

      def ary_transpose(ary)
        elen = -1
        result = nil

        alen = ary.len
        return ary_dup(ary) if alen.zero?

        alen.times do |i|
          tmp = ary.array_value[i].to_array_type
          if elen.negative?
            elen = tmp.len
            result = RArray.from([])
            elen.times do |j|
              result.array_value[j] = RArray.from([])
            end
          elsif elen != tmp.len
            rb_raise(eIndexError, "element size differs (#{tmp.len} should be #{elen})")
          end
          elen.times do |j|
            result.array_value[j].array_value[i] = tmp.array_value[j]
          end
        end
        result
      end

      def ary_replace(copy, orig)
        copy.array_value.replace(orig.array_value.dup)
        copy
      end

      def ary_clear(ary)
        ary.array_value.clear
        ary
      end

      def ary_fill(ary, *args)
        item = Q_UNDEF
        beg = 0
        len = 0

        not_range = false
        if rb_block_given?
          arg1, arg2 = args
          args << Q_UNDEF # hackish
        else
          item, arg1, arg2 = args
        end
        arg1 ||= Q_NIL
        arg2 ||= Q_NIL
        case args.length
        when 1
          beg = 0
          len = ary.len
        when 2
          r, beg, len = range_beg_len(arg1, ary.len, 1)
          not_range = true unless r == Q_TRUE
        when 3
          not_range = true
        end
        if not_range
          beg = arg1 == Q_NIL ? 0 : num2long(arg1)
          if beg.negative?
            beg = ary.len + beg
            beg = 0 if beg.negative?
          end
          len = arg2 == Q_NIL ? ary.len - beg : num2long(arg2)
        end
        return ary if len.negative?

        ed = beg + len
        ary_mem_clear(ary, ary.len, ed - ary.len) if ary.len < ed

        if item == Q_UNDEF
          (beg...ed).each do |i|
            v = rb_yield(RPrimitive.from(i))
            break if i >= ary.len

            ary.array_value[i] = v
          end
        else
          ary_mem_fill(ary, beg, len, item)
        end

        ary
      end

      def ary_cmp(ary1, ary2)
        ary2 = ary2.check_array_type
        return Q_NIL if ary2 == Q_NIL
        return RPrimitive.from(0) if ary1 == ary2

        len = ary1.len
        len = ary2.len if len > ary2.len
        len.times do |i|
          e1 = ary1.array_value[i]
          e2 = ary2.array_value[i]
          v = rb_funcall(e1, :<=>, e2)
          return v unless v == RPrimitive.from(0)
        end
        len = ary1.len - ary2.len
        return RPrimitive.from(0) if len.zero?
        return RPrimitive.from(1) if len > 0
        RPrimitive.from(-1)
      end

      def ary_plus(x, y)
        RArray.from(x.array_value + y.to_array_type.array_value)
      end

      def ary_times(ary, times)
        tmp = times.check_string_type

        return ary_join(ary, tmp) if tmp != Q_NIL

        len = times.value
        return RArray.from([]) if len.zero?
        rb_raise(eArgError, "negative argument") if len.negative?
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
          next if rtest(ary_includes_by_eql(ary2, elt))

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
          next unless rtest(ary_includes_by_eql(ary2, v))
          next if rtest(ary_includes_by_eql(ary3, v))

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

      def ary_max(ary, *args)
        result = Q_UNDEF

        # TODO: max(N)

        if rb_block_given?
          ary.array_value.each do |v|
            if result == Q_UNDEF || rb_cmpint(rb_yield(v, result), v, result) > 0
              result = v
            end
          end
        else
          ary.array_value.each do |v|
            if result == Q_UNDEF || rb_cmpint(rb_funcall(v, :<=>, result), v, result) > 0
              result = v
            end
          end
        end

        return Q_NIL if result == Q_UNDEF

        result
      end

      def ary_min(ary, *args)
        result = Q_UNDEF

        # TODO: max(N)

        if rb_block_given?
          ary.array_value.each do |v|
            if result == Q_UNDEF || rb_cmpint(rb_yield(v, result), v, result) < 0
              result = v
            end
          end
        else
          ary.array_value.each do |v|
            if result == Q_UNDEF || rb_cmpint(rb_funcall(v, :<=>, result), v, result) < 0
              result = v
            end
          end
        end

        return Q_NIL if result == Q_UNDEF

        result
      end

      def ary_union(ary_union, ary)
        ary.array_value.each do |elt|
          next if rtest(ary_includes_by_eql(ary_union, elt))

          ary_union.array_value.push(elt)
        end
      end

      def ary_dup(ary)
        RArray.new(ary.klass, [], ary.array_value)
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

      def flatten_array(ary, level)
        tmp = nil
        i = ary.array_value.find_index do |elt|
          rtest(tmp = elt.check_array_type)
        end

        return ary if i.nil? # already flat
        rb_raise(eArgError, 'tried to flatten recursive array') if tmp == ary

        result = RArray.new(nil, [], ary.array_value[0, i])

        stack = [ary, i + 1]

        memo = RHash.from({})
        hash_aset(memo, ary, Q_TRUE)
        hash_aset(memo, tmp, Q_TRUE)

        ary = tmp
        i = 0

        loop do
          while i < ary.len
            elt = ary.array_value[i]
            i += 1
            if level >= 0 && stack.length / 2 >= level
              ary_push(result, elt)
              next
            end
            tmp = elt.check_array_type
            if result.klass
              rb_raise(eRuntimeError, 'flatten reentered')
            end
            if tmp == Q_NIL
              ary_push(result, elt)
            else
              if rtest(hash_has_key(memo, tmp))
                rb_raise(eArgError, 'tried to flatten recursive array')
              end
              hash_aset(memo, tmp, Q_TRUE)
              stack << ary
              stack << i
              ary = tmp
              i = 0
            end
          end

          break if stack.empty?

          hash_delete_entry(memo, ary)
          ary, i = stack.pop(2)
        end

        result.klass = ary.klass.real
        result
      end

      def ary_flatten(ary, *args)
        level = -1

        unless args.empty? || args[0] == Q_NIL
          level = num2long(args[0])
          return ary_dup(ary) if level.zero?
        end

        result = flatten_array(ary, level)
        return ary_dup(ary) if result == ary

        result
      end

      def ary_flatten_bang(ary, *args)
      end

      def ary_any(ary, *args)
        return Q_FALSE if ary.len.zero?

        if args.length > 0
          puts 'WARNING: given block not used' if rb_block_given?

          ary.array_value.each do |elt|
            return Q_TRUE if rtest(rb_funcall(args.first, :===, elt))
          end
        elsif !rb_block_given?
          ary.array_value.each do |elt|
            return Q_TRUE if rtest(elt)
          end
        else
          ary.array_value.each do |elt|
            return Q_TRUE if rtest(rb_yield(elt))
          end
        end

        Q_FALSE
      end

      def ary_all(ary, *args)
        return Q_TRUE if ary.len.zero?

        if args.length > 0
          puts 'WARNING: given block not used' if rb_block_given?

          ary.array_value.each do |elt|
            return Q_FALSE unless rtest(rb_funcall(args.first, :===, elt))
          end
        elsif !rb_block_given?
          ary.array_value.each do |elt|
            return Q_FALSE unless rtest(elt)
          end
        else
          ary.array_value.each do |elt|
            return Q_FALSE unless rtest(rb_yield(elt))
          end
        end

        Q_TRUE
      end

      def ary_none(ary, *args)
        return Q_TRUE if ary.len.zero?

        if args.length > 0
          puts 'WARNING: given block not used' if rb_block_given?

          ary.array_value.each do |elt|
            return Q_FALSE if rtest(rb_funcall(args.first, :===, elt))
          end
        elsif !rb_block_given?
          ary.array_value.each do |elt|
            return Q_FALSE if rtest(elt)
          end
        else
          ary.array_value.each do |elt|
            return Q_FALSE if rtest(rb_yield(elt))
          end
        end

        Q_TRUE
      end

      def ary_one(ary, *args)
        return Q_FALSE if args.length.zero?

        result = false
        if args.length > 0
          puts 'WARNING: given block not used' if rb_block_given?

          ary.array_value.each do |elt|
            if rtest(rb_funcall(args.first, :===, elt))
              return Q_FALSE if result
              result = true
            end
          end
        elsif !rb_block_given?
          ary.array_value.each do |elt|
            if rtest(elt)
              return Q_FALSE if result
              result = true
            end
          end
        else
          ary.array_value.each do |elt|
            if rtest(rb_yield(elt))
              return Q_FALSE if result
              result = true
            end
          end
        end

        result ? Q_TRUE : Q_FALSE
      end

      def ary_pack(ary, fmt)
        # TODO: build this properly

        rb_ary = ary.array_value.map do |v|
          case v
          when RString
            v.string_value
          when RPrimitive
            v.value
          else
            raise "ARY PACK CAN ONLY DO STRINGS AND NUMBERS RIGHT NOW"
          end
        end

        RString.from(rb_ary.pack(fmt.obj_as_string.string_value))
      end
    end

    def self.init_array
      @cArray = rb_define_class(:Array)
      cArray.include_module(mEnumerable)

      rb_define_alloc_func(cArray, &method(:empty_ary_alloc))
      rb_define_method(cArray, :initialize, &method(:ary_initialize))
      rb_define_method(cArray, :initialize_copy, &method(:ary_replace))

      rb_define_method(cArray, :inspect, &method(:ary_inspect))
      rb_alias_method(cArray, :to_s, :inspect)
      rb_define_method(cArray, :to_h, &method(:ary_to_h))

      rb_define_method(cArray, :==, &method(:ary_equal))
      rb_define_method(cArray, :eql?, &method(:ary_eql))
      rb_define_method(cArray, :hash, &method(:ary_hash))

      rb_define_method(cArray, :[], &method(:ary_aref))
      rb_define_method(cArray, :[]=, &method(:ary_aset))
      rb_define_method(cArray, :first, &method(:ary_first))
      rb_define_method(cArray, :last, &method(:ary_last))
      rb_define_method(cArray, :concat, &method(:ary_concat_multi))
      rb_define_method(cArray, :<<, &method(:ary_push))
      rb_define_method(cArray, :push, &method(:ary_cat))
      rb_alias_method(cArray, :append, :push)
      rb_define_method(cArray, :pop, &method(:ary_pop))
      rb_define_method(cArray, :shift, &method(:ary_shift))
      rb_define_method(cArray, :unshift, &method(:ary_unshift))
      rb_define_method(cArray, :each, &method(:ary_each))
      rb_define_method(cArray, :reverse_each, &method(:ary_reverse_each))
      rb_define_method(cArray, :length, &method(:ary_length))
      rb_alias_method(cArray, :size, :length)
      rb_define_method(cArray, :empty?, &method(:ary_empty_p))
      rb_define_method(cArray, :join, &method(:ary_join))
      rb_define_method(cArray, :reverse, &method(:ary_reverse))
      rb_define_method(cArray, :reverse!, &method(:ary_reverse_bang))
      rb_define_method(cArray, :sort, &method(:ary_sort))
      rb_define_method(cArray, :sort!, &method(:ary_sort_bang))
      rb_define_method(cArray, :collect, &method(:ary_collect))
      rb_define_method(cArray, :collect!, &method(:ary_collect_bang))
      rb_define_method(cArray, :map, &method(:ary_collect))
      rb_define_method(cArray, :map!, &method(:ary_collect_bang))
      rb_define_method(cArray, :select, &method(:ary_select))
      rb_define_method(cArray, :select!, &method(:ary_select_bang))
      rb_define_method(cArray, :filter, &method(:ary_select))
      rb_define_method(cArray, :filter!, &method(:ary_select_bang))
      rb_define_method(cArray, :delete_if, &method(:ary_delete_if))
      rb_define_method(cArray, :reject!, &method(:ary_reject_bang))
      rb_define_method(cArray, :transpose, &method(:ary_transpose))
      rb_define_method(cArray, :replace, &method(:ary_replace))
      rb_define_method(cArray, :clear, &method(:ary_clear))
      rb_define_method(cArray, :fill, &method(:ary_fill))
      rb_define_method(cArray, :include?, &method(:ary_includes))
      rb_define_method(cArray, :<=>, &method(:ary_cmp))

      rb_define_method(cArray, :+, &method(:ary_plus))
      rb_define_method(cArray, :*, &method(:ary_times))

      rb_define_method(cArray, :-, &method(:ary_diff))
      rb_define_method(cArray, :&, &method(:ary_and))
      rb_define_method(cArray, :|, &method(:ary_or))

      rb_define_method(cArray, :max, &method(:ary_max))
      rb_define_method(cArray, :min, &method(:ary_min))

      rb_define_method(cArray, :uniq, &method(:ary_uniq))
      rb_define_method(cArray, :uniq!, &method(:ary_uniq_bang))
      rb_define_method(cArray, :compact, &method(:ary_compact))
      rb_define_method(cArray, :compact!, &method(:ary_compact_bang))
      rb_define_method(cArray, :flatten, &method(:ary_flatten))
      rb_define_method(cArray, :flatten!, &method(:ary_flatten_bang))

      rb_define_method(cArray, :any?, &method(:ary_any))
      rb_define_method(cArray, :all?, &method(:ary_all))
      rb_define_method(cArray, :none?, &method(:ary_none))
      rb_define_method(cArray, :one?, &method(:ary_one))

      rb_define_method(cArray, :pack, &method(:ary_pack))
    end
  end
end
