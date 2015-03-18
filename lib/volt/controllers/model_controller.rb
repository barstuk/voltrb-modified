require 'volt/reactive/reactive_accessors'

module Volt
  class ModelController
    include ReactiveAccessors

    reactive_accessor :current_model

    def self.model(val)
      @default_model = val
    end

    # Sets the current model on this controller
    def model=(val)
      # Start with a nil reactive value.
      self.current_model ||= Model.new

      if Symbol === val || String === val
        collections = [:page, :store, :params, :controller]
        if collections.include?(val.to_sym)
          self.current_model = send(val)
        else
          fail "#{val} is not the name of a valid model, choose from: #{collections.join(', ')}"
        end
      else
        self.current_model = val
      end
    end

    def model
      model = self.current_model

      # If the model is a proc, call it now
      if model && model.is_a?(Proc)
        model = model.call
      end

      model
    end

    def self.new(*args, &block)
      inst = allocate

      inst.model = @default_model if @default_model

      # In MRI initialize is private for some reason, so call it with send
      inst.send(:initialize, *args, &block)

      inst
    end

    attr_accessor :attrs

    def initialize(*args)
      if args[0]
        # Assign the first passed in argument to attrs
        self.attrs = args[0]

        # If a model attribute is passed in, we assign it directly
        if attrs.respond_to?(:model)
          self.model = attrs.locals[:model]
        end
      end
    end

    # Change the url params, similar to redirecting to a new url
    def go(url)
      self.url.parse(url)
    end

    def page
      $page.page
    end

    def store
      $page.store
    end

    def flash
      $page.flash
    end

    def params
      $page.params
    end

    def local_store
      $page.local_store
    end

    def cookies
      $page.cookies
    end

    def url
      $page.url
    end

    def channel
      $page.channel
    end

    def tasks
      $page.tasks
    end

    def controller
      @controller ||= Model.new
    end

    def url_for(params)
      $page.url.url_for(params)
    end

    def url_with(params)
      $page.url.url_with(params)
    end

    def loaded?
      respond_to?(:state) && state == :loaded
    end

    # Check if this controller responds_to method, or the model
    def respond_to?(method_name)
      super || begin
        model = self.model

        model.respond_to?(method_name) if model
      end
    end

    def method_missing(method_name, *args, &block)
      model = self.model

      if model
        model.send(method_name, *args, &block)
      else
        super
      end
    end
  end
end
