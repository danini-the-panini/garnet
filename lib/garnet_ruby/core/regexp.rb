module GarnetRuby
  class RRegexp < RObject
    attr_reader :regexp_value

    def initialize(klass, flags, value)
      super(klass, flags)
      @regexp_value = value
    end

    def operand(s, check)
      if s.is_a?(RSymbol)
        s.sym2str
      elsif s.is_a?(RString)
        s
      else
        # TODO
      end
    end

    def match_pos(str)
      if str == Q_NIL
        Core.backref_set(Q_NIL)
        return -1, str
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
      def backref_set(value)
        VM.instance.special_variables[:backref] = value
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
    end

    def self.init_regexp
      @cRegexp = rb_define_class(:Regexp, cObject)

      rb_define_method(cRegexp, :=~) { |re, str| re.match(str) }
      rb_define_method(cRegexp, :===) { |re, str| rtest(re.match(str)) ? Q_TRUE : Q_FALSE }

      @cMatch = rb_define_class(:MatchData, cObject)
    end
  end
end
