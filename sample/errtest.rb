puts "-- begin"

def run(x)
  puts "run #{x}"
  yield
rescue TypeError
  puts "nope"
ensure
  puts "<run(#{x}) ensure>"
end

def foo
  run('f') { raise "foo" }
  puts "no"
rescue TypeError
  puts "nope"
ensure
  puts "<foo ensure>"
end

begin
  puts "A"
  run('m') { foo }
  puts "B"
rescue RuntimeError
  puts "yes"
ensure
  puts "<main ensure>"
end

puts "-- fin"
