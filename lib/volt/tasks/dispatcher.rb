module Volt
  # The task dispatcher is responsible for taking incoming messages
  # from the socket channel and dispatching them to the proper handler.
  class Dispatcher

    # Dispatch takes an incoming Task from the client and runs it on the
    # server, returning the result to the client.
    # Tasks returning a promise will wait to return.
    def dispatch(channel, message)
      callback_id, class_name, method_name, meta_data, *args = message
      method_name = method_name.to_sym

      # Get the class
      klass = Object.send(:const_get, class_name)

      promise = Promise.new

      # Check that we are calling on a TaskHandler class and a method provide at
      # TaskHandler or above in the ancestor chain.
      if safe_method?(klass, method_name)
        promise.resolve(nil)

        # Init and send the method
        promise = promise.then do
          Thread.current['meta'] = meta_data

          result = klass.new(channel, self).send(method_name, *args)

          Thread.current['meta'] = nil

          result
        end

      else
        # Unsafe method
        promise.reject(RuntimeError.new("unsafe method: #{method_name}"))
      end

      if callback_id
        # Run the promise and pass the return value/error back to the client
        promise.then do |result|
          channel.send_message('response', callback_id, result, nil)
        end.fail do |error|
          channel.send_message('response', callback_id, nil, error)
          Volt.logger.error(error)
        end
      end
    end

    # Check if it is safe to use this method
    def safe_method?(klass, method_name)
      # Make sure the class being called is a TaskHandler.
      return false unless klass.ancestors.include?(TaskHandler)

      # Make sure the method is defined on the klass we're using and not up the hiearchy.
      #   ^ This check prevents methods like #send, #eval, #instance_eval, #class_eval, etc...
      klass.ancestors.each do |ancestor_klass|
        if ancestor_klass.instance_methods(false).include?(method_name)
          return true
        elsif ancestor_klass == TaskHandler
          # We made it to TaskHandler and didn't find the method, that means it
          # was defined above TaskHandler, so we reject the call.
          return false
        end
      end

      return false
    end
  end
end
