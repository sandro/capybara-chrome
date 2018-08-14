module Capybara::Chrome
  module Service

    CHROME_ARGS = [
      "--headless",
      "--disable-gpu",
      "--crash-dumps-dir=/tmp",
      '--js-flags="--max-old-space-size=500"',
      "--hide-scrollbars",
      "--mute-audio",
      "--disable-dev-shm-usage",
      "--disable-hang-monitor",
      "--disable-extensions",
    ]

    def start_chrome
      return if chrome_running?
      info "Starting Chrome", chrome_path, chrome_args
      @chrome_pid = Process.spawn chrome_path, *chrome_args
      at_exit { stop_chrome }
    end

    def stop_chrome
      Process.kill "TERM", @chrome_pid rescue nil
    end

    def restart_chrome
      stop_chrome
      if chrome_running?
        @chrome_port = find_available_port(@chrome_host)
      end
      start_chrome
    end

    def wait_for_chrome
      running = false
      while !running
        running = chrome_running?
        sleep 0.02
      end
    end

    def chrome_running?
      socket = TCPSocket.new(@chrome_host, @chrome_port) rescue false
      socket.close if socket
      !!socket
    end

    def chrome_path
      case os
      when :macosx
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
      when :linux
        # /opt/google/chrome/chrome
        "google-chrome-stable"
      end
    end

    def chrome_args
      CHROME_ARGS + ["--remote-debugging-port=#{@chrome_port}"]
    end

    def os
      @os ||= (
        host_os = RbConfig::CONFIG['host_os']
        case host_os
        when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
          :windows
        when /darwin|mac os/
          :macosx
        when /linux/
          :linux
        when /solaris|bsd/
          :unix
        else
          raise Error::WebDriverError, "unknown os: #{host_os.inspect}"
        end
      )
    end

    def find_available_port(host)
      sleep rand * 0.7 # slight delay to account for concurrent browsers
      server = TCPServer.new(host, 0)
      server.addr[1]
    ensure
      server.close if server
    end

  end
end
