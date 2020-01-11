module GarnetRuby
  class RRegexp < RObject
    attr_reader :regexp_value

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
      pos
    end

    def match(str)
      pos = match_pos(str)
      return Q_NIL if pos.nil?

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
    end

    def self.init_regexp
      @cRegexp = rb_define_class(:Regexp, cObject)
      rb_define_alloc_func(cRegexp, &method(:regexp_alloc))

      rb_define_method(cRegexp, :=~) { |re, str| re.match(str) }
      rb_define_method(cRegexp, :===) { |re, str| rtest(re.match(str)) ? Q_TRUE : Q_FALSE }
      rb_define_method(cRegexp, :match, &method(:reg_match))

      @cMatch = rb_define_class(:MatchData, cObject)
      rb_define_alloc_func(cMatch, &method(:match_alloc))
    end
  end
end
