module GarnetRuby
  class RThread < RObject
    attr_accessor :thread_value

    def initialize(klass, flags, thread_value)
      super(klass, flags)
      @thread_value = thread_value
    end

    def type
      Thread
    end

    def type?(x)
      x == Thread
    end

    def ==(other)
      return false unless other.is_a?(RThread)
      thread_value == other.thread_value
    end
    alias :eql? :==

    def self.from(value)
      return Q_NIL if value.nil?

      raise "NOT A THREAD: #{value.inspect}" unless value.is_a?(Thread)

      new(Core.cThread, [], value)
    end

    def thread_aref(key)
      id = Core.check_id(key)
      thread_value[id]
    end

    def thread_aset(key, value)
      id = Core.check_id(key)
      thread_value[id] = value
      value
    end
  end

  module Core
    class << self
      def thread_s_current(_)
        RThread.from(Thread.current)
      end
    end

    def self.init_thread
      @cThread = rb_define_class(:Thread)

      rb_define_singleton_method(cThread, :current, &method(:thread_s_current))
      rb_define_method(cThread, :[], &:thread_aref)
      rb_define_method(cThread, :[]=, &:thread_aset)
    end
  end
end
