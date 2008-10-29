Description
=

Protects you from monkey patching!!

MonkeyShield gets around the issue of method name collision from different libraries.  For example if two libraries define Fixnum#minutes differently and each library depends on its specific implementation then things will break.  With MonkeyShield it's simple to get around this problem.  You just wrap the require statement for each library with a context and MonkeyShield does the rest!

I actually successfully wrapped all of Rails in a context.  This shit actually works!... kindof, use at your own risk!

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
    
    o = Object.new
    Lib1.xml_for o  # => "<lib1/>"
    Lib2.xml_for o  # => "<lib2/>"
    
    o.to_xml # => raises MonkeyShield::NoContextError
    
    MonkeyShield.in_context(:lib2) { o.to_xml } # => "<lib2/>
    
    MonkeyShield.set_default_context_for Object, :to_xml, :lib1
    
    o.to_xml => "<lib1/>"
    
Install
=

    gem sources -a http://gems.github.com
    sudo gem install coderrr-monkey_shield

Todo
=

Instead of explicity wrapping code in a block, we should allow something like

    MonkeyShield.wrap_libraries_in_context('activesupport')

which would hook require and when that library is required it will wrap the require in a context with the same name.  This would allow you to wrap requires inside of big librarys w/o access to the source code.
