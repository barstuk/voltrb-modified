module Volt
  # The query listener is what gets notified on the backend when the results from
  # a query have changed.  It then will make the necessary changes to any ArrayStore's
  # to get them to display the new data.
  class QueryListener
    def initialize(query_listener_pool, tasks, collection, query)
      @query_listener_pool = query_listener_pool
      @tasks               = tasks
      @stores              = []

      @collection = collection
      @query      = query

      @listening = false
    end

    def add_listener
      @listening = true

      # Call the backend and add the listner
      QueryTasks.add_listener(@collection, @query).then do |ret|
        results, errors = ret

        # When the initial data comes back, add it into the stores.
        @stores.dup.each do |store|
          # Clear if there are existing items
          store.model.clear if store.model.size > 0

          results.each do |index, data|
            store.add(index, data)
          end

          store.change_state_to(:loaded)
        end
      end.fail do |err|
        puts "Error adding listener: #{err.inspect}"
      end
    end

    def add_store(store, &block)
      @stores << store

      if @listening
        # We are already listening and have this model somewhere else,
        # copy the data from the existing model.
        store.model.clear
        @stores.first.model.each_with_index do |item, index|
          store.add(index, item.to_h)
        end

        store.change_state_to(:loaded)
      else
        # First time we've added a store, setup the listener and get
        # the initial data.
        add_listener
      end
    end

    def remove_store(store)
      @stores.delete(store)

      # When there are no stores left, remove the query listener from
      # the pool, it can get created again later.
      if @stores.size == 0
        @query_listener_pool.remove(@collection, @query)

        # Stop listening
        if @listening
          @listening = false
          QueryTasks.remove_listener(@collection, @query)
        end
      end
    end

    def added(index, data)
      @stores.each do |store|
        store.add(index, data)
      end
    end

    def removed(ids)
      @stores.each do |store|
        store.remove(ids)
      end
    end

    def changed(model_id, data)
      $loading_models = true
      puts "new data: #{data.inspect}"
      Persistors::ModelStore.changed(model_id, data)
      $loading_models = false
    end
  end
end
