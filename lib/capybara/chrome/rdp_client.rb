module Capybara::Chrome

  # Chrome Remote Debugging Protocol (RDP) Client
  class RDPClient
    require "open-uri"

    include Debug
    include Service

    attr_reader :response_events, :response_messages, :loader_ids, :listen_mutex, :handler_calls, :ws, :handlers

    def initialize(chrome_host:, chrome_port:, browser:)
      @chrome_host = chrome_host
      @chrome_port = chrome_port
      @browser = browser
      @last_id = 0
      @ws = nil
      @ws_thread = nil
      @ws_mutex = Mutex.new
      @handlers = Hash.new { |hash, key| hash[key] = [] }
      @listen_thread = nil
      @listen_mutex = Mutex.new
      @response_messages = {}
      @response_events = []
      @read_mutex = Mutex.new
      @handler_mutex = Mutex.new
      @loader_ids = []
      @handler_calls = []
      # @fbr_bites = []
      # @fbr = Fiber.new { loop { if @fbr_bites.shift; Fiber.yield; else sleep 0.1; end } }
      @rp, @wp = IO.pipe
    end

    def generate_unique_id
      @last_id += 1
    end

    def send_cmd!(command, params={})
      debug command, params
      msg_id = generate_unique_id
      send_msg({method: command, params: params, id: msg_id}.to_json)
    end

    # Errno::EPIPE
    def send_cmd(command, params={})
      # read_and_process(0.01)
      msg_id = generate_unique_id

      # @read_mutex.synchronize do
      send_msg({method: command, params: params, id: msg_id}.to_json)
      # end

      debug "waiting #{command} #{msg_id}"
      msg = nil
      begin
        Timeout.timeout(Capybara::Chrome.configuration.max_wait_time) do
          until msg = @response_messages[msg_id]
            read_and_process
          end
        end
      rescue => e
        puts "#{command} #{params.inspect}"
        puts caller
        raise e
      end
      # puts "done waiting #{command} #{msg_id}. deleting"
      # p ["msg is", msg]

      # Thread.new do
      #   @listen_mutex.synchronize do
      #     @response_messages.delete msg_id
      #   end
      # end

      # p ["deleting response message done"]
      return msg["result"]

      # msg = read_until { |msg| msg["id"] == msg_id }
      # msg["result"]
    end

    def send_msg(msg)
      retries ||= 0
      ws.send_msg(msg)
    rescue Errno::EPIPE
      retries += 1
      stop_chrome
      start_chrome
      start
      retry if retries < 5 && !::RSpec.wants_to_quit
    end

    def on(event_name, &block)
      handlers[event_name] << block
    end

    def wait_for(event_name, timeout=Capybara.default_max_wait_time)
      # puts "wait for #{event_name}"
      # @listen_mutex.synchronize do
      # @response_events.clear
      # end
      msg = nil
      Timeout.timeout(timeout) do
        loop do
          msgs = @response_events.select {|v| v["method"] == event_name}
          if msgs.any?
            if block_given?
              do_return = msgs.detect do |m|
                val = yield m["params"]
                # if val
                #   msg = m.dup
                #   @response_events.delete m
                # end
                # val
              end
              if do_return
                msg = do_return.dup
                @listen_mutex.synchronize do
                  @response_events.delete do_return
                end
                break
              else
                # p "got msgs", msgs.size, msgs.map{|s| s["method"]}
                # sleep 0.05
                read_and_process
                next
              end
            else
              msg = msgs.first.dup
              @listen_mutex.synchronize do
                msgs.each {|m| @response_events.delete m}
              end
              break
            end
          else
            # p "got no msg - #{event_name}"
            # sleep 0.01
          end
          # sleep 0.05
          read_and_process
        end
      end
      # @response_events.clear
      return msg["params"]
    rescue Timeout::Error
      nil
    end

    # def setup_ws
    #   @ws_thread = Thread.new do
    #     @ws_mutex.synchronize do
    #       @ws = ::ChromeRemote::WebSocketClient.new(@ws_url)
    #     end
    #     loop do
    #       p ["parse input"]
    #       @ws.send :parse_input
    #     end
    #   end
    # end
    def process_messages
      # puts "ready"
      # events = []
      n = 0
      while @ws.messages.any? do
        n += 1
        # p ["some messages", @ws.messages.size]
        msg_raw = @ws.messages.shift
        if msg_raw
          msg = JSON.parse(msg_raw)
          # p "message #{msg["id"].inspect} #{msg["method"]} size #{@ws.messages.size}"
          if msg["method"]
            # p ["EVENT", msg["method"], msg["params"]["type"], msg["params"].fetch("request", {})["url"], msg["params"].fetch("response", {})["url"], "L", msg["params"]["loaderId"], "R", msg["params"]["requestId"], msg["params"]["type"], msg["params"]["name"]]
            # lid = msg["params"]["loaderId"]
            # if lid && !@loader_ids.include?(lid)
            #   params = msg["params"]
            #   p "New loader id #{msg["method"]} #{params["loaderId"]}"
            #   @loader_ids << lid
            # end
            # events << msg 
            hs = handlers[msg["method"]]
            if hs.any?
              # hs.each do |handler|
              #   handler.call(msg["params"])
              # end
              @handler_mutex.synchronize do
                @handler_calls << [msg["method"], msg["params"]]
                # @handler_calls << [hs, msg["params"]]
              end
            end
            # else
            @listen_mutex.synchronize do
              @response_events << msg
            end
            # end
          else
            # p ["writing to response_messages"]
            @listen_mutex.synchronize do

              @response_messages[msg["id"]] = msg
              if msg["exceptionDetails"]
                puts JSException.new(val["exceptionDetails"]["exception"].inspect)
                # raise JSException.new(val["exceptionDetails"]["exception"].inspect)
              end
            end
            # p ["writing to response_messages done"]
          end
        else
          p ["no msg_raw", msg_raw]
        end
      end
      # events.each do |emsg|
      #   handlers[emsg["method"]].each do |handler|
      #     handler.call(emsg["params"])
      #   end
      # end
      n
    end

    def drain_messages
      if !@draining
        @draining = true
        while IO.select [@rp], [], [], 0.001
          @rp.gets
        end
        @draining = false
      end
    end

    def read_and_process(timeout=0)
      return unless Thread.current == Thread.main
      ready = select [@ws.socket.io], [], [], timeout
      if ready
        # @read_mutex.synchronize do
        # puts "done select"
        @ws.send :parse_input
        # puts "done parse"
        process_messages
      end
      # drain_messages
      if !@calling_handlers
        # @fbr.resume if @fbr.alive?
        @calling_handlers = true
        while obj = @handler_calls.shift do
          handlers[obj[0]].each {|h| h.call obj[1]}
        end
        # @handler_calls.each_with_index.map do |obj, i|
        # @handler_mutex.synchronize do
        # job_ids = @handler_calls.each_with_index.map do |obj, i|
          # obj[0].each {|h| h.call obj[1]}
          # handlers[obj[0]].each {|h| h.call obj[1]}
          # i
        # end
          # # puts "DELETING #{job_ids.inspect}" if job_ids.any?
          # job_ids.each {|i| @handler_calls.delete_at i}
          # # @handler_calls.delete jobs
        # end
        @calling_handlers = false
      end
      # if !@listen_thread
      #   @listen_thread = Thread.new do
      #     loop do
      #     ready = select [@ws.socket.io], [], [], timeout
      #     if ready
      #     # @read_mutex.synchronize do
      #       # puts "done select"
      #       @ws.send :parse_input
      #       # puts "done parse"
      #       process_messages
      #     end
      #     end
      #   end
      # end
    end

    def discover_ws_url
      response = open("http://#{@chrome_host}:#{@chrome_port}/json")
      data = JSON.parse(response.read)
      first_page = data.detect {|e| e["type"] == "page"}
      @ws_url = first_page["webSocketDebuggerUrl"]
    end

    def start
      wait_for_chrome
      discover_ws_url
      @ws = RDPWebSocketClient.new @ws_url
      send_cmd "Network.enable"
      send_cmd "Network.clearBrowserCookies"
      send_cmd "Page.enable"
      send_cmd "DOM.enable"
      send_cmd "CSS.enable"
      send_cmd "Page.setDownloadBehavior", behavior: "allow", downloadPath: Capybara::Chrome.configuration.download_path
      helper_js = File.expand_path(File.join("..", "..", "chrome_remote_helper.js"), File.dirname(__FILE__))
      send_cmd "Page.addScriptToEvaluateOnNewDocument", source: File.read(helper_js)
      @browser.after_remote_start

      Thread.abort_on_exception = true
      return
      # setup_ws
      # @ws_mutex.synchronize {}
      @listen_thread = Thread.new do
        # p ["new thread"]
        loop do
          # puts "in looP"
          select [@ws.socket.io]
          # @read_mutex.synchronize do
          # puts "done select"
          @ws.send :parse_input
          # puts "done parse"
          nn = process_messages
          # @fbr_bites << true
          # puts "size #{nn}"
          @wp.puts 1 if nn > 0
        end
        # listen_until do |msg|
        #   p ["got msg", msg]
        #   continue unless msg
        #   false
        # end
      end
    end
  end

end
