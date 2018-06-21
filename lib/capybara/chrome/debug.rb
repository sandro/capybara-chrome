module Capybara
  module Chrome
    module Debug
      def debug(*args)
        # p [caller_locations(1,1)[0].label, *args, Time.now.to_i]
        return args[0]
      end

      def info(*args)
        p [caller_locations(1,1)[0].label, *args, Time.now.to_i]
        return args[0]
      end
    end
  end
end
