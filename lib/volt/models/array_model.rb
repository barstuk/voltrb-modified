require 'volt/reactive/reactive_array'
require 'volt/models/model_wrapper'
require 'volt/models/model_helpers'
require 'volt/models/model_state'

module Volt
  class ArrayModel < ReactiveArray
    include ModelWrapper
    include ModelHelpers
    include ModelState

    attr_reader :parent, :path, :persistor, :options, :array

    # For many methods, we want to call load data as soon as the model is interacted
    # with, so we proxy the method, then call super.
    def self.proxy_with_load_data(*method_names)
      method_names.each do |method_name|
        define_method(method_name) do |*args|
          load_data
          super(*args)
        end
      end
    end

    # Some methods get passed down to the persistor.
    def self.proxy_to_persistor(*method_names)
      method_names.each do |method_name|
        define_method(method_name) do |*args, &block|
          if @persistor.respond_to?(method_name)
            @persistor.send(method_name, *args, &block)
          else
            raise "this model's persistance layer does not support #{method_name}, try using store"
          end
        end
      end
    end

    proxy_with_load_data :[], :size, :first, :last
    proxy_to_persistor :find, :skip, :limit, :then

    def initialize(array = [], options = {})
      @options   = options
      @parent    = options[:parent]
      @path      = options[:path] || []
      @persistor = setup_persistor(options[:persistor])

      array = wrap_values(array)

      super(array)

      @persistor.loaded if @persistor
    end

    def attributes
      self
    end

    # Make sure it gets wrapped
    def <<(model)
      load_data

      if model.is_a?(Model)
        # Set the new path
        model.options = @options.merge(path: @options[:path] + [:[]])
      else
        model = wrap_values([model]).first
      end

      super(model)

      if @persistor
        @persistor.added(model, @array.size - 1)
      else
        nil
      end
    end

    # Works like << except it returns a promise
    def append(model)
      promise, model = self.send(:<<, model)

      # Return a promise if one doesn't exist
      promise ||= Promise.new.resolve(model)

      promise
    end


    # Find one does a query, but only returns the first item or
    # nil if there is no match.  Unlike #find, #find_one does not
    # return another cursor that you can call .then on.
    def find_one(*args, &block)
      find(*args, &block).limit(1)[0]
    end

    # Make sure it gets wrapped
    def inject(*args)
      args = wrap_values(args)
      super(*args)
    end

    # Make sure it gets wrapped
    def +(*args)
      args = wrap_values(args)
      super(*args)
    end

    def new_model(*args)
      class_at_path(options[:path]).new(*args)
    end

    def new_array_model(*args)
      ArrayModel.new(*args)
    end

    # Convert the model to an array all of the way down
    def to_a
      array = []
      attributes.each do |value|
        array << deep_unwrap(value)
      end
      array
    end

    def inspect
      # Just load the data on the server making it easier to work with
      load_data if Volt.server?

      if @persistor && @persistor.is_a?(Persistors::ArrayStore) && state == :not_loaded
        # Show a special message letting users know it is not loaded yet.
        "#<#{self.class}:not loaded, access with [] or size to load>"
      else
        # Otherwise inspect normally
        super
      end
    end

    def buffer
      model_path  = options[:path] + [:[]]
      model_klass = class_at_path(model_path)

      new_options = options.merge(path: model_path, save_to: self).reject { |k, _| k.to_sym == :persistor }
      model       = model_klass.new({}, new_options)

      model
    end

    private

    # Takes the persistor if there is one and
    def setup_persistor(persistor)
      if persistor
        @persistor = persistor.new(self)
      end
    end

    # Loads data in an array store persistor when data is requested.
    def load_data
      if @persistor && @persistor.is_a?(Persistors::ArrayStore)
        @persistor.load_data
      end
    end
  end
end
