def s_repr(val)
    @a ||= Func.new({
        [String] => lambda { |s| "`#{s.gsub(/`/, "``")}`" },
        :else => lambda { |s| s.inspect },
    }, 1)
    @a[val]
end

def truthy(val)
    val != 0
end

def falsey(val)
    not truthy(val)
end

class TrueClass; def to_i; 1; end; end
class FalseClass; def to_i; 0; end; end

class Stack
    def initialize(data = [], handle_error = $handle_error)
        @data = data
        @handle_error = handle_error
    end
    
    attr_accessor :data
    
    def [](n)
        @data[n]
    end
    
    def size
        @data.size
    end
    
    def map(&block)
        @data.map &block
    end
    
    def repr
        "[ #{ to_a.map { |e| s_repr(e) } .join "; " } ]"
    end
    
    def to_a
        @data.clone
    end
    
    def pop(n = nil)
        if n == nil
            @handle_error["Popping from an empty stack"] if @data.size == 0
            return @data.pop
        else
            args = []
            n.times {
                args.unshift pop
            }
            return args
        end
    end
    
    def shift(n = nil)
        if n == nil
            @handle_error["Popping from an empty stack"] if @data.size == 0
            return @data.shift
        else
            args = []
            n.times {
                args.push shift
            }
            return args
        end
    end
    
    def join(*a)
        @data.join(*a)
    end
    
    def peek
        @data[-1]
    end
    
    def push(*vals)
        @data.push *vals
    end
    
    def unshift(*vals)
        @data.unshift *vals
    end
    
    def inspect
        return "Stack #{@data.inspect}"
    end
end