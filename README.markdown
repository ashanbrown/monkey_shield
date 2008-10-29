Description
=

Protects you from monkey patching!!

MonkeyShield gets around the issue of method name collision from different libraries.  For example if two libraries define .months on Fixnum and then each library depends on its specific implementation things will break.  With MonkeyShield it's simple to get around this problem.  You just wrap the require statement for each library with a context.  Then you specify which methods need to be context switched and MonkeyShield does the rest!

I actually successfully wrapped all of Rails in a context.  This shit actually works!.... kindof

Usage
=

    MonkeyShield.wrap_with_context :lib1 do
      class Object
        def to_xml
          "<lib1/>"
        end
      end
    
      class Lib1
        def self.xml_for(o)
          o.to_xml
        end
      end
    end
    
    MonkeyShield.wrap_with_context :lib2 do
      class Object
        def to_xml
          "<lib2/>"
        end
      end
    
      class Lib2
        def self.xml_for(o)
          o.to_xml
        end
      end
    end
    
    # or 
    
    MonkeyShield.wrap_with_context(:lib1) { require 'lib1' }
    MonkeyShield.wrap_with_context(:lib2) { require 'lib2' }
    
    # now you can...
    
    MonkeyShield.context_switch_for Object, :to_xml
    
    o = Object.new
    Lib1.xml_for o  # => "<lib1/>"
    Lib2.xml_for o  # => "<lib2/>"
    
    o.to_xml # => raises Protect::NoContextError
    
    MonkeyShield.in_context(:lib2) { o.to_xml } # => "<lib2/>
    
    MonkeyShield.set_default_context_for Object, :to_xml, :lib1
    
    o.to_xml => "<lib1/>"
    
Install
=

    gem sources -a http://gems.github.com
    sudo gem install coderrr-monkey_shield