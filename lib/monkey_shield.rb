class Module
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
  VERSION = "0.2.0"

  class NoContextError < StandardError; end
  class MethodDefinedInModuleCallsSuper < StandardError; end

  @context_locations = {}
  @default_contexts = {}
  @context_wrapped_methods = Hash.new{|h,k| h[k] = [] }

  class << self
    attr_accessor :context_locations, :default_contexts, :current_default_context, :context_wrapped_methods
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
          MonkeyShield.L { "MA: <#{self.name rescue self.object_id}> #{klass.name rescue klass.object_id}##{method_name}" }

          return  unless MonkeyShield.hook_method_added?
          return  if exceptions.include? method_name or exceptions.include? "#{klass.name}##{method_name}" or
                     exceptions.any? {|ex| ex.is_a? Regexp and ex =~ method_name.to_s }

          bt = caller

          # our method line should come right after method_added line
          n = 0
          n += 1  until bt[n] =~ /`(singleton_)?method_added'/

          if bt[n+1] =~ /^(.+):\d/
            file = File.expand_path($1) 
            MonkeyShield.context_locations[file] = context
            MonkeyShield.L { "#{method_name} defined in #{file}" }
          end

          MonkeyShield.ignore_method_added { MonkeyShield.wrap_method_with_context(klass, method_name, context) }
        end
      end

      MonkeyShield.alias_method_added_hooks

      MonkeyShield.hook_method_added do
        yield
      end

      MonkeyShield.warnings

      @context_wrapped_methods.select{|k,ctxs| ctxs.uniq.size > 1 }.each do |(klass,method),c|
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

        MonkeyShield.context_wrapped_methods[ [klass, method_name] ] << context
      end
    rescue
      puts "failed to wrap #{klass.name}##{method_name}: #{$!}"
      puts $!.backtrace.join("\n")
    end
          
    def reset!
      @context_wrapped_methods.clear
      @context_locations.clear
    end

    def context_switch_for klass, method_name
      klass.class_eval do
        visibility = instance_method_visibility method_name 
        class_eval <<-EOF, __FILE__, __LINE__+1
          #{visibility}

          def #{tmp_name = MonkeyShield.temp_method_name} *args, &blk
            current_context = MonkeyShield.current_context(1)
            current_context ||= MonkeyShield.default_contexts[ [self.class, #{method_name.inspect}] ]
            current_context ||= MonkeyShield.current_default_context
            raise NoContextError  if ! current_context

            __send__(MonkeyShield.prefix_with_context(#{method_name.inspect}, current_context), *args, &blk)
          end
        EOF
        alias_method method_name, tmp_name
        remove_method tmp_name
      end
    end

    def default_context_for klass, method_name
      @default_contexts[[klass, method_name]]
    end

    def set_default_context_for klass, method_name, context
      @default_contexts[[klass, method_name]] = context
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

          class_eval <<-EOF, __FILE__, __LINE__+1
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

    def current_context(level = 0)
      caller[level] =~ /^(.+):\d/
      file = File.expand_path($1)

      context = MonkeyShield.context_locations[file]
    end

    def in_context(context, &blk)
      orig, self.current_default_context = self.current_default_context, context
      yield
    ensure
      self.current_default_context = orig
    end

    # TODO: inline this!
    def prefix_with_context(method_name, context)
      "__MONKEY__context__#{context}__#{method_name}" 
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

    def context_wrapped?(klass, method_name)
      !! @context_wrapped_methods.has_key?([klass, method_name])
    end

    def warnings
      if Object.const_defined? :BasicObject and ! $LOADED_FEATURES.grep(/facets.+basic.?object/).empty?
        raise "BasicObject on Facets <= 2.4.1 will BREAK this library, use alternative blankslate/basicobject class"
      end
    end
  end
end

MonkeyShield.prevent_recursing_method_added = MonkeyShield.prevent_recursing_singleton_method_added = 0
