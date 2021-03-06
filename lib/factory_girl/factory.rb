require "active_support/core_ext/hash/keys"
require "active_support/inflector"

module FactoryGirl
  # Raised when a factory is defined that attempts to instantiate itself.
  class AssociationDefinitionError < RuntimeError
  end

  # Raised when a callback is defined that has an invalid name
  class InvalidCallbackNameError < RuntimeError
  end

  # Raised when a factory is defined with the same name as a previously-defined factory.
  class DuplicateDefinitionError < RuntimeError
  end

  class Factory
    attr_reader :name #:nodoc:

    def factory_name
      puts "WARNING: factory.factory_name is deprecated. Use factory.name instead."
      name
    end

    def class_name #:nodoc:
      @class_name || name
    end

    def build_class #:nodoc:
      @build_class ||= class_name.to_s.camelize.constantize
    end

    def default_strategy #:nodoc:
      @default_strategy || :create
    end

    def initialize(name, options = {}) #:nodoc:
      assert_valid_options(options)
      @name             = name.to_s.underscore.to_sym
      @parent_factory   = nil
      @parent           = options[:parent]
      @aliases          = options[:aliases] || []
      @traits           = options[:traits]  || []
      @class_name       = options[:class]
      @default_strategy = options[:default_strategy]
      @defined_traits   = []
      @children         = []
      @attribute_list   = AttributeList.new
      @compiled         = false
    end

    def allow_overrides
      @attribute_list.overridable
      self
    end

    def allow_overrides?
      @attribute_list.overridable?
    end

    def add_child(factory)
      @children << factory unless @children.include?(factory)
    end

    def define_trait(trait)
      @defined_traits << trait
    end

    def add_callback(name, &block)
      @attribute_list.add_callback(Callback.new(name, block))
    end

    def attributes
      ensure_compiled
      AttributeList.new.tap do |list|
        @traits.reverse.map { |name| trait_by_name(name) }.each do |trait|
          list.apply_attributes(trait.attributes)
        end

        list.apply_attributes(@attribute_list)
        list.apply_attributes(@parent_factory.attributes) if @parent_factory
      end
    end

    def run(proxy_class, overrides) #:nodoc:
      ensure_compiled
      proxy = proxy_class.new(build_class)
      callbacks.each { |callback| proxy.add_callback(callback) }
      overrides = overrides.symbolize_keys

      attributes.each do |attribute|
        factory_overrides = overrides.select { |attr, val| attribute.aliases_for?(attr) }
        if factory_overrides.empty?
          attribute.add_to(proxy)
        else
          factory_overrides.each { |attr, val| proxy.set(attr, val, attribute.ignored); overrides.delete(attr) }
        end
      end
      overrides.each { |attr, val| proxy.set(attr, val) }
      proxy.result(@to_create_block)
    end

    def human_names
      names.map {|name| name.to_s.humanize.downcase }
    end

    def associations
      attributes.select {|attribute| attribute.association? }
    end

    def trait_by_name(name)
      if existing_attribute = trait_for(name)
        existing_attribute
      elsif @parent
        FactoryGirl.factory_by_name(@parent).trait_by_name(name)
      else
        FactoryGirl.trait_by_name(name)
      end
    end

    # Names for this factory, including aliases.
    #
    # Example:
    #
    #   factory :user, :aliases => [:author] do
    #     # ...
    #   end
    #
    #   FactoryGirl.create(:author).class
    #   # => User
    #
    # Because an attribute defined without a value or block will build an
    # association with the same name, this allows associations to be defined
    # without factories, such as:
    #
    #   factory :user, :aliases => [:author] do
    #     # ...
    #   end
    #
    #   factory :post do
    #     author
    #   end
    #
    #   FactoryGirl.create(:post).author.class
    #   # => User
    def names
      [name] + @aliases
    end

    def to_create(&block)
      @to_create_block = block
    end

    def callbacks
      attributes.callbacks
    end

    def compile
      inherit_factory(FactoryGirl.factory_by_name(@parent)) if @parent

      declarations.each do |declaration|
        declaration.to_attributes.each do |attribute|
          define_attribute(attribute)
        end
      end

      @compiled = true
    end

    def declare_attribute(declaration)
      @attribute_list.declare_attribute(declaration)
    end

    def ensure_compiled
      compile unless @compiled
    end

    def inherit_factory(parent) #:nodoc:
      parent.ensure_compiled
      @class_name       ||= parent.class_name
      @default_strategy ||= parent.default_strategy
      @parent_factory   = parent

      allow_overrides if parent.allow_overrides?
      parent.add_child(self)
    end

    private

    def declarations
      @attribute_list.declarations
    end

    def define_attribute(attribute)
      if attribute.respond_to?(:factory) && attribute.factory == self.name
        raise AssociationDefinitionError, "Self-referencing association '#{attribute.name}' in factory '#{self.name}'"
      end

      @attribute_list.define_attribute(attribute)
    end

    def assert_valid_options(options)
      options.assert_valid_keys(:class, :parent, :default_strategy, :aliases, :traits)

      if options[:default_strategy]
        assert_valid_strategy(options[:default_strategy])
        puts "WARNING: default_strategy is deprecated."
        puts "Override to_create if you need to prevent a call to #save!."
      end
    end

    def assert_valid_strategy(strategy)
      unless Proxy.const_defined? strategy.to_s.camelize
        raise ArgumentError, "Unknown strategy: #{strategy}"
      end
    end

    def trait_for(name)
      @defined_traits.detect {|trait| trait.name == name }
    end
  end
end
