require 'spec'
require File.dirname(__FILE__) + '/../lib/monkey_shield'

describe "MonkeyShield with some real libs" do
  MonkeyShield.wrap_with_context :rails, ['ActiveSupport::CoreExtensions::LoadErrorExtensions::LoadErrorClassMethods#new', 'ActiveSupport::Dependencies#new_constants_in', 'ActiveSupport::Dependencies::Loadable#require'] do
    require 'activesupport'  # defines String#each_char
    require 'activerecord'   # load just to see if we get any errors

    class String
      def sum
        sum = ""
        each_char {|c| sum += "#{c}+" }
        sum.sub(/\+$/,'')
      end
    end
  end

  MonkeyShield.wrap_with_context :hpricot do
    require 'hpricot'  # load just to see if we get any errors
  end

  MonkeyShield.wrap_with_context :my_libs do
    class String
      alias each_char each_byte

      def sum
        sum = 0
        each_char {|c| sum += c }
        sum
      end
    end
  end

  it "should work" do
    MonkeyShield.context_switch_for String, :sum
    MonkeyShield.context_switch_for String, :each_char
    MonkeyShield.set_default_context_for String, :each_char, :my_libs

    MonkeyShield.in_context(:my_libs) { "abc".sum }.should == 294
    MonkeyShield.in_context(:rails) { "abc".sum }.should == "a+b+c"
  end
end
