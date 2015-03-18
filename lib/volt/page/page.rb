if RUBY_PLATFORM == 'opal'
  require 'opal'
  require 'opal-jquery'
end
require 'volt/models'
require 'volt/controllers/model_controller'
require 'volt/tasks/task_handler'
require 'volt/page/bindings/attribute_binding'
require 'volt/page/bindings/content_binding'
require 'volt/page/bindings/each_binding'
require 'volt/page/bindings/if_binding'
require 'volt/page/bindings/template_binding'
require 'volt/page/bindings/component_binding'
require 'volt/page/bindings/event_binding'
require 'volt/page/template_renderer'
require 'volt/page/string_template_renderer'
require 'volt/page/document_events'
require 'volt/page/sub_context'
require 'volt/page/targets/dom_target'

if RUBY_PLATFORM == 'opal'
  require 'volt/page/channel'
else
  require 'volt/page/channel_stub'
end
require 'volt/router/routes'
require 'volt/models/url'
require 'volt/page/url_tracker'
require 'volt/benchmark/benchmark'
require 'volt/page/tasks'

module Volt
  class Page
    attr_reader :url, :params, :page, :templates, :routes, :events, :model_classes

    def initialize
      @model_classes = {}

      # Run the code to setup the page
      @page          = Model.new

      @url         = URL.new
      @params      = @url.params
      @url_tracker = UrlTracker.new(self)

      @events = DocumentEvents.new

      if RUBY_PLATFORM == 'opal'
        # Setup escape binding for console
        `
          $(document).keyup(function(e) {
            if (e.keyCode == 27) {
              Opal.gvars.page.$launch_console();
            }
          });

          $(document).on('click', 'a', function(event) {
            return Opal.gvars.page.$link_clicked($(this).attr('href'), event);
          });
        `
      end

      # Initialize tasks so we can get the reload message
      tasks if Volt.env.development?

      if Volt.client?
        channel.on('reconnected') do
          @page._reconnected = true

          `setTimeout(function() {`
          @page._reconnected = false
          `}, 2000);`
        end
      end
    end

    def flash
      @flash ||= Model.new({}, persistor: Persistors::Flash)
    end

    def store
      @store ||= Model.new({}, persistor: Persistors::StoreFactory.new(tasks))
    end

    def local_store
      @local_store ||= Model.new({}, persistor: Persistors::LocalStore)
    end

    def cookies
      @cookies ||= Model.new({}, persistor: Persistors::Cookies)
    end

    def tasks
      @tasks ||= Tasks.new(self)
    end

    def link_clicked(url = '', event = nil)
      # Skip when href == ''
      return false if url.blank?

      # Normalize url
      # Benchmark.bm(1) do
      if @url.parse(url)
        if event
          # Handled new url
          `event.stopPropagation();`
        end

        # Clear the flash
        flash.clear

        # return false to stop the event propigation
        return false
      end
      # end

      # Not stopping, process link normally
      true
    end

    # We provide a binding_name, so we can bind events on the document
    def binding_name
      'page'
    end

    def launch_console
      puts 'Launch Console'
    end

    def channel
      @channel ||= begin
        if Volt.client?
          Channel.new
        else
          ChannelStub.new
        end
      end
    end

    attr_reader :events

    def add_model(model_name)
      begin
        model_name                 = model_name.camelize.to_sym
        @model_classes[model_name] = Object.const_get(model_name)
      rescue NameError => e
        # Handle if the model is user (Volt's provided user model is scoped under Volt::)
        raise unless model_name == :User
      end
    end

    def add_template(name, template, bindings)
      @templates ||= {}

      # First template gets priority.  The backend will load templates in order so
      # that local templates come in before gems (so they can be overridden).
      #
      # TODO: Currently this means we will send templates to the client that will
      # not get used because they are being overridden.  Need to detect that and
      # not send them.
      unless @templates[name]
        @templates[name] = { 'html' => template, 'bindings' => bindings }
      end
      # puts "Add Template: #{name}"
    end

    def add_routes(&block)
      @routes   ||= Routes.new
      @routes.define(&block)
      @url.router = @routes
    end

    def start
      # Setup to render template
      Element.find('body').html = '<!-- $CONTENT --><!-- $/CONTENT -->'

      load_stored_page

      # Do the initial url params parse
      @url_tracker.url_updated(true)

      main_controller = MainController.new

      # Setup main page template
      TemplateRenderer.new(self, DomTarget.new, main_controller, 'CONTENT', 'main/main/main/body')

      # Setup title reactive template
      @title_template = StringTemplateRender.new(self, main_controller, 'main/main/main/title')

      # Watch for changes to the title template
      proc do
        title = @title_template.html.gsub(/\n/, ' ')
        `document.title = title;`
      end.watch!
    end

    # When the page is reloaded from the backend, we store the $page.page, so we
    # can reload the page in the exact same state.  Speeds up development.
    def load_stored_page
      if Volt.client?
        if `sessionStorage`
          page_obj_str = nil

          `page_obj_str = sessionStorage.getItem('___page');`
          `if (page_obj_str) {`
          `sessionStorage.removeItem('___page');`

          JSON.parse(page_obj_str).each_pair do |key, value|
            page.send(:"_#{key}=", value)
          end
          `}`
        end
      end
    rescue => e
      puts "Unable to restore: #{e.inspect}"
    end
  end

  if Volt.client?
    $page = Page.new

    # Call start once the page is loaded
    Document.ready? do
      $page.start
    end
  end
end
