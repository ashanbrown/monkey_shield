require 'rubygems'
require 'spec'
require 'pp'
require File.dirname(__FILE__) + '/../lib/monkey_shield'

$GLOBAL_SCOPE_BINDING = binding

describe MonkeyShield do
  def get_klasses
    klasses = []; ObjectSpace.each_object(Module) {|k| klasses << k }; klasses
  end

  before do
    MonkeyShield.reset!
    @current_klasses = get_klasses
  end

  after do
    (get_klasses - @current_klasses).each {|k| Object.send :remove_const, k.name }
  end

  it "should automatically detect which methods to context switch" do
    MonkeyShield.wrap_with_context :test1 do
      class X
        def x
          :x1
        end
      end

      module Kernel
        def test1
          X.new.x
        end
      end
    end

    MonkeyShield.wrap_with_context :test2 do
      class X
        def x
          :x2
        end
      end

      module Kernel
        def test2
          X.new.x
        end
      end
    end

    proc { X.new.x }.should raise_error(MonkeyShield::NoContextError)

    test1.should == :x1
    test2.should == :x2
  end

  it "auto context switching more than two colliding methods should work" do
    MonkeyShield.wrap_with_context(:a) {class X;def x;:a;end;end; module Kernel;def a;X.new.x;end;end }
    MonkeyShield.wrap_with_context(:b) {class X;def x;:b;end;end; module Kernel;def b;X.new.x;end;end }
    MonkeyShield.wrap_with_context(:c) {class X;def x;:c;end;end; module Kernel;def c;X.new.x;end;end }

    a.should == :a
    b.should == :b
    c.should == :c
  end

  # SEE: http://coderrr.wordpress.com/2008/03/28/alias_methodmodule-bug-in-ruby-18/
  it "should not wrap Module methods which call super" do
    MonkeyShield.wrap_with_context :test do
      module X
        def no_supa
          no_super
        end

        def yes_supa
          do_something
          super
        end

        def fakeout_supa
          do_something
          "i dont call super "
          do_somehting
        end
      end
    end

    MonkeyShield.context_wrapped?(X, :no_supa).should be_true
    MonkeyShield.context_wrapped?(X, :yes_supa).should be_false
    MonkeyShield.context_wrapped?(X, :fakeout_supa).should be_true
  end

  it "should not wrap the method multiple times (due to recursive method_added calls)" do
    unique = "asdfjhasdfuhuambambaenbweykgaerkyaskyfkagdfvaxmvmdfasdmf"
    backtrace = nil
    MonkeyShield.wrap_with_context :test do
      class X;end
      X.class_eval do
        define_method(unique) do
          :blah!
          raise '' rescue backtrace = $@
        end
      end
    end

    X.new.send(unique)

    backtrace.grep(/#{unique}/).grep(/__MONKEY__/).size.should == 1
  end

  it "aliasing a method then redefining it with the same name should not create an infinite loop" do 
    MonkeyShield.wrap_with_context(:ggg) do
      module X
        def encoding= e
          @encoding = e
        end
      end

      class Y
        include X

        alias :old_enc= :encoding=
        def encoding= e
          if e.nil?
            self.old_enc = 'UTF-8'
          else
            self.old_enc = e
          end
        end
      end
    end

    proc { Y.new.encoding = 'abc' }.should_not raise_error
  end

  it "should be work in the global scope" do
    eval(<<-EOF, $GLOBAL_SCOPE_BINDING)
      MonkeyShield.wrap_with_context :lib1 do
        def to_xml
          "lib1 xml"
        end
      end

      MonkeyShield.wrap_with_context :lib2 do
        def to_xml
          "lib2 xml"
        end
      end
    EOF

    MonkeyShield.context_switch_for Object, :to_xml

    o = Object.new
    proc { o.to_xml }.should raise_error(MonkeyShield::NoContextError)

    MonkeyShield.in_context(:lib1) { o.to_xml }.should == "lib1 xml"
    MonkeyShield.in_context(:lib2) { o.to_xml }.should == "lib2 xml"
  end

  it "methods of the same name should be able to exist peacefully in different contexts" do
    MonkeyShield.wrap_with_context :lib1 do
      class Object
        def to_xml
          "lib1 xml"
        end
      end

      class Lib1
        def x(o)
          o.to_xml
        end

        def mycontext
          MonkeyShield.current_context
        end
      end
    end

    MonkeyShield.wrap_with_context :lib2 do
      class Object
        def to_xml
          "lib2 xml"
        end
      end

      class Lib2
        def x(o)
          o.to_xml
        end

        def mycontext
          MonkeyShield.current_context
        end
      end
    end

    Lib1.new.mycontext.should == :lib1
    Lib2.new.mycontext.should == :lib2
    MonkeyShield.current_context.should be_nil

    MonkeyShield.context_switch_for Object, :to_xml

    o = Object.new
    Lib1.new.x(o).should == "lib1 xml"
    Lib2.new.x(o).should == "lib2 xml"

    proc { o.to_xml }.should raise_error(MonkeyShield::NoContextError)

    MonkeyShield.set_default_context_for Object, :to_xml, :lib1
    o.to_xml.should == "lib1 xml"

    MonkeyShield.set_default_context_for Object, :to_xml, :lib2
    o.to_xml.should == "lib2 xml"

    # still works after setting default?
    Lib1.new.x(o).should == "lib1 xml"
    Lib2.new.x(o).should == "lib2 xml"
  end

  it "module method calling super error should only be caught if debug is set" do
    MonkeyShield.wrap_with_context :test do
      class A 
        def a
          "a"
        end
      end

      module M
        def a
          super
        end
      end

      class B < A
        include M
      end
    end

    lambda { B.new.a }.should raise_error(NoMethodError)

    MonkeyShield.wrap_with_context :test, [], true do
      class AA
        def aa
          "aa"
        end
      end

      module MM
        def aa
          super
        end
      end

      class BB < AA
        include MM
      end
    end

    lambda { BB.new.aa }.should raise_error(MonkeyShield::MethodDefinedInModuleCallsSuper)
  end

  it "ignored method should not be wrapped in context" do
    MonkeyShield.should_not_receive :wrap_method_with_context
    MonkeyShield.wrap_with_context(:test, ['A#ggg']) do
      class A
        def ggg
          "ggg"
        end
      end
    end

    MonkeyShield.should_not_receive :wrap_method_with_context
    MonkeyShield.wrap_with_context(:test, [:ggg]) do
      class A
        def ggg
          "ggg"
        end
      end
      
      class B
        def ggg
          "ggg"
        end
      end
    end

  end

  it "oo visibility should be preserved" do
    MonkeyShield.wrap_with_context :lib1 do
      class Object
        public
          def pub; end
        protected
          def prot; end
        private
          def priv; end
      end
    end

    Object.public_instance_methods.index('pub').should_not be_nil
    Object.protected_instance_methods.index('prot').should_not be_nil
    Object.private_instance_methods.index('priv').should_not be_nil
  end

  it "context switched methods calling context switched methods should work" do
    MonkeyShield.wrap_with_context(:lib1) do
      class Object
        def to_xml
          "lib1 xml"
        end
      end

      class Array
        def to_g
          map { |o| o.to_xml }
        end
      end

      class Lib1
        def x(o)
          o.to_g
        end
      end
    end

    MonkeyShield.wrap_with_context(:lib2) do
      class Object
        def to_xml
          "lib2 xml"
        end
      end

      class Array
        def to_g
          map { |o| o.to_xml + "huh" }
        end
      end

      class Lib2
        def x(o)
          o.to_g
        end
      end
    end

    MonkeyShield.context_switch_for Array, :to_g
    MonkeyShield.context_switch_for Object, :to_xml

    o = Array.new(1)
    Lib1.new.x(o).should == ["lib1 xml"]
    Lib2.new.x(o).should == ["lib2 xmlhuh"]
    MonkeyShield.current_context.should be_nil

    MonkeyShield.set_default_context_for Array, :to_g, :lib1
    o.to_g.should == ["lib1 xml"]
    MonkeyShield.set_default_context_for Array, :to_g, :lib2
    o.to_g.should == ["lib2 xmlhuh"]

    Lib1.new.x(o).should == ["lib1 xml"]
    Lib2.new.x(o).should == ["lib2 xmlhuh"]
  end

  it "the behavior of module_function should be preserved" do
    MonkeyShield.wrap_with_context :fileutils do
      module G
        def x
          :x
        end
        module_function :x
      end

      module H
        module_function

        def a
          :a
        end
      end

      class X
        include G
        include H
      end
    end

    G.x.should == :x
    H.a.should == :a

    X.new.send(:x).should == :x
    X.new.send(:a).should == :a
  end

  it "singleton methods should be context switchable" do
    MonkeyShield.wrap_with_context :fileutils do
      module FileUtils
        def self.mkdir_p
          mkdir
        end

        def self.mkdir
          "blah!"
        end
      end
    end

    MonkeyShield.wrap_with_context :my_fileutils do
      module FileUtils
        def self.mkdir
          "not blah!"
        end
      end
    end

    MonkeyShield.context_switch_for((class << FileUtils; self; end), :mkdir)
    FileUtils.mkdir_p.should == "blah!"
  end

  it "irregular method names should be handled" do
    MonkeyShield.wrap_with_context :lib1 do
      class Object
        define_method "abc[def]abc" do
          :hehe
        end
      end
    end

    Object.send("abc[def]abc").should == :hehe
  end
end
