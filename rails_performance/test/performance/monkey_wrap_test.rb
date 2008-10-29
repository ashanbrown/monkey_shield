require File.dirname(__FILE__) + "/../../../lib/monkey_shield"

exceptions = [
  'ActiveSupport::CoreExtensions::LoadErrorExtensions::LoadErrorClassMethods#new',
  'ActiveSupport::Dependencies#new_constants_in',
  'ActiveSupport::Dependencies::Loadable#require',
  'MonitorMixin#initialize',
  'ActionController::Benchmarking::ClassMethods#benchmark',
  'ActionView::RenderablePartial#render',
  'ActiveRecord::AttributeMethods#respond_to?',
#  :method_missing,
  :inherited
]

MonkeyShield.wrap_with_context :test, exceptions do
#begin

  require File.dirname(__FILE__)+'/../test_helper'
  require 'performance_test_help'

end

class MonkeyWrapTest < ActionController::PerformanceTest
  # Replace this with your real tests.
  def test_homepage
    10.times { get '/perf/do_work' }
  end
end
