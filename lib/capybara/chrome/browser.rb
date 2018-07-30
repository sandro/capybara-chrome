module Capybara::Chrome

  class Browser
    require 'rbconfig'

    RECOGNIZED_SCHEME = /^https?/

    include Debug
    include Service

    attr_reader :remote, :driver, :console_messages, :error_messages
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
    end

    def start
      start_chrome
      start_remote
    end

    # def describe_node(id)
    #   val = remote.send_cmd("DOM.describeNode", nodeId: id)
    #   p ["describe_node", val,val.class]
    #   val = evaluate_script("document.querySelector('#upcoming-shipments')")
    #   p val
    #   oId = val["result"]["objectId"]
    #   val = remote.send_cmd("Runtime.callFunctionOn", functionDeclaration: "function() {return this.innerText}", objectId: oId)
    #   p ["functionOn", val]
    #   val = remote.send_cmd("DOM.requestNode", objectId: oId)
    #   p ["request node", val]
    #   val
    # end

    def evaluate_script(script, *args)
      val = execute_script(script)
      val["result"]["value"]
    end

    def execute_script(script, *args)
      val = remote.send_cmd "Runtime.evaluate", expression: script, includeCommandLineAPI: true, awaitPromise: true
      debug script, val
      if details = val["exceptionDetails"]
        if details["exception"]["className"] == "NodeNotFoundError"
          puts "got exception"
          p details
puts caller
          raise Capybara::ElementNotFound
        else
          p ["got JS exception", details]
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
      with_retry do
        execute_script %(window.ChromeRemoteHelper && console.log("haveit"); ChromeRemoteHelper.waitWindowLoaded())
      end
    end

    def visit(path, attributes={})
      uri = URI.parse(path)
      if uri.scheme.nil?
        uri.host = Capybara.current_session.server.host unless uri.host.present?
        uri.port = Capybara.current_session.server.port unless uri.port.present?
      end
      debug ["visit #{uri}"]
      # evaluate_script %(window.ChromeRemoteHelper && ChromeRemoteHelper.waitDOMContentLoaded())
      # @responses.clear
      if @last_navigate
        wait_for_load
        # puts "VISIT WAITING"
        # tm = Benchmark.realtime do
        # remote.wait_for("Network.responseReceived", 2) do |req|
        #   req["type"] == "Document"
        # end
        # end
        # puts "VISIT WAITED #{tm}"
      end
      # puts "VISITING #{uri}"
      @last_navigate = remote.send_cmd "Page.navigate", url: uri.to_s, transitionType: "typed"
      debug "last_navigate", @last_navigate
      # puts "WAITING"
      # remote.wait_for "Page.domContentEventFired"
      wait_for_load
      # remote.wait_for "Page.loadEventFired"
      # puts "WAITING DONE"
      # debug val, "wait done"
    end

    def with_retry(n:10, timeout: 0.05, &block)
      begin
        block.call
      rescue => e
        if n == 0
          raise e
        else
          puts "RETRYING #{e}"
          #sleep timeout
$stderr.puts "read_and_process"
remote.read_and_process(timeout)
          with_retry(n: n-1, timeout: timeout, &block)
        end
      end
    end

    def track_network_events
      return if @track_network_events
      # remote.on("Network.requestWillBeSent") do |req|
      #   debug req if req["type"] == "XHR"
      #   if req["type"] == "Document"
      #     debug "WILL WAIT", req
      #     remote.wait_for("Network.responseReceived") do |resp|
      #       if resp["type"] == req["type"] && resp["requestId"] == req["requestId"]
      #         debug "GOTIT", resp["requestId"], resp["loaderId"], resp["type"]
      #         @responses[resp["requestId"]] = resp["response"]
      #         true
      #       end
      #     end
      #   end
      # end
      remote.on("Network.requestWillBeSent") do |req|
        if req["type"] == "Document"
          # p ["DOC Request", req["request"]["url"], req]
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
          # p ["DOC Response", params["response"]["url"]]
          @responses[params["requestId"]] = params["response"]
          @last_response = params["response"]
        end
      end
      remote.on("Network.loadingFailed") do |params|
        debug ["loadingFailed", params]
      end
      # remote.on("Page.frameScheduledNavigation") do |params|
      #   debug "waiting"
      #   val = remote.wait_for("Page.frameNavigated")
      #   debug "wait done", val
      # end
      @track_network_events = true

      # @loader_ids = {}
      # @pages = []
      # @waiting = false

      # remote.on("DOM.documentUpdated") do
      #   puts "DOCUMENT UPDATED"
      # end

      # remote.on("Page.frameStartedLoading") do |params|
      #   puts "frame started loading"
      #   remote.wait_for("Page.frameStoppedLoading") do
      #     puts "frame done loading"
      #     true
      #   end
      # end

      # form submit
      # remote.on("Page.frameScheduledNavigation") do |params|
      #   p ["schedule", @waiting]
      #   next if @waiting
      #   @waiting = true
      #   # remote.wait_for("Page.frameNavigated") do |params2|
      #   p ["ABOUT TO wait FOR FRAME", params["frameId"]]
      #   # remote.wait_for("Page.frameStoppedLoading") do |params2|
      #   #   p ["navigated", params, params2]
      #   #   # params["frameId"] == params2["frame"]["id"]
      #   #   params["frameId"] == params2["frameId"]
      #   # end
      #   remote.wait_for("Page.lifecycleEvent") do |lcycle_params|
      #     # p ["wait for block called", lcycle_params["name"]]
      #     if lcycle_params["name"] == "DOMContentLoaded" && params["frameId"] == lcycle_params["frameId"]
      #       @loader_ids[lcycle_params["loaderId"]] = true
      #       @remote.response_events.delete_if {|k,v| k == lcycle_params["loaderId"]}
      #       true
      #     end
      #   end
      #   @waiting = false
      #   p ["wait done"]
      #   unset_root_node
      #   # root_node
      # end

      # remote.on("Network.requestWillBeSent") do |params|
      #   lid = params["loaderId"]
      #   if @loader_ids.has_key?(lid) || @waiting
      #     p ["skipping request", lid]
      #     next
      #   end
      #   # @waiting = true
      #   @loader_ids[lid] = false
      #   # @network_mutex.lock unless @network_mutex.locked?
      #   p ["ABOUT TO wait FOR REQUEST"]
      #   # next if @waiting
      #   # @waiting = true
      #   remote.wait_for("Page.lifecycleEvent") do |lcycle_params|
      #     # p ["wait for block called", lcycle_params["name"]]
      #     if (lcycle_params["name"] == "DOMContentLoaded"  || lcycle_params["name"] == "networkIdle")
      #       loaded = @loader_ids[lcycle_params["loaderId"]]
      #       if !loaded
      #         @loader_ids[lcycle_params["loaderId"]] = true
      #       end
      #     end
      #     val = @loader_ids.all? {|k,v| v == true}
      #     if val
      #       @remote.response_events.delete_if {|k,v| k == lcycle_params["loaderId"]}
      #     else
      #       puts "waiting again #{@loader_ids}"
      #     end
      #     val
      #   end
      #   # @waiting = false
      #   p ["wait done"]
      #   unset_root_node
      #   # root_node
      # end
      # remote.on("Network.loadingFinished") do |params|
      #   @network_mutex.unlock if @network_mutex.locked?
      # end
      # remote.on("Page.frameScheduledNavigation") do |params|
      #   debug "frame schedule", params
      #   p ["frame scheduled"]
      #   @network_mutex.lock
      #   p ["frame scheduled locked"]
      # end
      #   Thread.new do
      #     @frame_mutex.synchronize do
      #       debug "frame schedule in thread", params, Thread.current
      #       # val = remote.wait_for("Page.frameNavigated")
      #       p ["remote wait for"]
      #       val = remote.wait_for("Page.domContentEventFired")
      #       p ["domContentLoaded"]
      #       debug "domContentFired", val
      #     end
      #     get_document
      #   end
      # end
      # remote.on("Page.frameNavigated") do |params|
      #   debug "frame navigated", params
      # end
      # remote.on("Page.loadEventFired") do |params|
      #   debug "loadEventFired"
      #   debug html
      # end
    end

    def last_response
      @last_response
      # @responses[@last_navigate["loaderId"]] || {}
    end

    def last_response_or_err
      Timeout.timeout(Capybara.default_max_wait_time) do
        loop do
          remote.read_and_process
          break @last_response if @last_response
        end
      end
    rescue Timeout::Error
      raise Capybara::ExpectationNotMet
    end

    def status_code
      remote.wait_for("Network.responseReceived", Capybara.default_max_wait_time)
      last_response_or_err["status"]
    end

    def current_url
      wait_for_load
      # remote.wait_for("Network.responseReceived", 0.1)
      # last_response_or_err["url"]
      document_root["documentURL"]
    end


    def unrecognized_scheme_requests
      remote.read_and_process
      # sleep 0.01
      @unrecognized_scheme_requests
    end

    # def response_body
    #   val = remote.send_cmd "Network.getResponseBody", requestId: @last_navigate["loaderId"]
    #   debug val
    #   val["body"]
    # end

    # def wait_for_body
    #   debug
    #   Timeout.timeout(1) do
    #     loop do
    #       vv = nil
    #       tt = Benchmark.realtime do
    #         vv = remote.send_cmd("DOM.performSearch", query: "/html/body")
    #       end
    #       # p ["wait for body", vv, tt]
    #       remote.send_cmd!("DOM.discardSearchResults", searchId: vv["searchId"]) if vv
    #       if vv && vv["resultCount"] > 0
    #         break true
    #       end
    #       # vv = remote.send_cmd "DOM.querySelector", nodeId: id, selector: "body"
    #       # p ["query selector", vv]
    #       # if vv.nil? || vv["nodeId"] == 0
    #       #   sleep 0.01
    #       # end
    #       # break vv
    #     end
    #   end
    # rescue Timeout::Error
    #   nil
    # end

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
      debug
      Timeout.timeout(1) do
        loop do
          val = remote.send_cmd "DOM.getDocument"
          break val if has_body? val
        end
      end
      rescue Timeout::Error
        raise Capybara::ExpectationNotMet
      # debug "wait_for", Time.now.to_i
      # val = remote.wait_for "Page.loadEventFired"
      # debug "wait_for done", Time.now.to_i
      # unless wait_for_body
      #   p ["raising retry error"]
      #     raise Capybara::ExpectationNotMet
      # end
      # val = nil
      # debug "starting"
      # val = remote.send_cmd "DOM.getDocument"
      # debug "done #{val}"
      # @network_mutex.synchronize {}
      # p ["get document in sync"]
        # val = remote.send_cmd "DOM.getDocument"
        # val = remote.send_cmd "DOM.getDocument"
        # remote.wait_for "Page.loadEventFired"
      # end
      # if val["root"]["childNodeCount"] == 0
      #   p ["get document node count 0"]
      #   # raise RetryError
      #   # remote.wait_for "DOM.documentUpdated"
      #   remote.wait_for "Page.domContentEventFired"
      #   val = get_document
      # end
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
document_root
      # query.gsub!('"', '\"')
      # get_document
      # result = evaluate_script %( ChromeRemoteHelper.findCss("#{query}") )
      # return get_node_results result["result"]
      nodes = query_selector_all(query)
      nodes
    end

    def query_selector_all(query, index=nil)
document_root
wait_for_load
      p ["find_css", query, index]
      query.gsub!('"', '\"')
      result = if index
                 evaluate_script %( window.ChromeRemoteHelper && ChromeRemoteHelper.findCssWithin(#{index}, "#{query}") )
               else
                 evaluate_script %( window.ChromeRemoteHelper && ChromeRemoteHelper.findCss("#{query}") )
               end
      # info query, index, result
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
if vals.empty?
puts "empty result set"
end
      result.split(",").map do |id|
        Node.new driver, self, id.to_i
      end
    end

    def find_xpath(query, index=nil)
p ["find xpath", query, index]
document_root
      query.gsub!('"', '\"')
      result = if index
                 evaluate_script %( window.ChromeRemoteHelper && ChromeRemoteHelper.findXPathWithin(#{index}, "#{query}") )
               else
                 evaluate_script %( window.ChromeRemoteHelper && ChromeRemoteHelper.findXPath("#{query}") )
               end
      # info [query, index, result]
      get_node_results result
    end

    def title
      Timeout.timeout(1) do
        loop do
          get_document
          nodes = find_xpath("/html/head/title") rescue nil
          if nodes && nodes.any?
            break nodes[0].text
          else
            ""
          end
        end
      end
    rescue Timeout::Error
      ""
    end

    # def find_xpath(query)
    #   evaluate_script("$x(#{query})")
    # end
    # def find_xpath(query)
    #   # get_document
    #   val = remote.send_cmd("DOM.performSearch", query: query)
    #   debug val, query

    #   if val["resultCount"] == 0
    #     # raise RetryError.new
    #     return []
    #   end

    #   search_id = val["searchId"]
    #   val = remote.send_cmd("DOM.getSearchResults", searchId: search_id, fromIndex: 0, toIndex: val["resultCount"])
    #   debug 'search result', val
    #   if val.nil?
    #         # remote.wait_for("Page.lifecycleEvent") do |lcycle_params|
    #         #   # p ["wait for block called", lcycle_params["name"]]
    #         #   (lcycle_params["name"] == "load"  || lcycle_params["name"] == "networkIdle")# && params["loaderId"] == lcycle_params["loaderId"]
    #         # end
    #         # get_document
    #     raise Capybara::ExpectationNotMet?
    #   end
    #   # retry if val.nil?
    #   val["nodeIds"].map do |node_id|
    #     if node_id == 0
    #         # remote.wait_for("Page.lifecycleEvent") do |lcycle_params|
    #         #   # p ["wait for block called", lcycle_params["name"]]
    #         #   (lcycle_params["name"] == "load"  || lcycle_params["name"] == "networkIdle")# && params["loaderId"] == lcycle_params["loaderId"]
    #         # end
    #       raise Capybara::ExpectationNotMet
    #     end
    #     Node.new(@driver, self, node_id)
    #   end
    # # rescue => e
    # #   if e.message == "retry"
    # #     puts "RETRYING #{__method__}"
    # #     retry
    # #   else
    # #     raise e
    # #   end
    # ensure
    #   remote.send_cmd("DOM.discardSearchResults", searchId: search_id)
    # end

    # def html
    #   p ["html method"]
    #   val = remote.send_cmd "Network.getResponseBody", requestId: @last_navigate["loaderId"]
    #   val["body"]
    # end

    def start_remote
      # @remote = ChromeRemoteClient.new(::ChromeRemote.send(:get_ws_url, {host: "localhost", port: @chrome_port}))
      @remote = RDPClient.new chrome_host: @chrome_host, chrome_port: @chrome_port, browser: self
      remote.start
    end

    def after_remote_start
      remote.send_cmd "Page.setLifecycleEventsEnabled", enabled: true
      track_network_events
      enable_console_log
      enable_lifecycle_events
      enable_js_dialog
      enable_script_debug
      enable_network_interception
      set_viewport(width: 1680, height: 1050)
    end

    def set_viewport(width:, height:, device_scale_factor: 1, mobile: false)
      # remote.send_cmd("Emulation.clearDeviceMetricsOverride")
      remote.send_cmd("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: device_scale_factor, mobile: mobile)
    end

    def enable_network_interception
      remote.send_cmd "Network.setRequestInterception", patterns: [{urlPattern: "*"}]
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
      # remote.wait_for("Page.javascriptDialogOpening")
    end

    def enable_console_log
      remote.send_cmd "Console.enable"
      remote.on "Console.messageAdded" do |params|
         p ["console messageAdded", params]
        str = "#{params["message"]["source"]}:#{params["message"]["line"]} #{params["message"]["text"]}"
        if params["message"]["level"] == "error"
          @error_messages << str
        else
          @console_messages << str
        end
      end
    end

    def enable_lifecycle_events
      #return
      remote.on("Page.lifecycleEvent") do |params|
        p [:lifecycle, params]
        if params["name"] == "init"
          # @network_mutex.lock unless @network_mutex.locked?
        elsif params["name"] == "load"
          # p [:lifecycle_unlock]
          # @network_mutex.unlock if @network_mutex.locked?
        elsif params["name"] == "networkIdle"
          # @network_mutex.unlock if @network_mutex.locked?
          # p [:lifecycle_done]
        end
      end
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
        remote.send_cmd("Network.setUserAgentOverride", userAgent: value)
      else
        remote.send_cmd("Network.setExtraHTTPHeaders", headers: {key => value})
      end
    end

    def reset
      unset_root_node
      @responses.clear
      @last_response = nil
      # @loader_ids.clear
      @remote.listen_mutex.synchronize do
        @remote.handler_calls.clear
        @remote.response_messages.clear
        @remote.response_events.clear
        @remote.loader_ids.clear
      end
      @console_messages.clear
      @error_messages.clear
      @js_dialog_handlers.clear
      @unrecognized_scheme_requests.clear
      # remote.send_cmd "Page.close"
      remote.send_cmd "Network.clearBrowserCookies"
      remote.send_cmd "Runtime.discardConsoleEntries"
      visit "about:blank"
    end
  end

end
