require 'benchmark'
require File.dirname(__FILE__) + "/../lib/monkey_shield"

MonkeyShield.log = true
MonkeyShield.wrap_with_context :dog do
  class Animal
    def speak
      :bark!
      raise'wf'
    end

    def blah
      :blah!
    end
  end

  def speak_dog!
    Animal.new.speak
  end
end

def do_blah!
  Animal.new.blah
end

MonkeyShield.wrap_with_context :cat do
  class Animal
    def speak
      :meow!
    end
  end

  def speak_cat!
    Animal.new.speak
  end
end

MonkeyShield.context_switch_for Animal, :speak

class Animal
  def something_else
    :something_else
  end
end

def do_something_else
  Animal.new.something_else
end


def x
  :x
end


t1 = Benchmark.realtime { 100000.times { speak_dog! } }
t2 = Benchmark.realtime { 100000.times { do_blah! } }
tp = Benchmark.realtime { 100000.times { do_something_else } }

prof = lambda do 
  require 'ruby-prof'
  result = RubyProf.profile do 
    100000.times { speak_dog! }
  end
  printer = RubyProf::FlatPrinter.new(result)
  printer.print(STDOUT, 0)
end

prof.call

puts "context switched method"
p t1
puts "context wrapped method"
p t2
puts "plain method"
p tp
