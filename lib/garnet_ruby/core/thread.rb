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
    alias eql? ==

    def self.from(value)
      return Q_NIL if value.nil?

      raise "NOT A THREAD: #{value.inspect}" unless value.is_a?(Thread)

      new(Core.cThread, [], value)
    end

    def thr_initialize(*args)
      unless Core.rb_block_given?
        Core.rb_raise(Core.eThreadError, 'must be called with a block')
      end

      block = VM.instance.current_control_frame.block
      @t_proc = RProc.new(Core.cProc, [], block)
      @t_args = args

      self
    end

    def thr_join
      @t_value = Core.rb_funcall(@t_proc, :call, *@t_args)

      self
    end

    def thr_value
      thr_join
      @t_value
    end

    def thr_aref(key)
      id = Core.check_id(key)
      thread_value[id]
    end

    def thr_aset(key, value)
      id = Core.check_id(key)
      thread_value[id] = value
      value
    end
  end

  module Core
    class << self
      def thr_alloc(klass)
        RThread.new(klass, [], Thread.current)
      end

      def thr_s_current(_)
        RThread.from(Thread.current)
      end
    end

    def self.init_thread
      @cThread = rb_define_class(:Thread)
      rb_define_alloc_func(cThread, &method(:thr_alloc))

      rb_define_singleton_method(cThread, :current, &method(:thr_s_current))
      rb_define_method(cThread, :initialize, &:thr_initialize)
      rb_define_method(cThread, :join, &:thr_join)
      rb_define_method(cThread, :value, &:thr_value)
      rb_define_method(cThread, :[], &:thr_aref)
      rb_define_method(cThread, :[]=, &:thr_aset)
    end
  end
end
