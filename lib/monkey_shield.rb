require 'rubygems'
gem 'ParseTree', '>=3.0.2'
gem 'RubyInline', '>=3.8.1'
require 'inline'
require 'parse_tree'
require 'parse_tree_extensions'

class TmpClass; end

class UnboundMethod
  def to_sexp
    um = self
    TmpClass.send(:define_method, :__tmp__, um)
    TmpClass.new.method(:__tmp__).to_sexp
  end
end

class Module
  # the singleton method which module_function creates should point to the original 
  # method, not the context wrapped one
  def __MONKEY__module_function__with_args(*methods)
    methods.each do |method|
      if unique_method_name = MonkeyShield::UNIQUE_METHOD_NAMES[ [self, method] ]
        __module_function__(unique_method_name)
        (class << self; self; end).class_eval { alias_method method, unique_method_name }
      else
        __module_function__(method)
      end
    end
  end  

  alias_method :__module_function__, :module_function  # store original module_function
  # this has to be a C function so that it can modify the module's scope
  inline { |builder| builder.c_raw %q{
    static VALUE __MONKEY__module_function(int argc, VALUE *argv, VALUE self) {
      if (argc == 0)
        return rb_funcall(self, rb_intern("__module_function__"), 0);
      else
        return rb_funcall2(self, rb_intern("__MONKEY__module_function__with_args"), argc, argv);
    }
  } }

  def instance_method_visibility(method_name)
    if public_method_defined? method_name
      :public
    elsif protected_method_defined? method_name
      :protected
    elsif private_method_defined? method_name
      :private
    end
  end
end

class MonkeyShield
  VERSION = "0.1.0"

  UNIQUE_METHOD_NAMES = {}
  CONTEXT_WRAPPED_METHODS = Hash.new{|h,k| h[k] = [] }

  class NoContextError < StandardError; end
  class MethodDefinedInModuleCallsSuper < StandardError; end

  class << self
    attr_accessor :prevent_recursing_method_added, :prevent_recursing_singleton_method_added
    attr_accessor :debug, :log

    def L
      puts yield  if log
    end

    def wrap_with_context(context, exceptions = [], debug = false, &blk)
      exceptions << :method_added
      context = context.to_sym
      orig_debug, self.debug = self.debug, debug
      Module.class_eval do
        define_method :__MONKEY__method_added do |klass, method_name|
          MonkeyShield.L { "MA: <#{self}> #{klass}##{method_name}" }
          return  unless MonkeyShield.hook_method_added?
          return  if exceptions.include? method_name or exceptions.include? "#{klass.name}##{method_name}" or
                     exceptions.any? {|ex| ex.is_a? Regexp and ex =~ method_name.to_s }
          return  if MonkeyShield.module_calls_super?(klass, method_name)

          MonkeyShield.ignore_method_added { MonkeyShield.wrap_method_with_context(klass, method_name, context) }
        end
      end

      MonkeyShield.alias_method_added_hooks

      MonkeyShield.hook_module_function do
        MonkeyShield.hook_method_added do
          yield
        end
      end

      MonkeyShield.warnings

      CONTEXT_WRAPPED_METHODS.select{|k,ctxs| ctxs.uniq.size > 1 }.each do |(klass,method),c|
        MonkeyShield.context_switch_for klass, method 
      end
    ensure
      self.debug = orig_debug
    end

    def wrap_method_with_context(klass, method_name, context)
      klass.class_eval do
        visibility = instance_method_visibility method_name 
        return  if ! visibility  # something else removed the method already, wth!
        MonkeyShield.L { "wrapping #{klass}##{method_name} in #{context}" }

        method_name_with_context = MonkeyShield.prefix_with_context(method_name, context)
        unique_method_name = MonkeyShield.unique_method_name(method_name)

        alias_method method_name_with_context, method_name
        alias_method unique_method_name, method_name
        private method_name_with_context, unique_method_name

        UNIQUE_METHOD_NAMES[ [klass, method_name] ] = unique_method_name
        CONTEXT_WRAPPED_METHODS[ [klass, method_name] ] << context

        class_eval <<-EOF, __FILE__, __LINE__
          def #{tmp_name = MonkeyShield.temp_method_name} *args, &blk
            MonkeyShield.in_context #{context.inspect} do
              #{unique_method_name}(*args, &blk)
            end
          #{%{rescue NoMethodError
            if $!.message =~ /super: no superclass method `(.+?)'/
              raise MonkeyShield::MethodDefinedInModuleCallsSuper, "Please add #{self.name}##{method_name} to the exceptions list!"
            end

            raise}  if MonkeyShield.debug}
          end
        EOF
        alias_method method_name, tmp_name
        remove_method tmp_name

        send visibility, method_name
      end
    rescue
      puts "failed to wrap #{klass.name}##{method_name}: #{$!}"
      puts $!.backtrace.join("\n")
    end
          
    def reset!
      CONTEXT_WRAPPED_METHODS.clear
      UNIQUE_METHOD_NAMES.clear
    end

    def context_switch_for klass, method_name
      klass.class_eval do
        class_eval <<-EOF, __FILE__, __LINE__
          def #{tmp_name = MonkeyShield.temp_method_name} *args, &blk
            raise NoContextError  if ! current_context = MonkeyShield.current_context
            __send__(MonkeyShield.prefix_with_context(#{method_name.inspect}, current_context), *args, &blk)
          end
        EOF
        alias_method method_name, tmp_name
        remove_method tmp_name
      end
    end

    def set_default_context_for klass, method_name, context
      context_switched_name = "__context_switch__#{MonkeyShield.unique}__#{sanitize_method(method_name)}"
      klass.class_eval do
        alias_method context_switched_name, method_name
        class_eval <<-EOF, __FILE__, __LINE__
          def #{tmp_name = MonkeyShield.temp_method_name} *args, &blk
            if ! MonkeyShield.current_context
              need_pop = true
              MonkeyShield.push_context #{context.inspect}
            end

            #{context_switched_name}(*args, &blk)
          ensure
            MonkeyShield.pop_context  if need_pop
          end
        EOF
        alias_method method_name, tmp_name
        remove_method tmp_name
      end
    end

    def alias_method_added_hooks
      return  if @method_added_hooks_aliased

      # TODO; catch method_added being added and automatically wrap it
      # these list must contain all classes any other library might override method_added on (eg. BlankSlate classes)
      klasses = [Module, (class << Object; self; end), (class << Kernel; self; end)]
      klasses.each do |klass|
        klass.class_eval do
          if method_defined? :method_added
            old_method_added = MonkeyShield.unique_method_name(:method_added)
            alias_method old_method_added, :method_added
          end

          if method_defined? :singleton_method_added
            old_singleton_method_added = MonkeyShield.unique_method_name(:singleton_method_added)
            alias_method old_singleton_method_added, :singleton_method_added
          end

          class_eval <<-EOF, __FILE__, __LINE__
            def __MONKEY__method_added__proxy method_name
              n = MonkeyShield.prevent_recursing_method_added += 1

              __MONKEY__method_added(self, method_name)  if n == 1
              #{"#{old_method_added} method_name"  if old_method_added}
            ensure
              MonkeyShield.prevent_recursing_method_added -= 1
            end

            def __MONKEY__singleton_method_added__proxy method_name
              n = MonkeyShield.prevent_recursing_singleton_method_added += 1

              __MONKEY__method_added((class<<self;self;end), method_name)  if n == 1
              #{"#{old_singleton_method_added} method_name"  if old_singleton_method_added}
            ensure
              MonkeyShield.prevent_recursing_singleton_method_added -= 1
            end
          EOF

          alias_method :method_added, :__MONKEY__method_added__proxy
          alias_method :singleton_method_added, :__MONKEY__singleton_method_added__proxy
        end
      end

      @method_added_hooks_aliased = true
    end

    def hook_module_function(&blk)
      old_module_function = MonkeyShield.unique_method_name(:module_function)
      Module.class_eval do
        alias_method old_module_function, :module_function
        alias_method :module_function, :__MONKEY__module_function
      end

      yield
    ensure
      Module.class_eval { alias_method :module_function, old_module_function }
    end

    def context_stack
      s = Thread.current[:__MONKEY__method_context] and s.dup
    end

    inline do |builder| 
      builder.include '"node.h"'
      builder.prefix %{
        extern rb_thread_t rb_curr_thread;
        static ID __MONKEY__method_context;

        // def push_context(context)
        //   (Thread.current[:__MONKEY__method_context] ||= []).push context
        // end

        VALUE __push_context(VALUE context) {
          VALUE val = rb_thread_local_aref(rb_curr_thread->thread, __MONKEY__method_context);
          if (val == Qnil) {
            val = rb_ary_new();
            rb_thread_local_aset(rb_curr_thread->thread, __MONKEY__method_context, val);
          }

          rb_ary_push(val, context);

          return Qnil;
        }

        // def pop_context
        //   s = Thread.current[:__MONKEY__method_context] and s.pop
        // end

        VALUE __pop_context() {
          VALUE val = rb_thread_local_aref(rb_curr_thread->thread, __MONKEY__method_context);
          if (val != Qnil)
            return rb_ary_pop(val);

          return Qnil;
        }
      }

      builder.c %{
        static void initialize_symbol() { __MONKEY__method_context = rb_intern("__MONKEY__method_context"); }
      }

      builder.c %{
        // def current_context
        //  s = Thread.current[:__MONKEY__method_context] and s.last
        // end

        static VALUE current_context() {
          VALUE val = rb_thread_local_aref(rb_curr_thread->thread, __MONKEY__method_context);
          if (val == Qnil)  return Qnil;
          if (RARRAY(val)->len == 0) return Qnil;
          return RARRAY(val)->ptr[RARRAY(val)->len-1];
        }
      }

      builder.c %{
        static VALUE push_context(VALUE context) {
          return __push_context(context);
        }
      }  

      builder.c %{
        static VALUE pop_context() {
          return __pop_context();
        }
      }

#    def in_context(context, &blk)
#      push_context context
#      yield
#    ensure
#      pop_context
#    end
#
      builder.c %{
        static VALUE in_context(VALUE context) {
          __push_context(context);
          return rb_ensure(rb_yield, NULL, __pop_context, NULL);
        }
      }

    # def prefix_with_context(method_name, context)
    #   "__MONKEY__context__#{context}__#{method_name}" 
    # end
      builder.c %{
        static VALUE prefix_with_context(VALUE method_name, VALUE context) {
          char tmp[1024];
          sprintf(tmp, "__MONKEY__context__%s__%s", rb_id2name(rb_to_id(context)), rb_id2name(rb_to_id(method_name)));
          return rb_str_new2(tmp);
        }
      }
    end

    def unique
      $unique_counter ||= 0
      $unique_counter += 1
    end

    def unique_method_name(method_name)
      "__MONKEY__unique_method__#{unique}__#{sanitize_method(method_name)}"
    end

    def temp_method_name
      "__MONKEY__temp_method__#{unique}"
    end

    def sanitize_method(method_name)
      method_name.to_s.gsub(/\W/,'')
    end

    def hook_method_added(hook = true, &blk)
      orig, @hook_method_added = !!@hook_method_added, hook
      yield
    ensure
      @hook_method_added = orig
    end

    def ignore_method_added(&blk)
      hook_method_added false, &blk
    end

    def hook_method_added?
      @hook_method_added
    end

    def module_calls_super?(klass, method_name)
      klass.class == Module and 
        ! (klass.instance_method(method_name).to_sexp.flatten & [:super, :zsuper]).empty?
    rescue UnsupportedNodeError
      false
    end

    def context_wrapped?(klass, method_name)
      !! CONTEXT_WRAPPED_METHODS.has_key?([klass, method_name])
    end

    def warnings
      if Object.const_defined? :BasicObject and ! $LOADED_FEATURES.grep(/facets.+basic.?object/).empty?
        raise "BasicObject on Facets <= 2.4.1 will BREAK this library, use alternative blankslate/basicobject class"
      end
    end
  end
end

MonkeyShield.initialize_symbol
MonkeyShield.prevent_recursing_method_added = MonkeyShield.prevent_recursing_singleton_method_added = 0
