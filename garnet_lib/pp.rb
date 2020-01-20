# require 'prettyprint'

# TODO

module Kernel
  def pretty_inspect
    String(inspect)
  end

  def pp(*objs)
    objs.each do |obj|
      p obj
    end
    objs.size <= 1 ? objs.first : objs
  end
end
