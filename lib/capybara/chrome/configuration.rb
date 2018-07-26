module Capybara::Chrome
  class Configuration

    DEFAULT_ALLOWED_URLS = [
      %r(.*127\.0\.0\.1),
      %r(.*localhost),
      "data:*,*"
    ].freeze
    DEFAULT_MAX_WAIT_TIME = 10
    DEFAULT_DOWNLOAD_PATH = "/tmp"
    # set Capybara::Chrome::Configuration.chrome_port = 9222 for easy debugging
    DEFAULT_CHROME_PORT = nil
    DEFAULT_TRAP_INTERRUPT = true

    attr_accessor :max_wait_time, :download_path, :chrome_port, :trap_interrupt

    def initialize
      @allowed_urls = DEFAULT_ALLOWED_URLS.dup
      @blocked_urls = []
      @max_wait_time = DEFAULT_MAX_WAIT_TIME
      @download_path = DEFAULT_DOWNLOAD_PATH
      @chrome_port = DEFAULT_CHROME_PORT
      @trap_interrupt = DEFAULT_TRAP_INTERRUPT
    end

    def block_unknown_urls
      @block_unknown_urls = true
    end

    def allow_unknown_urls
      allow_url(/.*/)
    end

    def re_url(url)
      url.is_a?(Regexp) ? url : Regexp.new(Regexp.escape(url))
    end

    def allow_url(url)
      @allowed_urls << re_url(url)
    end

    def block_url(url)
      @blocked_urls << re_url(url)
    end

    def url_match?(pattern, url)
      pattern === url
    end

    def url_allowed?(url)
      @allowed_urls.detect {|pattern| url_match?(pattern, url)}
    end

    def block_url?(url)
      if url_allowed?(url)
        false
      else
        @block_unknown_urls || @blocked_urls.detect {|pattern| url_match?(pattern, url)}
      end
    end

    def skip_image_loading
      @skip_image_loading = true
    end

    def skip_image_loading?
      @skip_image_loading
    end

    def trap_interrupt?
      @trap_interrupt
    end

  end
end
