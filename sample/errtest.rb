puts "-- begin"

def run
  yield
rescue TypeError
  puts "nope"
ensure
  puts "<run ensure>"
end

def foo
  run { raise "foo" }
  puts "no"
rescue TypeError
  puts "nope"
ensure
  puts "<foo ensure>"
end

begin
  puts "A"
  run { foo }
  puts "B"
rescue RuntimeError
  puts "yes"
ensure
  puts "<main ensure>"
end

puts "-- fin"
