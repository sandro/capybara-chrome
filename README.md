# Capybara::Chrome

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/capybara/chrome`. To experiment with that code, run `bin/console` for an interactive prompt.

TODO: Delete this and the text above, and describe your gem

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'capybara-chrome'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install capybara-chrome

## Usage

The standard port for the debugging protocol is `9222`. Visit `localhost:9222` in a Chrome tab to watch the tests execute. Note, the port will be random when using Specjour.

### Debugging

Use `byebug` instead of `binding.pry` when debugging a test. The Pry debugger tends to hang when `visit` is called.

### Using the repl

You can use the capybara-chrome browser without providing a rack app. This can be helpful in debugging.

```
[2] pry(main)> driver = Capybara::Chrome::Driver.new(nil, port:9222); driver.start; browser = driver.browser
[3] pry(main)> browser.visit "http://google.com"
=> true
[4] pry(main)> browser.current_url
=> "https://www.google.com/?gws_rd=ssl"
[5] pry(main)>

```

Further, you can run a local netcat server and point the capybara-chrome browser to it to see the entire request that's being sent.

Terminal one contains the browser:

```
[1] pry(main)> driver = Capybara::Chrome::Driver.new(nil, port:9222); driver.start; browser = driver.browser
[2] pry(main)> browser.header "x-foo", "bar"
[3] pry(main)> browser.visit "http://localhost:8000"
```

Terminal two prints the request

```
$ while true; do { echo -e "HTTP/1.1 200 OK \r\n"; echo "hi"; } | nc -l 8000; done
GET / HTTP/1.1
Host: localhost:8000
Connection: keep-alive
Upgrade-Insecure-Requests: 1
User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/68.0.3440.106 Safari/537.36
x-foo: bar
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8
Accept-Encoding: gzip, deflate
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/carezone/capybara-chrome.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
