# DHH::Deadline: a monotonic time budget, made only through Deadline.after.

require_relative 'test_helper'

deadline = DHH::Deadline.after(10)
assert(deadline.remaining.between?(9, 10) && !deadline.expired?, 'a fresh deadline has its budget left')
assert(DHH::Deadline.after(0).expired? && DHH::Deadline.after(-1).remaining.negative?, 'a spent deadline is expired')
begin
  DHH::Deadline.new(1)
  raise 'FAIL: Deadline.new is public'
rescue NoMethodError
  # expected: Deadline.after is the one constructor
end

puts 'test_deadline.rb: all assertions passed'
