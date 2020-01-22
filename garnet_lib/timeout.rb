module Timeout
  def self.timeout(*args)
    yield
  end
end

def timeout(*args, &block)
  Timeout.timeout(*args, &block)
end