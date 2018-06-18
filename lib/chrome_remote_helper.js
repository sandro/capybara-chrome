window.ChromeRemoteHelper = {
  DOMContentLoaded: false,
  windowLoaded: false,
  nextIndex: 0,
  nodes: {},
  nodeClicks: {},
  TEXT_TYPES: ["date", "email", "number", "password", "search", "tel", "text", "textarea", "url"],

  registerNode: function(node) {
    this.nextIndex++;
    this.nodes[this.nextIndex] = node;
    return this.nextIndex;
  },

  waitPromise: function(truthFn, delay) {
    var intId;
    var p = new Promise(function(resolve, reject) {
      var truthy = truthFn();
      if (truthy) {
        resolve(truthy);
      } else {
        intId = window.setInterval(function() {
          truthy = truthFn();
          if (truthy) {
            clearInterval(intId);
            resolve(truthy);
          }
        }.bind(this), delay);
      }
    }.bind(this));
    return p;
  },

  waitWindowLoaded: function() {
    return this.waitPromise(function() {
      return this.windowLoaded;
    }.bind(this));
    // var intId;
    // var p = new Promise(function(resolve, reject) {
    //   if (this.windowLoaded) {
    //     resolve();
    //   } else {
    //     intId = window.setInterval(function() {
    //       if (this.windowLoaded) {
    //         clearInterval(intId);
    //         resolve(this.windowLoaded);
    //       }
    //     }.bind(this), 5);
    //   }
    // }.bind(this));
    // return p;
  },

  waitDOMContentLoaded: function() {
    return this.waitPromise(function() {
      return this.DOMContentLoaded;
    }.bind(this));
    // var intId;
    // var p = new Promise(function(resolve, reject) {
    //   if (this.DOMContentLoaded) {
    //     resolve();
    //   } else {
    //     intId = window.setInterval(function() {
    //       if (this.DOMContentLoaded) {
    //         clearInterval(intId);
    //         resolve(this.DOMContentLoaded);
    //       }
    //     }.bind(this), 5);
    //   }
    // }.bind(this));
    // return p;
  },

  findCss: function(query) {
    return this.findCssRelativeTo(document, query);
  },

  findCssWithin: function (index, query) {
    return this.findCssRelativeTo(this.getNode(index), query);
  },

  findCssRelativeTo: function(reference, query) {
    return this.waitDOMContentLoaded().then(function() {
      var results = [];
      var list = reference.querySelectorAll(query);
      for (i = 0; i < list.length; i++) {
        results.push(this.registerNode(list[i]));
      }
      return results.join(",");
    }.bind(this));
  },

  findXPath: function(query) {
    return this.findXpathRelativeTo(document, query);
  },

  findXPathWithin: function(index, query) {
    return this.findXpathRelativeTo(this.getNode(index), query);
  },

  findXpathRelativeTo: function(reference, query) {
    return this.waitDOMContentLoaded().then(function() {
      var iterator = document.evaluate(query, reference, null, XPathResult.ORDERED_NODE_ITERATOR_TYPE, null);
      var node;
      var results = [];
      while (node = iterator.iterateNext()) {
        results.push(this.registerNode(node));
      }
      return results.join(",");
    }.bind(this));
  },

  getXPathNode: function(node, path) {
    path = path || [];
    if (node.parentNode) {
      path = this.getXPathNode(node.parentNode, path);
    }

    var first = node;
    while (first.previousSibling)
      first = first.previousSibling;

    var count = 0;
    var index = 0;
    var iter = first;
    while (iter) {
      if (iter.nodeType == 1 && iter.nodeName == node.nodeName)
        count++;
      if (iter.isSameNode(node))
        index = count;
      iter = iter.nextSibling;
      continue;
    }

    if (node.nodeType == 1)
      path.push(node.nodeName.toLowerCase() + (node.id ? "[@id='"+node.id+"']" : count > 1 ? "["+index+"]" : ''));

    return path;
  },

  nodePathForNode: function(index) {
    return this.pathForNode(this.getNode(index));
  },

  pathForNode: function(node) {
    return "/" + this.getXPathNode(node).join("/");
  },

  getNode: function(index) {
    var node = this.nodes[index];
    if (!node) {
      throw new NodeNotFoundError("No node found with id:"+index+". Registered nodes:"+Object.keys(this.nodes).length);
    }
    return node;
  },

  onSelf: function(index, script) {
    var node = this.getNode(index);
    // console.log("onSelf " + index + " " + node.tagName + " " + (node.parentElement && node.parentElement.tagName) + " " + script);
    var fn = Function("'use strict';"+script).bind(node)
    var pp = new Promise(function(resolve) { resolve(fn()); });
    return pp;
  },

  // args should be an array
  onSelfValue: function(index, meth, args) {
    var node = this.getNode(index);
    var val = node[meth];
    if (typeof val === "function") {
      val.apply(node, args);
    } else {
      return val;
    }
  },

  dispatchEvent: function(node, eventName) {
    if (eventName == "click") {
      var eventObject = new MouseEvent("click", {bubbles: true, cancelable: true});
      return node.dispatchEvent(eventObject);
    } else {
      var eventObject = document.createEvent("HTMLEvents");
      eventObject.initEvent(eventName, true, true);
      return node.dispatchEvent(eventObject);
    }
  },

  nodeSetType: function(index) {
    var node = this.getNode(index);
    return (node.type || node.tagName).toLowerCase();
  },

  nodeSet: function(index, value, type) {
    var node = this.getNode(index);
    if (type == "checkbox" || type == "radio") {
      if (value == "true" && !node.checked) {
        return node.click();
      } else if (value == "false" && node.checked) {
        return node.click();
      }
    } else {
      return node.value = value;
    }
  },

  nodeVisible: function(index) {
    return this.visible(this.getNode(index));
  },

  visible: function(node) {
    var styles = node.ownerDocument.defaultView.getComputedStyle(node);
    if (styles["visibility"] == "hidden" || styles["display"] == "none" || styles["opacity"] == 0) {
      return false;
    }
    while (node = node.parentElement) {
      styles = node.ownerDocument.defaultView.getComputedStyle(node);
      if (styles["display"] == "none" || styles["opacity"] == 0) {
        return false;
      }
    }
    return true;
  },

  nodeText: function(index) {
    return this.text(this.getNode(index));
  },

  text: function(node) {
    var type = node instanceof HTMLFormElement ? 'form' : (node.type || node.tagName).toLowerCase();
    if (type == "textarea") {
      return node.innerHTML;
    } else {
      var visible_text = node.innerText;
      return typeof visible_text === "string" ? visible_text : node.textContent;
    }
  },

  nodeIsNodeAtPosition: function(index, pos) {
    return this.isNodeAtPosition(this.getNode(index), pos);
  },

  isNodeAtPosition: function(node, pos) {
    var nodeAtPosition =
      document.elementFromPoint(pos.relativeX, pos.relativeY);
    var overlappingPath;


    if (nodeAtPosition) {
      // console.log("is node at position" + nodeAtPosition.tagName)
      overlappingPath = this.pathForNode(nodeAtPosition)
    }

    if (!this.isNodeOrChildAtPosition(node, pos, nodeAtPosition)) {
      // console.log("Would throw " + overlappingPath + " " + this.pathForNode(node))
      return false;
    }

    return true;
  },

  isNodeOrChildAtPosition: function(expectedNode, pos, currentNode) {
    if (currentNode == expectedNode) {
      return true;
    } else if (currentNode) {
      return this.isNodeOrChildAtPosition(
        expectedNode,
        pos,
        currentNode.parentNode
      );
    } else {
      return false;
    }
  },

  nodeGetDimensions: function(index) {
    return this.getDimensions(this.getNode(index));
  },

  getDimensions: function(node) {
    return JSON.stringify(node.getBoundingClientRect());
  },

  // don't attach state to the node because the node can go away after click
  attachClickListener: function(index) {
    var node = this.getNode(index);
    this.nodeClicks[index] = false;
    var fn = function() {
      this.nodeClicks[index] = true;
      node.removeEventListener("click", fn);
    }.bind(this);
    node.addEventListener("click", fn);
  },

  nodeVerifyClicked: function(index) {
    return this.nodeClicks[index];
  }
}

document.addEventListener("DOMContentLoaded", function() {
  ChromeRemoteHelper.DOMContentLoaded = true;
  // console.log("DOMContentLoaded");
});

window.addEventListener("load", function() {
  ChromeRemoteHelper.windowLoaded = true;
  // console.log("windowLoaded");
});

class NodeNotFoundError extends Error{}
