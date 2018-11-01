module Capybara::Chrome
  class Node < ::Capybara::Driver::Node
    include Debug
    attr_reader :browser, :id

    def initialize(driver, browser, id)
      raise "hell" if id == 0
      @driver = driver
      @browser = browser
      @id = id
      @mouse_x = 0
      @mouse_y = 0
    end

    def html
      browser.evaluate_script %( ChromeRemoteHelper.waitDOMContentLoaded(); )
      browser.evaluate_script %( ChromeRemoteHelper.onSelfValue(#{id}, "outerHTML") )
    end

    def all_text
      browser.evaluate_script %( ChromeRemoteHelper.waitDOMContentLoaded(); )
      text = browser.evaluate_script %( ChromeRemoteHelper.onSelfValue(#{id}, "textContent") )
      if Capybara::VERSION.to_f < 3.0
        Capybara::Helpers.normalize_whitespace(text)
      else
        text.gsub(/[\u200b\u200e\u200f]/, '')
          .gsub(/[\ \n\f\t\v\u2028\u2029]+/, ' ')
          .gsub(/\A[[:space:]&&[^\u00a0]]+/, "")
          .gsub(/[[:space:]&&[^\u00a0]]+\z/, "")
          .tr("\u00a0", ' ')
      end
    end

    def visible_text
      raw_text.to_s.gsub(/\ +/, ' ')
        .gsub(/[\ \n]*\n[\ \n]*/, "\n")
        .gsub(/\A[[:space:]&&[^\u00a0]]+/, "")
        .gsub(/[[:space:]&&[^\u00a0]]+\z/, "")
        .tr("\u00a0", ' ')
    end
    alias text visible_text

    def raw_text
      browser.evaluate_script %( ChromeRemoteHelper.nodeText(#{id}) )
    end

    def visible?
      browser.evaluate_script %( ChromeRemoteHelper.nodeVisible(#{id}) )
    end

    def is_connected?
      # on_self_value %( return this.isConnected )
      val = browser.evaluate_script %( ChromeRemoteHelper.onSelfValue(#{id}, "isConnected") )
    end

    def get_dimensions
      browser.wait_for_load
      val = browser.evaluate_script %( ChromeRemoteHelper.nodeGetDimensions(#{id}) )
      val = JSON.parse(val) rescue {}
      val
    end

    def expect_node_at_position(x,y)
      in_position = browser.evaluate_script %( ChromeRemoteHelper.nodeIsNodeAtPosition(#{id}, {relativeX: #{x}, relativeY: #{y}}) )
      if !in_position
        raise "Element '<#{tag_name}>' not at expected position: #{x},#{y}"
      end
    end

    def move_mouse(x, y, steps: 1)
      if steps >= 1
        (0..x).step(steps).each do |dx|
          send_cmd! "Input.dispatchMouseEvent", type: "mouseMoved", x: dx, y: 0
        end
        (0..y).step(steps).each do |dy|
          send_cmd! "Input.dispatchMouseEvent", type: "mouseMoved", x: x, y: dy
        end
      end
      send_cmd! "Input.dispatchMouseEvent", type: "mouseMoved", x: x, y: y
    end

    def click
      browser.with_retry do
        on_self("this.scrollIntoViewIfNeeded();");
        dim = get_dimensions
        if dim["width"] == 0 && dim["height"] == 0
          puts "DIM IS 0"
          puts html
          raise Capybara::ElementNotFound
        end
        xd = [1, dim["width"]/2, dim["width"]/3]
        yd = [1, dim["height"]/2, dim["height"]/3]
        strategy = rand(0..xd.size-1)
        cx = (dim["x"] + xd[strategy]).floor
        cy = (dim["y"] + yd[strategy]).floor
        move_mouse(cx, cy, steps: 0)
        expect_node_at_position(cx, cy)
        send_cmd! "Input.dispatchMouseEvent", type: "mousePressed", x: cx, y: cy, clickCount: 1, button: "left"
        send_cmd! "Input.dispatchMouseEvent", type: "mouseReleased", x: cx, y: cy, clickCount: 1, button: "left"
        vv = browser.wait_for_load
      end
    end

    def find_css(query)
      browser.query_selector_all(query, id)
    end

    def find_xpath(query)
      browser.find_xpath query, id
    end

    def path
      browser.evaluate_script %( ChromeRemoteHelper.nodePathForNode(#{id}) )
    end
    alias get_xpath path

    def disabled?
      val = browser.evaluate_script %( ChromeRemoteHelper.onSelfValue(#{id}, "disabled") )
      debug val
      val
    end

    TEXT_TYPES = %w(date email number password search tel text textarea url)
    def set(value, options={})
      value = value.to_s.gsub('"', '\"')
      type = browser.evaluate_script %( ChromeRemoteHelper.nodeSetType(#{id}) )

      if type == "file"
        send_cmd "DOM.setFileInputFiles", files: [value.to_s], nodeId: node_id
      elsif TEXT_TYPES.include?(type)
        script = "this.value = ''; this.focus();"
        if value.blank?
          script << %(ChromeRemoteHelper.dispatchEvent(this, "change"))
        end
        on_self script
        type_string(value.to_s)
      else
        browser.evaluate_script %( ChromeRemoteHelper.nodeSet(#{id}, "#{value}", "#{type}") )
      end
    end

    def node_id
      browser.get_document
      val = browser.execute_script %(ChromeRemoteHelper.onSelf(#{id}, "return this;"))
      send_cmd("DOM.requestNode", objectId: val["result"]["objectId"])["nodeId"]
    end

    def type_string(string)
      ary = string.chars
      ary.each do |char|
        char.tr!("\n", "\r")
        send_cmd! "Input.dispatchKeyEvent", {type: "keyDown", text: char}
        send_cmd! "Input.dispatchKeyEvent", {type: "keyUp"}
      end
    end

    def send_keys(*args)
      raise "i dunno"
    end

    def focus
      val = browser.evaluate_script %( ChromeRemoteHelper.onSelfValue(#{id}, "focus") )
    end

    def value(*args)
      debug args
      val = browser.evaluate_script %( ChromeRemoteHelper.onSelfValue(#{id}, "value") )
    end

    def checked?
      val = browser.evaluate_script %( ChromeRemoteHelper.onSelfValue(#{id}, "checked") )
    end

    def selected?
      val = browser.evaluate_script %( ChromeRemoteHelper.onSelfValue(#{id}, "selected") )
    end

    def disabled?
      val = browser.evaluate_script %( ChromeRemoteHelper.onSelfValue(#{id}, "disabled") )
    end

    def select_option(*args)
      on_self_value %(
        if (this.disabled)
          return;

        var selectNode = this.parentNode;
        ChromeRemoteHelper.dispatchEvent(selectNode, "mousedown");
        selectNode.focus();
        ChromeRemoteHelper.dispatchEvent(selectNode, "input");

        if (!this.selected) {
          this.selected = true;
          ChromeRemoteHelper.dispatchEvent(this, "change");
        }

        ChromeRemoteHelper.dispatchEvent(selectNode, "mouseup");
        ChromeRemoteHelper.dispatchEvent(selectNode, "click");
      )
    end

    def trigger(event_name)
      on_self %( ChromeRemoteHelper.dispatchEvent(this, '#{event_name}') )
    end

    def method_missing(method, *args)
      debug ["method missing", method, args]
      raise "method midding #{method}"
    end

    def [](attr)
      on_self_value %(return this.getAttribute("#{attr}") )
    end

    def node_description
      # return @node_description if @node_description
      @node_description = send_cmd("DOM.describeNode", nodeId: id)
      debug ["node_desc", @node_description, id]
      if @node_description.nil?
        raise Capybara::ExpectationNotMet
      end
      @node_description
    end

    def tag_name
      # node_description["node"]["localName"]
      on_self_value("return this.tagName.toLowerCase()")
    end
    alias local_name tag_name

    def send_cmd(cmd, args={})
      browser.remote.send_cmd(cmd, args)
    end
    def send_cmd!(cmd, args={})
      browser.remote.send_cmd!(cmd, args)
    end

    def on_self_value(function_body, options={})
      function_body = function_body.gsub('"', '\"').gsub(/\s+/, " ")
      browser.evaluate_script %(ChromeRemoteHelper.onSelf(#{id}, "#{function_body}"))
    end

    def on_self(function_body, options={})
      function_body = function_body.gsub('"', '\"').gsub(/\s+/, " ")
      browser.evaluate_script %( window.ChromeRemoteHelper && ChromeRemoteHelper.waitDOMContentLoaded(); )
      browser.evaluate_script %(window.ChromeRemoteHelper && ChromeRemoteHelper.onSelf(#{id}, "#{function_body}"))
    end

    def on_self!(function_body, options={})
      function_body = function_body.gsub('"', '\"').gsub(/\s+/, " ")

      browser.evaluate_script %( ChromeRemoteHelper.waitDOMContentLoaded(); )

      browser.execute_script! %(ChromeRemoteHelper.onSelf(#{id}, "#{function_body}"))
    end

    def remote_object_id
      remote_object["object"]["objectId"]
    end

    def remote_object
      return @remote_object if @remote_object
      @remote_object = send_cmd("DOM.resolveNode", nodeId: id)
      debug @remote_object, id
      if @remote_object.nil?
        raise Capybara::ExpectationNotMet
      end
      @remote_object
    end

    def request_node(remote_object_id)
      @request_node ||= send_cmd("DOM.requestNode", objectId: remote_object_id)
    end
  end

end
