require 'rubygems'

require 'benchmark'
require File.dirname(__FILE__) + "/../lib/monkey_shield"

def filename fn, code
  eval code, nil, fn
end

MonkeyShield.wrap_with_context :dog do
  filename 'dog.rb', %{
    class Animal
      def speak
        sleep 0.01
        :bark!
      end

      def blah
        sleep 0.01
        :blah!
      end
    end

    def speak_dog!
      Animal.new.speak
    end
  }
end

def do_blah!
  Animal.new.blah
end

MonkeyShield.wrap_with_context :cat do
  filename 'cat.rb', %{
    class Animal
      def speak
        :meow!
      end
    end

    def speak_cat!
      Animal.new.speak
    end
  }
end

MonkeyShield.context_switch_for Animal, :speak

class Animal
  def something_else
    sleep 0.01
    :something_else
  end
end

def do_something_else
  Animal.new.something_else
end

t1 = Benchmark.realtime { 100.times { speak_dog! } }
t2 = Benchmark.realtime { 100.times { do_blah! } }
tp = Benchmark.realtime { 100.times { do_something_else } }

class Symbol
  def to_proc
    lambda { |i| i.__send__ self }
  end
end

require 'ruby-prof'
prof = lambda do 
  result = RubyProf.profile do 
    100.times { speak_dog! }
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
