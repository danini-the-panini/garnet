module GarnetRuby
  class RRegexp < RObject
    attr_accessor :regexp_value

    def initialize(klass, flags, value)
      super(klass, flags)
      @regexp_value = value
    end

    def type
      Regexp
    end

    def type?(x)
      x == Regexp
    end

    def operand(s, check)
      if s.is_a?(RSymbol)
        s.sym2str
      elsif s.is_a?(RString)
        s
      else
        check ? s.str_to_str : s.check_string_type
      end
    end

    def match_pos(str)
      if str == Q_NIL
        Core.backref_set(Q_NIL)
        return -1
      end

      pos = regexp_value =~ operand(str, true).string_value
      Core.backref_set(RMatch.from($~))
      pos || -1
    end

    def match(str)
      pos = match_pos(str)
      return Q_NIL if pos.negative?

      RPrimitive.from(pos)
    end

    def self.from(value)
      return Q_NIL if value.nil?

      new(Core.cRegexp, [], value)
    end

    def self.from_string(str, options = nil)
      from(Regexp.new(str.string_value, options))
    end
  end

  class RMatch < RObject
    attr_reader :match_value

    def initialize(klass, flags, match_value)
      super(klass, flags)
      @match_value = match_value
    end

    def nth_match(nth)
      RString.from(match_value[nth])
    end

    def last_match
      nth_match(0)
    end

    def match_pre
      RString.from(match_value.pre_match)
    end

    def match_post
      RString.from(match_value.post_match)
    end

    def match_last
      nth_match(-1)
    end

    def check!
      raise 'uninitialized matchdata' if match_value.nil?
    end

    def self.from(value)
      return Q_NIL if value.nil?

      new(Core.cMatch, [], value)
    end
  end

  module Core
    class << self
      def regexp_alloc(klass)
        RRegexp.new(klass, [], nil)
      end

      def match_alloc(klass)
        RMatch.new(klass, [], nil)
      end

      def backref_set(value)
        VM.instance.special_variables[:backref] = value
      end

      def backref_get
        VM.instance.special_variables[:backref]
      end

      def reg_last_match(match)
        return Q_NIL if match == Q_NIL

        match.check!
        match.last_match
      end

      def reg_match_pre(match)
        return Q_NIL if match == Q_NIL

        match.check!
        match.match_pre
      end

      def reg_match_post(match)
        return Q_NIL if match == Q_NIL

        match.check!
        match.match_post
      end

      def reg_match_last(match)
        return Q_NIL if match == Q_NIL

        match.check!
        match.match_last
      end

      def reg_nth_match(nth, match)
        return Q_NIL if match == Q_NIL

        match.check!
        match.nth_match(nth)
      end

      def reg_s_quote(_, str)
        RString.from(Regexp.quote(str.obj_as_string.string_value))
      end

      def reg_initialize(slf, *args)
        # enc = nil
        if args[0].type?(Regexp)
          re = args[0]

          puts "WARNING: flags ignored" if args.length > 1

          flags = re.regexp_value.options
          str = re.regexp_value.source
        else
          if args.length >= 2
            if fixnum?(args[1])
              flags = args[1].value
            elsif rtest(args[1])
              flags = Regexp::IGNORECASE
            end
          end
          # TODO: third argument?
          str = args[0].string_value
        end

        # if enc && str.string_value.encoding != enc
          # TODO: enc is always nil
        # else

        slf.regexp_value = Regexp.new(str, flags)

        slf
      end

      def reg_match(re, *args)
        str = args[0]

        if args.length == 2
          pos = num2long(args[1])
        else
          pos = 0
        end

        m = re.regexp_value.match(re.operand(str, true).string_value, pos)
        if m.nil?
          Core.backref_set(Q_NIL)
          return Q_NIL
        end
        m = RMatch.from(m)
        Core.backref_set(m)
        if rb_block_given?
          rb_yield(m)
        end
        m
      end

      def reg_to_s(re)
        RString.from(re.regexp_value.to_s)
      end

      def reg_inspect(re)
        RString.from(re.regexp_value.inspect)
      end

      def reg_options(re)
        RPrimitive.from(re.regexp_value.options)
      end

      def reg_encoding(re)
        REncoding.from(re.regexp_value&.encoding || Encoding::BINARY)
      end

      def reg_fixed_encoding(re)
        re.regexp_value.fixed_encoding? ? Q_TRUE : Q_FALSE
      end
    end

    def self.init_regexp
      @cRegexp = rb_define_class(:Regexp, cObject)
      rb_define_alloc_func(cRegexp, &method(:regexp_alloc))
      rb_define_singleton_method(cRegexp, :quote, &method(:reg_s_quote))

      rb_define_method(cRegexp, :initialize, &method(:reg_initialize))
      rb_define_method(cRegexp, :=~) { |re, str| re.match(str) }
      rb_define_method(cRegexp, :===) { |re, str| rtest(re.match(str)) ? Q_TRUE : Q_FALSE }
      rb_define_method(cRegexp, :match, &method(:reg_match))
      rb_define_method(cRegexp, :to_s, &method(:reg_to_s))
      rb_define_method(cRegexp, :inspect, &method(:reg_inspect))
      rb_define_method(cRegexp, :options, &method(:reg_options))
      rb_define_method(cRegexp, :encoding, &method(:reg_encoding))
      rb_define_method(cRegexp, :fixed_encoding?, &method(:reg_fixed_encoding))

      @cMatch = rb_define_class(:MatchData, cObject)
      rb_define_alloc_func(cMatch, &method(:match_alloc))
    end
  end
end
