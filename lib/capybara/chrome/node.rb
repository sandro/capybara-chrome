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
      # @lookup_path = lookup_path
    end

    def html
      # puts "IN HTML"
      browser.evaluate_script %(
        ChromeRemoteHelper.waitDOMContentLoaded();
        ChromeRemoteHelper.onSelfValue(#{id}, "outerHTML");
      )
      # puts "IN HTML DONE JS"
      # vv = on_self_value %(return this.innerHTML)
      # puts "html is #{vv}"
      # outer = send_cmd "DOM.getOuterHTML", nodeId: id
      # debug ["get Outer", outer.nil?, outer.class, id]
      # if outer.nil?
      #   p "NO HTML"
      #   return ""
      # end
      # outer["outerHTML"]
      # debug id, outer["outerHTML"].to_s.size
      # (outer||{})["outerHTML"].to_s
      # outer["outerHTML"]
    end

    def all_text
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
      debug visible?
      if visible?
        text
      else
        ""
      end
    end

    def text
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
      # box = send_cmd "DOM.getBoxModel", nodeId: id
      # b = box["model"]["border"]
      # x = [b[0], b[2], b[4], b[6]].min
      # y = [b[1], b[3], b[5], b[7]].min
      # width = [b[0], b[2], b[4], b[6]].max - x
      # height = [b[1], b[3], b[5], b[7]].max - y
      # {x: x, y: y, width: width, height: height}
      # val = on_self_value %( return ChromeRemoteHelper.getDimensions(this) ), awaitPromise: true
      browser.evaluate_script %( ChromeRemoteHelper.waitWindowLoaded() )
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
      # val = on_self_value("this.focus(); this.click(); return 'clicked'")
      # debug val
      # on_self %(
      #   this.dataset.chromeRemoteClicked = false;
      #   var fn = function() {
      #     this.dataset.chromeRemoteClicked = true;
      #     this.removeEventListener("click", fn);
      #   }.bind(this);
      #   this.addEventListener("click", fn);
      # )
      browser.evaluate_script %( ChromeRemoteHelper.attachClickListener(#{id}) )
      browser.with_retry do
        on_self("this.scrollIntoViewIfNeeded();");
        dim = get_dimensions
        # p dim
        raise Capybara::ExpectationNotMet if dim["width"] == 0 && dim["height"] == 0
        # cx = (dim["x"] + dim["width"]/2).floor
        # cy = (dim["y"] + dim["height"]/2 ).floor
        xd = [1, dim["width"]/2, dim["width"]/3]
        yd = [1, dim["height"]/2, dim["height"]/3]
        strategy = rand(0..xd.size-1)
        cx = (dim["x"] + xd[strategy]).floor
        cy = (dim["y"] + yd[strategy]).floor
        move_mouse(cx, cy, steps: 0)
        expect_node_at_position(cx, cy)
        send_cmd! "Input.dispatchMouseEvent", type: "mousePressed", x: cx, y: cy, clickCount: 1, button: "left"
        send_cmd! "Input.dispatchMouseEvent", type: "mouseReleased", x: cx, y: cy, clickCount: 1, button: "left"
        clicked = browser.evaluate_script %( ChromeRemoteHelper.nodeVerifyClicked(#{id}) )
        # p ["CLICKED", clicked]
        raise Capybara::ExpectationNotMet unless clicked
      end
    end

    def find_css(query)
      # p ["find_css embedded", query]
      # info "node", query, id
      # val = on_self %(
      #   return this.querySelector("#{query}");
      # )
      # debug val
      # node = request_node(val["objectId"])
      # [Node.new(@driver, @browser, node["nodeId"])]
      browser.query_selector_all(query, id)
    end

    def find_xpath(query)
      # info "node", query, id
      browser.find_xpath query, id
      # p ["find_xpath embedded", query, tag_name]
      # query.gsub!('"', '\"')
      # browser.get_node_results on_self %( return ChromeRemoteHelper.findXPath("#{query}", this) )

      # val = on_self %(
      #   return ChromeRemoteHelper.findXPath("#{query}", this)
      # )
      # browser.request_nodes(val["objectId"])
      # debug "embedded", query, get_xpath
      # browser.find_xpath(query, path)
      # val = send_cmd("DOM.performSearch", query: "#{get_xpath}/#{query}")
      # p ['search', val]
      # search_id = val["searchId"]
      # val = send_cmd("DOM.getSearchResults", searchId: search_id, fromIndex: 0, toIndex: val["resultCount"])
      # p ['search result', val]
      # val["nodeIds"].map do |node_id|
      #   Node.new(@driver, @browser, node_id)
      # end
    # ensure
      # send_cmd("DOM.discardSearchResults", searchId: search_id)
    end

    def path
      browser.evaluate_script %( ChromeRemoteHelper.nodePathForNode(#{id}) )
      # on_self_value %( return ChromeRemoteHelper.pathForNode(this) )
      # on_self_value %(
      #   this.getXPathNode = function(node, path) {
      #     var path = path || [];
      #     if (node.parentNode) {
      #       path = this.getXPathNode(node.parentNode, path);
      #     }

      #     var first = node;
      #     while (first.previousSibling)
      #       first = first.previousSibling;

      #     var count = 0;
      #     var index = 0;
      #     var iter = first;
      #     while (iter) {
      #       if (iter.nodeType == 1 && iter.nodeName == node.nodeName)
      #         count++;
      #       if (iter.isSameNode(node))
      #          index = count;
      #       iter = iter.nextSibling;
      #       continue;
      #     }

      #     if (node.nodeType == 1)
      #       path.push(node.nodeName.toLowerCase() + (node.id ? "[@id='"+node.id+"']" : count > 1 ? "["+index+"]" : ''));

      #     return path;
      #   }
      #   return "/" + this.getXPathNode.call(this, this).join("/");
      # )
    end
    alias get_xpath path

    def disabled?
      # val = on_self_value "return this.disabled"
      val = browser.evaluate_script %( ChromeRemoteHelper.onSelfValue(#{id}, "disabled") )
      debug val
      val
    end

    TEXT_TYPES = %w(date email number password search tel text textarea url)
    def set(value, options={})
      value = value.to_s.gsub('"', '\"')
      # p ["set", value, options, node_description]
      # info value, options
      # on_self_value("return this.value")
      # type = on_self_value %( return (this.type || this.tagName).toLowerCase(); )
      type = browser.evaluate_script %( ChromeRemoteHelper.nodeSetType(#{id}) )
      # p ["TYPE", type, value]

      if type == "file"
        send_cmd "DOM.setFileInputFiles", files: [value.to_s], nodeId: node_id
      elsif TEXT_TYPES.include?(type)
        script = "this.value = ''; this.focus();"
        if value.blank?
          script << %(ChromeRemoteHelper.dispatchEvent(this, "change"))
        end
        # p script
        on_self script
        type_string(value.to_s)
      else
        browser.evaluate_script %( ChromeRemoteHelper.nodeSet(#{id}, "#{value}", "#{type}") )
      end


      # value = *[value].flatten
      # desc = node_description["node"]
      # if desc["localName"] == "input"
      # res = browser.execute_script %( ChromeRemoteHelper.onSelf(#{id}, "return (this.type || this.tagName).toLowerCase();") )
      # type = res["result"]["value"]
      #   info type
      #   if type == "checkbox" || type == "radio"
      #     on_self! %(
      #       if (#{value} && !this.checked) {
      #         return this.click();
      #       } else if (!#{value} && this.checked) {
      #         return this.click();
      #       }
      #     )
      #   elsif type == "file"
      #     send_cmd "DOM.setFileInputFiles", files: [value.to_s], nodeId: node_id
      #     # on_self "this.innerHTML = '#{value}'"
      #   elsif TEXT_TYPES.include?(type)
      #     focus
      #     on_self_value "this.value = ''; return this.value"
      #     if value.to_s == ""
      #       trigger("change")
      #     else
      #       type_string(value.to_s)
      #     end
      #   else
      #     p ["SET ELSE", tag_name, type, value]
      #     on_self_value %(this.value = "#{value.to_s.gsub('"', '\"')}"; return this.value)
      #   end
      # end
      # on_self_value %(
      #   var type = (this.type || this.tagName).toLowerCase();
      #   if (type == "checkbox" || type == "radio") {
      #     return this.click()
      #   } else {
      #     return this.value = "#{value}"
      #   }
      # )
    end

    def node_id
      browser.get_document
      val = browser.execute_script %(ChromeRemoteHelper.onSelf(#{id}, "return this;"))
      send_cmd("DOM.requestNode", objectId: val["result"]["objectId"])["nodeId"]
    end

    def type_string(string)
      ary = string.chars
      # if ary.empty?
      #   send_cmd! "Input.dispatchKeyEvent", {type: "keyDown", code: "Delete"}
      #   send_cmd! "Input.dispatchKeyEvent", {type: "keyUp"}
      # else
        ary.each do |char|
          char.tr!("\n", "\r")
          send_cmd! "Input.dispatchKeyEvent", {type: "keyDown", text: char}
          send_cmd! "Input.dispatchKeyEvent", {type: "keyUp"}
        end
      # end
    end

    def send_keys(*args)
      raise "i dunno"
    end

    def focus
      # on_self "return this.focus()"
      val = browser.evaluate_script %( ChromeRemoteHelper.onSelfValue(#{id}, "focus") )
    end

    def value(*args)
      debug args
      # on_self_value("return this.value")
      val = browser.evaluate_script %( ChromeRemoteHelper.onSelfValue(#{id}, "value") )
    end

    def checked?
      # on_self_value("return this.checked")
      val = browser.evaluate_script %( ChromeRemoteHelper.onSelfValue(#{id}, "checked") )
    end

    def selected?
      # on_self_value("return this.selected")
      val = browser.evaluate_script %( ChromeRemoteHelper.onSelfValue(#{id}, "selected") )
    end

    def disabled?
      # on_self_value("return this.disabled")
      val = browser.evaluate_script %( ChromeRemoteHelper.onSelfValue(#{id}, "disabled") )
    end

    def select_option(*args)
      # debug args, node_description
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
      # desc = node_description["node"]
      # name_index = desc["attributes"].index(attr.to_s)
      # desc["attributes"][name_index+1] if name_index
    end

    def node_description
      # return @node_description if @node_description
      @node_description = send_cmd("DOM.describeNode", nodeId: id)
      debug ["node_desc", @node_description, id]
      if @node_description.nil?
        # browser.remote.wait_for("Page.lifecycleEvent") do |lcycle_params|
        #   # p ["wait for block called", lcycle_params["name"]]
        #   (lcycle_params["name"] == "load"  || lcycle_params["name"] == "networkIdle")# && params["loaderId"] == lcycle_params["loaderId"]
        # end
        # browser.get_document
          raise Capybara::ExpectationNotMet
      end
      @node_description
    # rescue => e
    #   if e.message == "retry"
    #     puts "RETRYING #{__method__}"
    #     retry
    #   else
    #     raise e
    #   end
    end

    def tag_name
      # node_description["node"]["localName"]
      on_self_value("return this.tagName.toLowerCase()")
    end
    alias local_name tag_name

    # def nodeDescription
    #   browser.describe_node(id)
    # end

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
      browser.evaluate_script %(ChromeRemoteHelper.onSelf(#{id}, "#{function_body}"))
      # val = send_cmd("Runtime.callFunctionOn", {functionDeclaration: "function() {#{function_body}}", objectId: remote_object_id, awaitPromise: true}.merge(options))
      # debug val, function_body
      # if val.nil?
      #   raise Capybara::ExpectationNotMet
      # elsif val["exceptionDetails"]
      #   raise JSException.new(val["exceptionDetails"]["exception"].inspect)
      # end
      # # p ["result is", val, function_body]
      # val["result"]
    end

    def on_self!(function_body, options={})
      function_body = function_body.gsub('"', '\"').gsub(/\s+/, " ")
      browser.execute_script! %(ChromeRemoteHelper.onSelf(#{id}, "#{function_body}"))
      # send_cmd!("Runtime.callFunctionOn", functionDeclaration: "function() {#{function_body}}", objectId: remote_object_id)
    end

    def remote_object_id
      remote_object["object"]["objectId"]
    end

    def remote_object
      return @remote_object if @remote_object
      @remote_object = send_cmd("DOM.resolveNode", nodeId: id)
      debug @remote_object, id
      if @remote_object.nil?
        # browser.remote.wait_for("Page.lifecycleEvent") do |lcycle_params|
        #   # p ["wait for block called", lcycle_params["name"]]
        #   (lcycle_params["name"] == "load"  || lcycle_params["name"] == "networkIdle")# && params["loaderId"] == lcycle_params["loaderId"]
        # end
        # browser.get_document
          raise Capybara::ExpectationNotMet
      end
      @remote_object
      # send_cmd("DOM.resolveNode", nodeId: id)
    # rescue => e
    #   if e.message == "retry"
    #     puts "RETRYING #{__method__}"
    #     retry
    #   else
    #     raise e
    #   end
    end

    def request_node(remote_object_id)
      @request_node ||= send_cmd("DOM.requestNode", objectId: remote_object_id)
    end
  end

end
