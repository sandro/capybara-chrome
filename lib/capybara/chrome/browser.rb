module Capybara::Chrome

  class Browser
    require 'rbconfig'

    RECOGNIZED_SCHEME = /^https?/

    include Debug
    include Service

    attr_reader :remote, :driver, :console_messages, :error_messages
    attr_accessor :chrome_port
    def initialize(driver, host: "127.0.0.1", port: nil)
      @driver = driver
      @chrome_pid = nil
      @chrome_host = host
      @chrome_port = port || find_available_port(host)
      @remote = nil
      @responses = {}
      @last_response = nil
      @frame_mutex = Mutex.new
      @network_mutex = Mutex.new
      @console_messages = []
      @error_messages = []
      @js_dialog_handlers = Hash.new {|h,key| h[key] = []}
      @unrecognized_scheme_requests = []
      @loader_ids = []
      @loaded_loaders = {}
    end

    def start
      start_chrome
      start_remote
    end

    def evaluate_script(script, *args)
      val = execute_script(script, *args)
      val["result"]["value"]
    end

    def execute_script(script, *args)
      default_options = {expression: script, includeCommandLineAPI: true, awaitPromise: true}
      opts = args[0].respond_to?(:merge) ? args[0] : {}
      opts = default_options.merge(opts)
      val = remote.send_cmd "Runtime.evaluate", opts
      debug script, val
      if details = val["exceptionDetails"]
        if details["exception"]["className"] == "NodeNotFoundError"
          raise Capybara::ElementNotFound
        else
          raise JSException.new(details["exception"].inspect)
        end
      end
      val
    end

    def execute_script!(script, options={})
      remote.send_cmd!("Runtime.evaluate", {expression: script, includeCommandLineAPI: true}.merge(options))
    end

    def evaluate_async_script(script, *args)
      raise "i dunno"
    end

    def wait_for_load
      remote.send_cmd "DOM.getDocument"
      loop do
        val = evaluate_script %(window.ChromeRemotePageLoaded), awaitPromise: false
        break val if val
      end
    end

    def visit(path, attributes={})
      uri = URI.parse(path)
      if uri.scheme.nil?
        uri.host = Capybara.current_session.server.host unless uri.host.present?
        uri.port = Capybara.current_session.server.port unless uri.port.present?
      end
      debug ["visit #{uri}"]
      @last_navigate = remote.send_cmd "Page.navigate", url: uri.to_s, transitionType: "typed"
      wait_for_load
    end

    def with_retry(n:10, timeout: 0.05, &block)
      skip_retry = [Errno::EPIPE, EOFError, ResponseTimeoutError]
      begin
        block.call
      rescue => e
        if n == 0 || skip_retry.detect {|klass| e.instance_of?(klass)}
          raise e
        else
          puts "RETRYING #{e}"
          sleep timeout
          with_retry(n: n-1, timeout: timeout, &block)
        end
      end
    end

    def track_network_events
      return if @track_network_events
      remote.on("Network.requestWillBeSent") do |req|
        if req["type"] == "Document"
          if !RECOGNIZED_SCHEME.match req["request"]["url"]
            puts "ADDING SCHEME"
            @unrecognized_scheme_requests << req["request"]["url"]
          else
            @last_response = nil
          end
        end
      end
      remote.on("Network.responseReceived") do |params|
        debug params["response"]["url"], params["requestId"], params["loaderId"], params["type"]
        if params["type"] == "Document"
          @responses[params["requestId"]] = params["response"]
          @last_response = params["response"]
        end
      end
      remote.on("Network.loadingFailed") do |params|
        debug ["loadingFailed", params]
      end
      @track_network_events = true
    end

    def last_response
      @last_response
    end

    def last_response_or_err
      loop do
        break last_response if last_response
        remote.read_and_process(0.01)
      end
    rescue Timeout::Error
      raise Capybara::ExpectationNotMet
    end

    def status_code
      last_response_or_err["status"]
    end

    def current_url
      document_root["documentURL"]
    end

    def unrecognized_scheme_requests
      remote.read_and_process(1)
      @unrecognized_scheme_requests
    end

    def has_body?(resp)
      debug
      if resp["root"] && resp["root"]["children"]
        resp["root"]["children"].detect do |child|
          next unless child.has_key?("children")
          child["children"].detect do |grandchild|
            grandchild["localName"] == "body"
          end
        end
      end
    end

    def get_document
      val = remote.send_cmd "DOM.getDocument"
    end

    def document_root
      @document_root = get_document["root"]
    end

    def root_node
      @root_node = find_css("html")[0]
    end

    def unset_root_node
      @root_node = nil
    end

    def html
      val = root_node.html
      debug "root", val.size
      val
    end

    def find_css(query)
      debug query
      nodes = query_selector_all(query)
      nodes
    end

    def query_selector_all(query, index=nil)
      wait_for_load
      query = query.dup
      query.gsub!('"', '\"')
      result = if index
                 evaluate_script %( window.ChromeRemoteHelper && ChromeRemoteHelper.findCssWithin(#{index}, "#{query}") )
               else
                 evaluate_script %( window.ChromeRemoteHelper && ChromeRemoteHelper.findCss("#{query}") )
               end
      get_node_results result
    end

    # object_id represents a script that returned of an array of nodes
    def request_nodes(object_id)
      nodes = []
      results = remote.send_cmd("Runtime.getProperties", objectId: object_id, ownProperties: true)
      raise Capybara::ExpectationNotMet if results.nil?
      results["result"].each do |prop|
        if prop["value"]["subtype"] == "node"
          lookup = remote.send_cmd("DOM.requestNode", objectId: prop["value"]["objectId"])
          raise Capybara::ExpectationNotMet if lookup.nil?
          id = lookup["nodeId"]
          if id == 0
            raise Capybara::ExpectationNotMet
          else
            nodes << Node.new(driver, self, id)
          end
        end
      end
      nodes
    end

    def get_node_results(result)
      vals = result.split(",")
      nodes = []
      if vals.any?
        nodes = result.split(",").map do |id|
          Node.new driver, self, id.to_i
        end
      end
      nodes
    end

    def find_xpath(query, index=nil)
      wait_for_load
      query = query.dup
      query.gsub!('"', '\"')
      result = if index
                 evaluate_script %( window.ChromeRemoteHelper && ChromeRemoteHelper.findXPathWithin(#{index}, "#{query}") )
               else
                 evaluate_script %( window.ChromeRemoteHelper && ChromeRemoteHelper.findXPath("#{query}") )
               end
      get_node_results result
    end

    def title
      nodes = find_xpath("/html/head/title")
      if nodes && nodes.first
        nodes[0].text
      else
        ""
      end
    end

    def start_remote
      # @remote = ChromeRemoteClient.new(::ChromeRemote.send(:get_ws_url, {host: "localhost", port: @chrome_port}))
      @remote = RDPClient.new chrome_host: @chrome_host, chrome_port: @chrome_port, browser: self
      remote.start
      after_remote_start
    end

    def after_remote_start
      track_network_events
      enable_console_log
      # enable_lifecycle_events
      enable_js_dialog
      enable_script_debug
      enable_network_interception
      set_viewport(width: 1680, height: 1050)
    end

    def set_viewport(width:, height:, device_scale_factor: 1, mobile: false)
      remote.send_cmd!("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: device_scale_factor, mobile: mobile)
    end

    def enable_network_interception
      remote.send_cmd! "Network.setRequestInterception", patterns: [{urlPattern: "*"}]
      remote.on("Network.requestIntercepted") do |params|
        if Capybara::Chrome.configuration.block_url?(params["request"]["url"]) || (Capybara::Chrome.configuration.skip_image_loading? && params["resourceType"] == "Image")
          # p ["blocking", params["request"]["url"]]
          remote.send_cmd "Network.continueInterceptedRequest", interceptionId: params["interceptionId"], errorReason: "ConnectionRefused"
        else
          # p ["allowing", params["request"]["url"]]
          remote.send_cmd "Network.continueInterceptedRequest", interceptionId: params["interceptionId"]
        end
      end
    end

    def enable_script_debug
      remote.send_cmd "Debugger.enable"
      remote.on("Debugger.scriptFailedToParse") do |params|
        puts "\n\n!!! ERROR: SCRIPT FAILED TO PARSE !!!\n\n"
        p params
      end
    end

    def enable_js_dialog
      remote.on("Page.javascriptDialogOpening") do |params|
        debug ["Dialog Opening", params]
        handler = @js_dialog_handlers[params["type"]].last
        if handler
          debug ["have handler", handler]
          args = {accept: handler[:accept]}
          args.merge!(promptText: handler[:prompt_text]) if params[:type] == "prompt"
          remote.send_cmd("Page.handleJavaScriptDialog", args)
          @js_dialog_handlers[params["type"]].delete(params["type"].size - 1)
        else
          puts "WARNING: Accepting unhandled modal. Use #accept_modal or #dismiss_modal to handle this modal properly."
          puts "Details: #{params.inspect}"
          remote.send_cmd("Page.handleJavaScriptDialog", accept: true)
        end
      end
    end

    def accept_modal(type, text_or_options=nil, options={}, &block)
      @js_dialog_handlers[type.to_s] << {accept: true}
      block.call if block
    end

    def dismiss_modal(type, text_or_options=nil, options={}, &block)
      @js_dialog_handlers[type.to_s] << {accept: false}
      block.call if block
      debug [type, text_or_options, options]
    end

    def enable_console_log
      remote.send_cmd! "Console.enable"
      remote.on "Console.messageAdded" do |params|
        str = "#{params["message"]["source"]}:#{params["message"]["line"]} #{params["message"]["text"]}"
        if params["message"]["level"] == "error"
          @error_messages << str
        else
          @console_messages << str
        end
      end
    end

    def enable_lifecycle_events
      remote.send_cmd! "Page.setLifecycleEventsEnabled", enabled: true
      remote.on("Page.lifecycleEvent") do |params|
        if params["name"] == "init"
          @loader_ids.push(params["loaderId"])
        elsif params["name"] == "load"
          @loaded_loaders[params["loaderId"]] = true
        elsif params["name"] == "networkIdle"
        end
      end
    end

    def loader_loaded?(loader_id)
      @loaded_loaders[loader_id]
    end

    def save_screenshot(path, options={})
      options[:width]  ||= 1000
      options[:height] ||= 10
      render path, options[:width], options[:height]
    end

    def render(path, width=nil, height=nil)
      response = remote.send_cmd "Page.getLayoutMetrics"
      width = response["contentSize"]["width"]
      height = response["contentSize"]["height"]
      response = remote.send_cmd "Page.captureScreenshot", clip: {width: width, height: height, x: 0, y: 0, scale: 1}
      File.open path, "wb" do |f|
        f.write Base64.decode64(response["data"])
      end
    end

    def header(key, value)
      if key.downcase == "user-agent"
        remote.send_cmd!("Network.setUserAgentOverride", userAgent: value)
      else
        remote.send_cmd!("Network.setExtraHTTPHeaders", headers: {key => value})
      end
    end

    def reset
      unset_root_node
      @responses.clear
      @last_response = nil
      @console_messages.clear
      @error_messages.clear
      @js_dialog_handlers.clear
      @unrecognized_scheme_requests.clear
      remote.reset
      remote.send_cmd! "Network.clearBrowserCookies"
      remote.send_cmd! "Runtime.discardConsoleEntries"
      remote.send_cmd! "Network.setExtraHTTPHeaders", headers: {}
      remote.send_cmd! "Network.setUserAgentOverride", userAgent: ""
      visit "about:blank"
    end
  end

end
