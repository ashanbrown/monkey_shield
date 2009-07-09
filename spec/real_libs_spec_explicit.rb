require 'rubygems'
require 'spec'
require File.dirname(__FILE__) + '/../lib/monkey_shield'

describe "MonkeyShield with some real libs" do
#  MonkeyShield.wrap_with_context :rails, ['ActiveSupport::CoreExtensions::LoadErrorExtensions::LoadErrorClassMethods#new', 'ActiveSupport::Dependencies#new_constants_in', 'ActiveSupport::Dependencies::Loadable#require'] do
  MonkeyShield.wrap_with_context :rails, [] do
    require 'activesupport'  # defines String#each_char
    require 'activerecord'   # load just to see if we get any errors

    String.class_eval <<-EOF, 'rails_context'
      def sum
        sum = ""
        each_char {|c| sum += "\#{c}+" }
        sum.sub(/\\+$/,'')
      end
    EOF

    Object.class_eval <<-EOF, 'rails_test'
      def rails_sum
        "abc".sum
      end
    EOF
  end

  MonkeyShield.wrap_with_context :hpricot do
    require 'hpricot'  # load just to see if we get any errors
  end

  MonkeyShield.wrap_with_context :my_libs do
    String.class_eval <<-EOF, 'my_libs'
      alias each_char each_byte

      def sum
        sum = 0
        each_char {|c| sum += c }
        sum
      end
    EOF

    Object.class_eval <<-EOF, 'my_libs_test'
      def my_libs_sum
        "abc".sum
      end
    EOF
  end

  it "should work" do
    MonkeyShield.context_switch_for String, :sum
    MonkeyShield.context_switch_for String, :each_char
    MonkeyShield.set_default_context_for String, :each_char, :my_libs

    my_libs_sum.should == 294
    rails_sum.should == "a+b+c"
  end
end
