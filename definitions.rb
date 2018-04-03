def ords(s)
    s.chars.map(&:ord)
end

def chr(x)
    [x].pack 'U'
end

def is_upcase?(s)
    s == s.upcase and s != s.downcase
end

def is_downcase?(s)
    s == s.downcase and s != s.upcase
end

class Func
    def initialize(type_map, arity, raw = false)
        @type_map = type_map
        @arity = arity
        @raw = raw
    end
    
    attr_accessor :arity, :raw, :type_map
    
    def Func.raw(&func)
        Func.new ({ :else => func }), 0, true
    end
    
    def Func.constant(val)
        Func.raw { $stack.push val }
    end
    
    # code point-ify -- allows for operations defined over integers to be extended over code points
    def cp_ify(opt = :some)
        if opt == :monad
            int_case = @type_map[[Integer]]
            @type_map[[String]] = lambda { |s| ords(s).map { |c| chr(int_case[c]) }.join }
        elsif opt == :rev_monad
            str_case = @type_map[[String]]
            @type_map[[Integer]] = lambda { |n| str_case[chr(n)] }
        elsif opt == :some or opt == :all
            int_case = @type_map[[Integer, Integer]]
            @type_map[[String, Integer]] = lambda { |s, i| ords(s).map { |c| chr(int_case[c, i]) }.join }
            @type_map[[Integer, String]] = lambda { |i, s| ords(s).map { |c| chr(int_case[i, c]) }.join }
            if opt == :all
                @type_map[[String, String]] = lambda { |a, b|
                    maxl = ords(a.size < b.size ? b : a)
                    minl = ords(a.size < b.size ? a : b)
                    
                    cpoints = maxl.map.with_index { |e, i|
                        return e if i >= minl.size
                        int_case[e, minl[i]]
                    }
                    
                    return cpoints.map { |e| chr(e) }.join
                }
            end
        else
            $stderr.puts "Unknown cp_ify method #{opt}"
        end
        return self
    end
    
    def [](*a)
        a_types = a.map &:class
        effect = nil
        @type_map.each { |k, v|
            if k == :else || k == a_types
                effect = v
                break
            end
        }
        if effect == nil
            str = "No such case for `#{a_types.join ", "}`; expected one of:\n"
            str += @type_map.to_a.map { |k| "- #{k[0].join ", "}" }.join "\n"
            $handle_error[str]
        end
        return effect[*a]
    end
end

def fact(n)
    @mem ||= {}
    return @mem[n] if @mem.has_key? n
    return 1 if n == 0 or n == 1
    $handle_error["Cannot take factorial of negative number #{n}"] if n < 0
    @mem[n] = fact(n - 1) * n
end

def sprintf(fmt)
    @opts ||= {
        "r" => lambda { |s| s_repr(s) },
        "s" => lambda { |s| s.to_s },
        "i" => lambda { |s| s.to_i },
        "c" => lambda { |s| chr(s.to_i) },
        "v" => lambda { |s| s },
    }
    fmt.gsub(/%(.)/) {
        @opts[$1][$stack.pop]
    }.gsub(/(\\x[\dA-Fa-f]{2}|\\u[\dA-Fa-f]{4}|\\[nvftr])/) { eval "\"#$1\"" }
end

$funcs = {
    # duplicate
    "\t" => Func.raw {},    # no op
    "\n" => Func.raw {},    # no op
    " " => Func.raw {},     # no op
    "." => Func.raw {},     # no op
    "~" => Func.raw {
        a, b = $stack.pop(2)
        $stack.push b, a
    },
    "!" => Func.new({
        [Integer] => lambda { |n| fact n },
        [String] => lambda { |s| execute(s); nil },
    }, 1),
    "$" => Func.raw { $stack.pop },
    # multiply
    "*" => Func.new({
        [Integer, Integer] => lambda { |x, y| x * y },
    }, 2).cp_ify(:all),
    # subtract
    "-" => Func.new({
        [Integer, Integer] => lambda { |x, y| x - y },
    }, 2).cp_ify(:all),
    # add
    "+" => Func.new({
        [Integer, Integer] => lambda { |x, y| x + y },
    }, 2).cp_ify(:all),
    # conditional
    "?" => Func.raw { |ind, tokens|
        if falsey $stack.pop
            # p ind
            while ind < tokens.size and tokens[ind] != ","
                ind += 1
            end
        end
        [:update, ind]
    },
    "," => Func.raw { |ind, tokens|
        while ind < tokens.size and tokens[ind] != "."
            ind += 1
        end
        [:update, ind]
    },
    "<" => Func.new({
        [String, String] => lambda { |x, y| (x < y).to_i },
        [Integer, Integer] => lambda { |x, y| (x < y).to_i },
    }, 2),
    ">" => Func.new({
        [String, String] => lambda { |x, y| (x > y).to_i },
        [Integer, Integer] => lambda { |x, y| (x > y).to_i },
    }, 2),
    # equality
    "=" => Func.new({
        [Integer, Integer] => lambda { |x, y| (x == y).to_i },
        [String, String] => lambda { |x, y| (x == y).to_i },
        [Integer, String] => lambda { |x, y| 0 },
        [String, Integer] => lambda { |x, y| 0 },
    }, 2),
    "_" => Func.new({
        [String] => lambda { |s| s.chars.reverse.join },
        [Integer] => lambda { |n| -n },
    }, 1),
    # concat
    ":" => Func.new({
        [String, String] => lambda { |x, y| x + y },
    }, 2),
    ";" => Func.raw {},     # no op
    "A" => Func.constant(10),
    "B" => Func.constant(11),
    "C" => Func.constant(12),
    "D" => Func.constant(13),
    "E" => Func.constant(14),
    "F" => Func.constant(15),
    "G" => Func.raw { $stack.push $stdin.read($stack.pop) || "" },
    # pick
    "H" => Func.raw {
        $stack.push $stack[-$stack.pop]
    },
    # read integer
    "I" => Func.raw {
        build = $stdin.read(1)
        if build =~ /\d|-/
            loop do
                byte = $stdin.read(1)
                break if byte !~ /\d/
                build += byte
            end
            build = build.to_i
        end
        $stack.push build
    },
    # bubble
    "J" => Func.raw {
        n = $stack.pop
        q = $stack.pop n
        $stack.push *q[1..-1]
        $stack.push q[0]
    },
    "L" => Func.new({
        [String] => lambda { |s| is_downcase?(s).to_i }
    }, 1).cp_ify(:rev_monad),
    "M" => Func.raw { $stack.push $stack.pop.to_i },
    # negation
    "N" => Func.raw { $stack.push falsey($stack.pop).to_i },
    "O" => Func.raw { puts $stack.pop },
    "P" => Func.new({
        [String] => lambda { |s|
            sprintf(s)
        }
    }, 1),
    "R" => Func.raw { puts s_repr($stack.pop) },
    "U" => Func.new({
        [String] => lambda { |s| is_upcase?(s).to_i }
    }, 1).cp_ify(:rev_monad),
    "V" => Func.new({
        [Integer] => lambda { |x| (x - 32) % 95 + 32 },
    }, 1).cp_ify(:monad),
    "W" => Func.raw { $status |= Terminals::DISPLAY_AT_END },
    "X" => Func.new({
        [Integer] => lambda { |x| x + 1 },
    }, 1).cp_ify(:monad),
    "Y" => Func.new({
        [Integer] => lambda { |x| x - 1 },
    }, 1).cp_ify(:monad),
    "Z" => Func.raw { puts $stack.repr },
    # push to buffer
    "b" => Func.raw { $buffer.push $stack.pop },
    # code to char
    "c" => Func.new({
        [Integer] => lambda { |s| chr(s) },
        [String] => lambda { |s| s },
    }, 1),
    "d" => Func.raw { $stack.push $stack.peek },
    "e" => Func.constant(""),
    "g" => Func.raw { $stack.push $stdin.read(1) || "" },
    "l" => Func.raw { $stack.push $stdin.read },
    "m" => Func.raw { $stack.push $stack.pop.to_s },
    "n" => Func.constant("\n"),
    "o" => Func.raw { print $stack.pop },
    # printf
    "p" => Func.new({
        [String] => lambda { |s|
            print sprintf(s)
            nil
        }
    }, 1),
    "q" => Func.raw { $status |= Terminals::DISABLE_PRINT },
    "r" => Func.raw { print s_repr($stack.pop) },
    "s" => Func.constant(" "),
    # pop from buffer
    "u" => Func.raw { $stack.push $buffer.pop },
    "w" => Func.raw { $status |= Terminals::SHOW_AT_END },
    # repeat
    "x" => Func.new({
        [String, Integer] => lambda { |s, n| s * n },
        [Integer, String] => lambda { |n, s| s * n },
        [Integer, Integer] => lambda { |n, r| (n.to_s * r).to_i },
    }, 2),
    # char -> int
    "y" => Func.new({
        [Integer] => lambda { |i| i },
        [String] => lambda { |s| s.ord },
    }, 1),
    "z" => Func.raw { puts $stack.data.join "\n" },
    # conditional
    "#?" => Func.raw {
        cond, if_c, else_c = $stack.pop(3)
        execute(truthy(cond) ? if_c : else_c)
    },
    # push ASCII
    "#@" => Func.raw { $stack.push (32..126).to_a.map(&:chr).join },
    # divmod
    "#/" => Func.new({
        [Integer, Integer] => lambda { |a, b|
            $stack.push a / b
            a % b
        },
    }, 2).cp_ify(:all),
    "#A" => Func.constant(("A".."Z").to_a.join),
    "#C" => Func.raw { print "\x1b[2J" },
    # update domain
    "#D" => Func.raw { $domain = $stack.pop },
    # read all of stdin
    "#L" => Func.raw { $stack.push $stdin.read },
    # swapcase
    "#S" => Func.new({
        [String] => lambda { |s|
            s == s.upcase ? s.downcase : s.upcase
        }
    }, 1),
    # domain previous
    "#T" => Func.new({
        [String] => lambda { |x|
            ind = $domain.index x
            return x if ind == nil
            ind -= 1
            $domain[ind % $domain.size]
        }
    }, 1),
    # domain next
    "#U" => Func.new({
        [String] => lambda { |x|
            ind = $domain.index x
            return x if ind == nil
            ind += 1
            $domain[ind % $domain.size]
        }
    }, 1),
    # dynamic fit
    "#V" => Func.new({
        [String] => lambda { |x|
            ind = $domain.index x
            $domain[ind % $domain.size]
        }
    }, 1),
    "#Z" => Func.raw { puts $buffer.repr },
    "#a" => Func.constant(("a".."z").to_a.join),
    # unshift to buffer
    "#b" => Func.raw { $buffer.unshift $stack.pop },
    # remove trailing newline if present
    "#c" => Func.new({
        [String] => lambda { |s| s.chomp },
    }, 1),
    # push domain
    "#d" => Func.raw { $stack.push $domain },
    # read line of input
    "#l" => Func.raw { $stack.push $stdin.gets },
    # map function over stack
    "#m" => Func.new({
        [String] => lambda { |s|
            temp_stack = $stack.data.clone
            $stack = Stack.new temp_stack.map { |val|
                $stack = Stack.new [val]
                execute(s)
                $stack.pop
            }
            nil
        }
    }, 1),
    "#p" => Func.new({
        [Integer, Integer, String] => lambda { |x, y, c| 
            print "\x1b[#{x + 1};#{y + 1}f#{c}"
        },
    }, 3),
    "#q" => Func.new({
        [String] => lambda { |s| s.chars.uniq.join },
        [Integer] => lambda { |s| x.to_s.chars.uniq.join.to_i },
    }, 1),
    # reduce stack over function
    "#r" => Func.new({
        [String] => lambda { |s|
            while $stack.size > 1
                execute(s)
            end
        }
    }, 1),
    # shift from buffer
    "#u" => Func.raw { $stack.push $buffer.shift },
    "#z" => Func.raw { puts $buffer.data.join "\n" },
}

$ext = "#"