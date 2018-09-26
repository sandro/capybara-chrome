module Capybara::Chrome

  # Chrome Remote Debugging Protocol (RDP) Client
  class RDPClient
    require "open-uri"

    include Debug

    attr_reader :response_events, :response_messages, :loader_ids, :listen_mutex, :handler_calls, :ws, :handlers, :browser

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
      @rp, @wp = IO.pipe
    end

    def reset
      @calling_handlers = false
      response_messages.clear
      response_events.clear
      loader_ids.clear
    end

    def generate_unique_id
      @last_id += 1
    end

    def send_cmd!(command, params={})
      debug command, params
      msg_id = generate_unique_id
      send_msg({method: command, params: params, id: msg_id}.to_json)
      msg_id
    end

    # Errno::EPIPE
    def send_cmd(command, params={})
      msg_id = send_cmd!(command, params)

      debug "waiting #{command} #{msg_id}"
      msg = nil
      begin
        until msg = @response_messages[msg_id]
          read_and_process(1)
        end
        @response_messages.delete msg_id
      rescue Timeout::Error
        puts "TimeoutError #{command} #{params.inspect} #{msg_id}"
        send_cmd! "Runtime.terminateExecution"
        puts "Recovering"
        recover_chrome_crash
        raise ResponseTimeoutError
      rescue WebSocketError => e
        puts "send_cmd received websocket error #{e.inspect}"
        recover_chrome_crash
        raise e
      rescue Errno::EPIPE, EOFError => e
        puts "send_cmd received EPIPE or EOF error #{e.inspect}"
        recover_chrome_crash
        raise e
      rescue => e
        puts "send_cmd caught error #{e.inspect} when issuing #{command} #{params.inspect}"
        puts caller
        raise e
      end
      return msg["result"]
    end

    def recover_chrome_crash
      $stderr.puts "Chrome Crashed... #{Capybara::Chrome.wants_to_quit.inspect} #{::RSpec.wants_to_quit.inspect}" unless Capybara::Chrome.wants_to_quit
      browser.restart_chrome
      browser.start_remote
      # @chrome_port = browser.chrome_port
      # start
    end

    def send_msg(msg)
      retries ||= 0
      ws.send_msg(msg)
    rescue Errno::EPIPE, EOFError => exception
      retries += 1
      recover_chrome_crash
      if retries < 5 && !::Capybara::Chrome.wants_to_quit
        retry
      else
        raise exception
      end
    end

    def on(event_name, &block)
      handlers[event_name] << block
    end

    def wait_for(event_name, timeout=Capybara.default_max_wait_time)
      @response_events.clear
      msg = nil
      loop do
        msgs = @response_events.select {|v| v["method"] == event_name}
        if msgs.any?
          if block_given?
            do_return = msgs.detect do |m|
              val = yield m["params"]
            end
            if do_return
              msg = do_return.dup
              @response_events.delete do_return
              break
            else
              read_and_process(1)
              next
            end
          else
            msg = msgs.first.dup
            msgs.each {|m| @response_events.delete m}
            break
          end
        else
        end
        read_and_process(1)
      end
      return msg && msg["params"]
    rescue Timeout::Error
      puts "WAIT_FOR TIMED OUT"
      nil
    end

    def process_messages
      n = 0
      while @ws.messages.any? do
        n += 1
        msg_raw = @ws.messages.shift
        if msg_raw
          msg = JSON.parse(msg_raw)
          if msg["method"]
            hs = handlers[msg["method"]]
            if hs.any?
              @handler_calls << [msg["method"], msg["params"]]
            end
            @response_events << msg
          else
            @response_messages[msg["id"]] = msg
            if msg["exceptionDetails"]
              puts JSException.new(val["exceptionDetails"]["exception"].inspect)
            end
          end
        else
          p ["no msg_raw", msg_raw]
        end
      end
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
        @ws.parse_input
        process_messages
      end
      if !@calling_handlers
        @calling_handlers = true
        while obj = @handler_calls.shift do
          handlers[obj[0]].each {|h| h.call obj[1]}
        end
        @calling_handlers = false
      end
    end

    def discover_ws_url
      response = open("http://#{@chrome_host}:#{@chrome_port}/json")
      data = JSON.parse(response.read)
      puts "data is #{response.inspect} #{data.inspect}"
      first_page = data.detect {|e| e["type"] == "page"}
      @ws_url = first_page["webSocketDebuggerUrl"]
    end

    def start
      browser.wait_for_chrome
      browser.with_retry do
        discover_ws_url
      end
      @ws = RDPWebSocketClient.new @ws_url
      send_cmd! "Network.enable"
      send_cmd! "Network.clearBrowserCookies"
      send_cmd! "Page.enable"
      send_cmd! "DOM.enable"
      send_cmd! "CSS.enable"
      send_cmd! "Page.setDownloadBehavior", behavior: "allow", downloadPath: Capybara::Chrome.configuration.download_path
      helper_js = File.expand_path(File.join("..", "..", "chrome_remote_helper.js"), File.dirname(__FILE__))
      send_cmd! "Page.addScriptToEvaluateOnNewDocument", source: File.read(helper_js)

      Thread.abort_on_exception = true
      return
      @listen_thread = Thread.new do
        loop do
          select [@ws.socket.io]
          @ws.send :parse_input
          nn = process_messages
          @wp.puts 1 if nn > 0
        end
      end
    end
  end

end
