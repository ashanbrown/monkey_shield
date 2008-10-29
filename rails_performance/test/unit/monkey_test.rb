require File.dirname(__FILE__)+"/../../../lib/monkey_shield"

exceptions = [
  'ActiveSupport::CoreExtensions::LoadErrorExtensions::LoadErrorClassMethods#new',
  'ActiveSupport::Dependencies#new_constants_in',
  'ActiveSupport::Dependencies::Loadable#require',
  'MonitorMixin#initialize',
  'ActionController::Benchmarking::ClassMethods#benchmark',
  'ActionView::RenderablePartial#render',
  'ActiveRecord::AttributeMethods#respond_to?',
  'ActiveSupport::Dependencies::ClassConstMissing#const_missing',
  'ActiveRecord::AttributeMethods#method_missing',
#  :method_missing,
  :inherited
]

MonkeyShield.wrap_with_context :rails, exceptions, true do
  require File.dirname(__FILE__)+"/../test_helper"

  Monkey.delete_all
  m = Monkey.create :name => 'curious_george'
  m.name

  def monkey_name_in_rails
    Monkey.first.name
  end
end

MonkeyShield.wrap_with_context :test do
  class Monkey
    def name
      "tony"
    end
  end
 
  def monkey_name_in_test
    Monkey.first.name
  end
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
