module GarnetRuby
  class RTime < RObject
    attr_accessor :time_value

    def type
      Time
    end

    def type?(x)
      x == Time
    end

    def initialize(klass, flags, time_value)
      super(klass, flags)
      @time_value = time_value
    end

    def self.from(value)
      return Q_NIL if val.nil?

      raise "NOT A TIME OBJECT: #{value}" unless value.is_a?(Time)

      new(Core.cTime, [], value)
    end
  end

  module Core
    class << self
      def time_alloc(klass)
        RTime.new(klass, [], nil)
      end

      def time_s_now(klass, *args)
        rb_class_new_instance(klass, *args)
      end

      def time_init_0(time)
        time.time_value = Time.now
        time
      end

      def time_init_1(time, *args)
        year, mon, mday, hour, min, sec, off = args

        year = year.rb_to_int
        mon = mon&.rb_to_int
        mday = mday&.rb_to_int
        hour = hour&.rb_to_int
        min = min&.rb_to_int
        sec = sec&.rb_to_int
        unless offset.nil?
          offset = offset.type?(Symbol) ? offset.symbol_value : offset.string_value
        end

        time.time_value = Time.new(year, mon, mday, hour, min, sec, offset)
        time
      end

      def time_init(time, *args)
        return time_init_0(time) if args.empty?
        time_init_1(time, *args)
      end

      def time_add(torig, offset, sign)
        RTime.from(torig.time_value + (sign * num2long(offset)))
      end

      def time_plus(time1, time2)
        rb_raise(eTypeError, 'time + time?') if time2.type?(Time)
        
        time_add(time1, time2, 1)
      end

      def time_minus(time1, time2)
        if time2.type?(Time)
          return RPrimitive.from(time1.time_value - time2.time_value)
        end

        time_add(time1, time2, -1)
      end
    end

    def self.init_time
      @cTime = rb_define_class(:Time, cObject)
      cTime.include_module(mComparable)

      rb_define_alloc_func(cTime, &method(:time_alloc))
      rb_define_singleton_method(cTime, :now, &method(:time_s_now))
      rb_define_singleton_method(cTime, :at, &method(:TODO_not_implemented))
      rb_define_singleton_method(cTime, :utc, &method(:TODO_not_implemented))
      rb_define_singleton_method(cTime, :gm, &method(:TODO_not_implemented))
      rb_define_singleton_method(cTime, :local, &method(:TODO_not_implemented))
      rb_define_singleton_method(cTime, :mktime, &method(:TODO_not_implemented))

      rb_define_method(cTime, :to_i, &method(:TODO_not_implemented))
      rb_define_method(cTime, :to_f, &method(:TODO_not_implemented))
      rb_define_method(cTime, :to_r, &method(:TODO_not_implemented))
      rb_define_method(cTime, :<=>, &method(:TODO_not_implemented))
      rb_define_method(cTime, :eql?, &method(:TODO_not_implemented))
      rb_define_method(cTime, :hash, &method(:TODO_not_implemented))
      rb_define_method(cTime, :initialize, &method(:time_init))
      rb_define_method(cTime, :initialize_copy, &method(:TODO_not_implemented))

      rb_define_method(cTime, :localtime, &method(:TODO_not_implemented))
      rb_define_method(cTime, :gmtime, &method(:TODO_not_implemented))
      rb_define_method(cTime, :utc, &method(:TODO_not_implemented))
      rb_define_method(cTime, :getlocal, &method(:TODO_not_implemented))
      rb_define_method(cTime, :getgm, &method(:TODO_not_implemented))
      rb_define_method(cTime, :getutc, &method(:TODO_not_implemented))

      rb_define_method(cTime, :ctime, &method(:TODO_not_implemented))
      rb_define_method(cTime, :asctime, &method(:TODO_not_implemented))
      rb_define_method(cTime, :to_s, &method(:TODO_not_implemented))
      rb_define_method(cTime, :inspect, &method(:TODO_not_implemented))
      rb_define_method(cTime, :to_a, &method(:TODO_not_implemented))

      rb_define_method(cTime, :+, &method(:time_plus))
      rb_define_method(cTime, :-, &method(:time_minus))

      rb_define_method(cTime, :succ, &method(:TODO_not_implemented))
      rb_define_method(cTime, :round, &method(:TODO_not_implemented))
      rb_define_method(cTime, :floor, &method(:TODO_not_implemented))
      rb_define_method(cTime, :ceil, &method(:TODO_not_implemented))

      rb_define_method(cTime, :sec, &method(:TODO_not_implemented))
      rb_define_method(cTime, :min, &method(:TODO_not_implemented))
      rb_define_method(cTime, :hour, &method(:TODO_not_implemented))
      rb_define_method(cTime, :mday, &method(:TODO_not_implemented))
      rb_define_method(cTime, :day, &method(:TODO_not_implemented))
      rb_define_method(cTime, :mon, &method(:TODO_not_implemented))
      rb_define_method(cTime, :month, &method(:TODO_not_implemented))
      rb_define_method(cTime, :year, &method(:TODO_not_implemented))
      rb_define_method(cTime, :wday, &method(:TODO_not_implemented))
      rb_define_method(cTime, :yday, &method(:TODO_not_implemented))
      rb_define_method(cTime, :isdst, &method(:TODO_not_implemented))
      rb_define_method(cTime, :dst?, &method(:TODO_not_implemented))
      rb_define_method(cTime, :zone, &method(:TODO_not_implemented))
      rb_define_method(cTime, :gmtoff, &method(:TODO_not_implemented))
      rb_define_method(cTime, :gmt_offset, &method(:TODO_not_implemented))
      rb_define_method(cTime, :utc_offset, &method(:TODO_not_implemented))

      rb_define_method(cTime, :utc?, &method(:TODO_not_implemented))
      rb_define_method(cTime, :gmt?, &method(:TODO_not_implemented))

      rb_define_method(cTime, :sunday?, &method(:TODO_not_implemented))
      rb_define_method(cTime, :monday?, &method(:TODO_not_implemented))
      rb_define_method(cTime, :tuesday?, &method(:TODO_not_implemented))
      rb_define_method(cTime, :wednesday?, &method(:TODO_not_implemented))
      rb_define_method(cTime, :thursday?, &method(:TODO_not_implemented))
      rb_define_method(cTime, :friday?, &method(:TODO_not_implemented))
      rb_define_method(cTime, :saturday?, &method(:TODO_not_implemented))

      rb_define_method(cTime, :tv_sec, &method(:TODO_not_implemented))
      rb_define_method(cTime, :tv_usec, &method(:TODO_not_implemented))
      rb_define_method(cTime, :usec, &method(:TODO_not_implemented))
      rb_define_method(cTime, :tv_nsec, &method(:TODO_not_implemented))
      rb_define_method(cTime, :nsec, &method(:TODO_not_implemented))
      rb_define_method(cTime, :subsec, &method(:TODO_not_implemented))

      rb_define_method(cTime, :strftime, &method(:TODO_not_implemented))

      rb_define_private_method(cTime, :_dump, &method(:TODO_not_implemented))
      rb_define_private_method(singleton_class_of(cTime), :_load, &method(:TODO_not_implemented))
    end
  end
end