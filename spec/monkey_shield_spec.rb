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

  def filename fn, code
    eval code, nil, fn
  end

  it "should automatically detect which methods to context switch" do
    MonkeyShield.wrap_with_context :test1 do
      filename 'test1.rb', %{
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
      }
    end

    MonkeyShield.wrap_with_context :test2 do
      filename 'test2.rb', %{
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
      }
    end

    proc { X.new.x }.should raise_error(MonkeyShield::NoContextError)

    test1.should == :x1
    test2.should == :x2
  end

  it "auto context switching more than two colliding methods should work" do
    MonkeyShield.wrap_with_context(:a) do
      filename 'a.rb', %{ class X;def x;:a;end;end; module Kernel;def a;X.new.x;end;end }
    end

    MonkeyShield.wrap_with_context(:b) do
      filename 'b.rb', %{ class X;def x;:b;end;end; module Kernel;def b;X.new.x;end;end }
    end

    MonkeyShield.wrap_with_context(:c) do
      filename 'c.rb', %{ class X;def x;:c;end;end; module Kernel;def c;X.new.x;end;end }
    end

    a.should == :a
    b.should == :b
    c.should == :c
  end

  it "should work in the global scope" do
    eval <<-EOF, $GLOBAL_SCOPE_BINDING, 'lib1.rb'
      MonkeyShield.wrap_with_context :lib1 do
        def to_xml
          "lib1 xml"
        end
      end
    EOF

    eval <<-EOF, $GLOBAL_SCOPE_BINDING, 'lib2.rb'
      MonkeyShield.wrap_with_context :lib2 do
        def to_xml
          "lib2 xml"
        end
      end
    EOF

    MonkeyShield.context_switch_for Object, :to_xml

    o = Object.new
    proc { o.send :to_xml }.should raise_error(MonkeyShield::NoContextError)

    MonkeyShield.in_context(:lib1) { o.send :to_xml }.should == "lib1 xml"
    MonkeyShield.in_context(:lib2) { o.send :to_xml }.should == "lib2 xml"
  end

  it "methods of the same name should be able to exist peacefully in different contexts" do
    MonkeyShield.wrap_with_context :lib1 do
      eval <<-EOE, nil, 'lib1.rb'
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
      EOE
    end

    MonkeyShield.wrap_with_context :lib2 do
      eval <<-EOE, nil, 'lib2.rb'
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
      EOE
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

  it "oo visibility should be preserved for context_switched methods" do
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

    MonkeyShield.context_switch_for Object, :pub
    MonkeyShield.context_switch_for Object, :prot
    MonkeyShield.context_switch_for Object, :priv
    
    Object.private_instance_methods.index('priv').should_not be_nil
    Object.protected_instance_methods.index('prot').should_not be_nil
    Object.public_instance_methods.index('pub').should_not be_nil
  end

  it "context switched methods calling context switched methods should work" do
    MonkeyShield.wrap_with_context(:lib1) do
      eval <<-EOE, nil, 'lib1.rb'
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
      EOE
    end

    MonkeyShield.wrap_with_context(:lib2) do
      eval <<-EOE, nil, 'lib2.rb'
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
      EOE
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

  it "singleton methods should be context switchable" do
    MonkeyShield.wrap_with_context :fileutils do
      eval <<-EOE, nil, 'fileutils.rb'
        module FileUtils
          def self.mkdir_p
            mkdir
          end

          def self.mkdir
            "blah!"
          end
        end
      EOE
    end

    MonkeyShield.wrap_with_context :my_fileutils do
      eval <<-EOE, nil, 'my_fileutils.rb'
        module FileUtils
          def self.mkdir
            "not blah!"
          end
        end
      EOE
    end

    MonkeyShield.context_switch_for((class << FileUtils; self; end), :mkdir)
    FileUtils.mkdir_p.should == "blah!"
  end
end
