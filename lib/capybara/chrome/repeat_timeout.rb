module Capybara::Chrome
  module DumbTimeout
    class Error < StandardError
    end

    def self.timeout(n)
      start_at = Time.now
      loop do
        raise Error.new("waited #{n}s") if (Time.now - start_at).to_i >= n
        yield
      end
    end

  end
end
