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
    # swap top two
    "~" => Func.raw {
        a, b = $stack.pop(2)
        $stack.push b, a
    },
    # factorial, or eval
    "!" => Func.new({
        [Integer] => lambda { |n| fact n },
        [String] => lambda { |s| execute(s); nil },
    }, 1),
    # drop top
    "$" => Func.raw { $stack.pop },
    # multiply
    "*" => Func.new({
        [Integer, Integer] => lambda { |x, y| x * y },
    }, 2).cp_ify(:all),
    # exponentiation
    "^" => Func.new({
        [Integer, Integer] => lambda { |x, y| x ** y },
    }, 2).cp_ify(:all),
    # division
    "/" => Func.new({
        [Integer, Integer] => lambda { |x, y| x / y },
    }, 2).cp_ify(:all),
    # subtract
    "-" => Func.new({
        [Integer, Integer] => lambda { |x, y| x - y },
    }, 2).cp_ify(:all),
    # add
    "+" => Func.new({
        [Integer, Integer] => lambda { |x, y| x + y },
    }, 2).cp_ify(:all),
    # conditional condition?if,else.
    "?" => Func.raw { |ind, tokens|
        if falsey $stack.pop
            # p ind
            while ind < tokens.size and tokens[ind] != ","
                ind += 1
            end
        end
        [:update, ind]
    },
    # delim for conditional
    "," => Func.raw { |ind, tokens|
        while ind < tokens.size and tokens[ind] != "."
            ind += 1
        end
        [:update, ind]
    },
    # less-than
    "<" => Func.new({
        [String, String] => lambda { |x, y| (x < y).to_i },
        [Integer, Integer] => lambda { |x, y| (x < y).to_i },
    }, 2),
    # greater-than
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
    # reverse, or negation
    "_" => Func.new({
        [String] => lambda { |s| s.chars.reverse.join },
        [Integer] => lambda { |n| -n },
    }, 1),
    # concat, or digit concat
    ":" => Func.new({
        [String, String] => lambda { |x, y| x + y },
        [Integer, Integer] => lambda { |x, y| (x.to_s + y.to_s).to_i }
    }, 2),
    ";" => Func.raw {},     # no op
    # constants A-F = 10-15
    "A" => Func.constant(10),
    "B" => Func.constant(11),
    "C" => Func.constant(12),
    "D" => Func.constant(13),
    "E" => Func.constant(14),
    "F" => Func.constant(15),
    # read N characters from STDIN
    "G" => Func.raw { $stack.push $stdin.read($stack.pop) || "" },
    # pick from stack
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
    # slice (2-arg)
    "K" => Func.new({
        [String, Integer, Integer] => lambda { |s, b, e|
            s[b..e]
        }
    }, 3),
    "L" => Func.new({
        [String] => lambda { |s| is_downcase?(s).to_i }
    }, 1).cp_ify(:rev_monad),
    "M" => Func.raw { $stack.push $stack.pop.to_i },
    # logical negation
    "N" => Func.raw { $stack.push falsey($stack.pop).to_i },
    # output top with trailing newline
    "O" => Func.raw { puts $stack.pop },
    # sprintf, popping members from top of stack, and push result to stack
    "P" => Func.new({
        [String] => lambda { |s|
            sprintf(s)
        }
    }, 1),
    # str representation
    "R" => Func.raw { puts s_repr($stack.pop) },
    # size, or digit count
    "S" => Func.new({
        [String] => lambda { |s| s.size },
        [Integer] => lambda { |n| n.abs.to_s.size },
    }, 1),
    # is uppercase?
    "U" => Func.new({
        [String] => lambda { |s| is_upcase?(s).to_i }
    }, 1).cp_ify(:rev_monad),
    # lock to ascii domain
    "V" => Func.new({
        [Integer] => lambda { |x| (x - 32) % 95 + 32 },
    }, 1).cp_ify(:monad),
    # displays stack at end
    "W" => Func.raw { $status |= Terminals::DISPLAY_AT_END },
    # increment
    "X" => Func.new({
        [Integer] => lambda { |x| x + 1 },
    }, 1).cp_ify(:monad),
    # decrement
    "Y" => Func.new({
        [Integer] => lambda { |x| x - 1 },
    }, 1).cp_ify(:monad),
    # debug - print stack
    "Z" => Func.raw { puts $stack.repr },
    # push to buffer
    "b" => Func.raw { $buffer.push $stack.pop },
    # code to char
    "c" => Func.new({
        [Integer] => lambda { |s| chr(s) },
        [String] => lambda { |s| s },
    }, 1),
    # duplicate top of stack
    "d" => Func.raw { $stack.push $stack.peek },
    # empty string
    "e" => Func.constant(""),
    # reading 1 character from stdin
    "g" => Func.raw { $stack.push $stdin.read(1) || "" },
    # slice 1-arg
    "k" => Func.new({
        [String, Integer] => lambda { |s, b|
            s[b..-1]
        }
    }, 2),
    # read all of stdin
    "l" => Func.raw { $stack.push $stdin.read },
    # convert to string
    "m" => Func.raw { $stack.push $stack.pop.to_s },
    # newline
    "n" => Func.constant("\n"),
    # print without trailing newline
    "o" => Func.raw { print $stack.pop },
    # printf, pushes nothing to stack
    "p" => Func.new({
        [String] => lambda { |s|
            print sprintf(s)
            nil
        }
    }, 1),
    # disables automatic printing for the run
    "q" => Func.raw { $status |= Terminals::DISABLE_PRINT },
    # print repr without trailing newline
    "r" => Func.raw { print s_repr($stack.pop) },
    # space literal
    "s" => Func.constant(" "),
    # pop from buffer
    "u" => Func.raw { $stack.push $buffer.pop },
    # displays stack at end as string
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
    # debug simple
    "z" => Func.raw { puts $stack.data.join "\n" },
    # conditional
    "#?" => Func.raw {
        cond, if_c, else_c = $stack.pop(3)
        execute(truthy(cond) ? if_c : else_c)
    },
    # push ASCII
    "#@" => Func.raw { $stack.push (32..126).to_a.map(&:chr).join },
    "\#$" => Func.raw { $stack.push $chars_read },
    # divmod
    "#/" => Func.new({
        [Integer, Integer] => lambda { |a, b|
            $stack.push a / b
            a % b
        },
    }, 2).cp_ify(:all),
    # push uppercase alphabet
    "#A" => Func.constant(("A".."Z").to_a.join),
    # move entire stack to buffer
    "#B" => Func.raw {
        $buffer.push *$stack.pop($stack.size)
    },
    # clear screen
    "#C" => Func.raw { print "\x1b[2J" },
    # update domain
    "#D" => Func.raw { $domain = $stack.pop },
    # exit with code
    "#E" => Func.new({
        [Integer] => lambda { |i| exit i },
        [String] => lambda { |msg| STDERR.puts message; exit 1 },
    }, 1),
    # read all of stdin
    "#L" => Func.raw { $stack.push $stdin.read },
    # string range, or integer stack range
    "#R" => Func.new({
        [String, String] => lambda { |s, r|
            reverse = s >= r
            s, r = r, s if reverse
            res = [*s..r].join
            res.reverse! if reverse
            res
        },
        [Integer, Integer] => lambda { |a, b|
            iter = a < b ? a.upto(b) : a.downto(b)
            iter.each { |i|
                $stack.push i
            }
            nil
        }
    }, 2),
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
    # debug buffer
    "#Z" => Func.raw { puts $buffer.repr },
    # push lowercase alphabet
    "#a" => Func.constant(("a".."z").to_a.join),
    # unshift to buffer
    "#b" => Func.raw { $buffer.unshift $stack.pop },
    # remove trailing newline if present
    "#c" => Func.new({
        [String] => lambda { |s| s.chomp },
    }, 1),
    # push domain
    "#d" => Func.raw { $stack.push $domain },
    # exit program
    "#e" => Func.raw { exit 0 },
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
    # place character at position in console
    "#p" => Func.new({
        [Integer, Integer, String] => lambda { |x, y, c| 
            print "\x1b[#{x + 1};#{y + 1}f#{c}"
        },
    }, 3),
    # unique
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
    # scan, regexp to stack
    "#s" => Func.new({
        [String, String] => lambda { |s, reg|
            reg = Regexp.new reg
            $stack.push *s.scan(reg)
            nil
        }
    }, 2),
    # shift from buffer
    "#u" => Func.raw { $stack.push $buffer.shift },
    # debug buffer simple
    "#z" => Func.raw { puts $buffer.data.join "\n" },
    # less-than or equal to
    "#<" => Func.new({
        [String, String] => lambda { |x, y| (x <= y).to_i },
        [Integer, Integer] => lambda { |x, y| (x <= y).to_i },
    }, 2),
    # greater-than or equal to
    "#>" => Func.new({
        [String, String] => lambda { |x, y| (x >= y).to_i },
        [Integer, Integer] => lambda { |x, y| (x >= y).to_i },
    }, 2),
}

$ext = "#"