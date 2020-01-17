module GarnetRuby
  class RBasic
    attr_accessor :klass, :flags

    def initialize(klass, flags)
      @klass = klass
      @flags = flags
    end

    def to_s
      "<##{klass.name}>"
    end
    alias inspect to_s

    def type
      nil
    end

    def type?(_)
      false
    end

    def numeric?
      false
    end

    def discrete_object?
      return false if obj_is_kind_of(self, Core.cTime) == Q_TRUE # TODO: until Time#succ removed

      VM.instance.rb_respond_to(self, :succ)
    end

    def to_integer(mid)
      return self if Core.fixnum?(self)

      v = try_to_int(mid, true)
      conversion_mismatch('Integer', mid.to_s, v) unless fixnum?(v)
      v
    end

    def try_to_int(mid, should_raise)
      convert_type_with_id('Integer', mid, should_raise, -1)
    end

    def numeric_to_float
      unless Core.obj_is_kind_of(self, Core.cNumeric)
        rb_raise(eTypeError, "can't convert #{val.klass} into Float")
      end
      rb_convert_type_with_id(Float, 'Float', :to_f)
    end

    def num_to_dbl
      if Core.fixnum?(self)
        value.to_f
      elsif type?(Float)
        value
      else
        # TODO: Rational
        numeric_to_float.value
      end
    end

    def to_id
      return symbol_value if type?(Symbol)

      name = string_for_symbol
      name.string_value.to_sym
    end

    def to_symbol
      return self if type?(Symbol)

      name = string_for_symbol
      RSymbol.from(name.string_value.to_sym)
    end

    def string_for_symbol
      unless type?(String)
        tmp = check_string_type
        if tmp == Q_NIL
          Core.rb_raise(Core.eTypeError, "#{self} is not a symbol")
        end
        return tmp
      end
      self
    end

    def obj_as_string
      return self if type?(String)

      str = Core.rb_funcall(self, :to_s)
      str.obj_as_string_result(self)
    end

    def obj_as_string_result(obj)
      return obj.any_to_s unless type?(String)

      self
    end

    def any_to_s
      "<#{klass.name}:#{__id__}>"
    end

    def rb_string
      tmp = check_string_type
      if tmp == Q_NIL
        tmp = convert_type_with_id(String, 'String', :to_s)
      end
      tmp
    end

    def check_string_type
      rb_check_convert_type_with_id(String, 'String', :to_str)
    end

    def str_to_str
      rb_convert_type_with_id(String, 'String', :to_str)
    end

    def ary_to_ary
      tmp = check_array_type
      return tmp unless tmp == Q_NIL

      RArray.from([self])
    end

    def to_array_type
      rb_convert_type_with_id(Array, 'Array', :to_ary)
    end

    def check_array_type
      rb_check_convert_type_with_id(Array, 'Array', :to_ary)
    end

    def check_to_array
      rb_check_convert_type_with_id(Array, 'Array', :to_a)
    end

    def check_hash_type
      rb_check_convert_type_with_id(Hash, 'Hash', :to_hash)
    end

    def rb_check_convert_type_with_id(type, tname, method)
      return self if self.type == type
      v = convert_type_with_id(tname, method, false, -1)
      return Q_NIL if v == Q_NIL
      if v.type != type
        conversion_mismatch(tname, method, v)
      end
      v
    end

    def rb_convert_type_with_id(type, tname, method)
      return self if self.type == type
      v = convert_type_with_id(tname, method, true, -1)
      if v.type != type
        conversion_mismatch(tname, method, v)
      end
      v
    end

    def convert_type_with_id(tname, method, should_raise, index)
      r = VM.instance.rb_check_funcall(self, method)
      if r == Q_UNDEF
        if should_raise
          # TODO: fancier error message
          
          cname = case self
          when Q_NIL   then 'nil'
          when Q_TRUE  then 'true'
          when Q_FALSE then 'false'
          else self.klass
          end
          raise TypeError, "can't convert #{cname} into #{tname}"
        end
        return Q_NIL
      end
      r
    end

    def conversion_mismatch(tname, method, result)
      cname = self.klass
      raise TypeError, "can't convert #{cname} to #{tname} (#{cname}##{method} gives #{result.klass})"
    end
  end
end
