module Volt
  class NumericalityValidator
    def self.validate(model, old_model, field_name, args)
      # Construct the class and return the errors
      self.new(model, field_name, args).errors
    end

    attr_reader :errors

    def initialize(model, field_name, args)
      @field_name = field_name
      @args = args
      @errors = {}

      @value = model.read_attribute(field_name)

      # Convert to float if it is a string for a float
      @value = Kernel.Float(@value) rescue nil

      check_errors
    end

    def add_error(error)
      field_errors = (@errors[@field_name] ||= [])
      field_errors << error
    end

    # Looks at the value
    def check_errors
      if @value && @value.is_a?(Numeric)
        if @args.is_a?(Hash)

          @args.each do |arg, val|
            case arg
            when :min
              if @value < val
               add_error("number must be greater than #{val}")
              end
            when :max
              if @value > val
                add_error("number must be less than #{val}")
              end
            end
          end

        end
      else
        message = (@args.is_a?(Hash) && @args[:message]) || 'must be a number'
        add_error(message)
      end
    end
  end
end
