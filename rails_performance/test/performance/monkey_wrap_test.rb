require File.dirname(__FILE__) + "/../../../lib/monkey_shield"

puts "WITHOUT MonkeyShield"
pid = fork do
  require File.dirname(__FILE__)+'/../test_helper'
  require 'performance_test_help'

  class MonkeyWrapTest < ActionController::PerformanceTest
    def test_homepage
      10.times { get '/perf/do_work' }
    end
  end
end
Process.wait pid

puts "WITH MonkeyShield"
pid = fork do
  MonkeyShield.wrap_with_context :test do
    require File.dirname(__FILE__)+'/../test_helper'
    require 'performance_test_help'
  end

  class MonkeyWrapTest < ActionController::PerformanceTest
    def test_homepage
      10.times { get '/perf/do_work' }
    end
  end
end
Process.wait pid

