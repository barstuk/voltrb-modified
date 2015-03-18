module Volt
  class NoticesController < ModelController
    model :page

    def show_connection_errors
      false
    end

    def hey
      'yep'
    end

    def map_key_class(key)
      case key
      when 'errors'
        'danger'
      when 'warnings'
        'warning'
      when 'successes'
        'success'
      else
        # notices
        'info'
      end
    end
  end
end
