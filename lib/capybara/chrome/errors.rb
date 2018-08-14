module Capybara::Chrome

  class Error < StandardError
  end

  class JSException < Error
  end

  class ResponseTimeoutError < Error
  end

end
