class Array
    def &(y)
        m = Matcher.new
        m.add_record self, y
    end
end

class Matcher
    def initialize
        @entries = []
    end
    
    def add_record(key, val)
        @entries.push [key, val]
    end
    
    def |(y)
        
    end
    
    attr_accessor :entries
end

match = [Fixnum] % 12  |
        [String] % 34  |
        [Array]  % 235

p match