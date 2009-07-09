require File.dirname(__FILE__)+"/../../../lib/monkey_shield"

def filename fn, code
  eval code, nil, fn
end

MonkeyShield.wrap_with_context :rails do
  require File.dirname(__FILE__)+"/../test_helper"

  filename 'rails_context.rb', %{
    Monkey.delete_all
    m = Monkey.create :name => 'curious_george'
    m.name

    def monkey_name_in_rails
      Monkey.first.name
    end
  }
end

MonkeyShield.wrap_with_context :test do
  filename 'test_context.rb', %{
    class Monkey
      def name
        "tony"
      end
    end
   
    def monkey_name_in_test
      Monkey.first.name
    end
  }
end

MonkeyShield.context_switch_for Monkey, :name

# test cases are already wrapped in a context, so we need this to be outside
begin
  Monkey.first.name
  raise "should raise NoContextError"
rescue MonkeyShield::NoContextError
end

class MonkeyUnit < Test::Unit::TestCase
  def test_context_switched_methods
    assert_equal 'curious_george', monkey_name_in_rails
    assert_equal 'tony', monkey_name_in_test
  end
end
