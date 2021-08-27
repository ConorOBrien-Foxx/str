# ruby implementation of the `str` language
# goals:
#   C or C++ implementation

# Performance analysis, 3/24/2021, on test/hello-world.str
#   Seconds elapsed for #tokenize: 0.357114
#       Most expensive token operations:
#           ` (string) \n (linefeed/whitespace) first few commands
#   Seconds elapsed for #get_sections: 0.348736
#   Seconds elapsed for #main: 0.357812
# Made string parsing its own while loop. Result:
#   Seconds elapsed for #tokenize: 0.013031
#   Seconds elapsed for #get_sections: 0.01344
#   Seconds elapsed for #main: 0.021211
#   94.07% improvement

def time_fn(label="unlabeled", &fn)
    time_start = Time.now
    res = fn[]
    time_end = Time.now
    diff = time_end - time_start
    puts "Seconds elapsed for ##{label}: #{diff}"
    res
end

# time_fn("main") {

require 'io/console'
$ctrlC = "\u0003"
$ctrlD = "\u0004"

$chars_read = 0
def getch
    char = STDIN.getch
    exit(1) if char == $ctrlC
    char == $ctrlD ? -1 : char
end

$command = nil
$handle_error = Proc.new { |message, fatal = true, exit_code = -1|
    $stderr.puts "Error: #{message}"
    # begin
        # raise
    # rescue Exception => e
        # $stderr.puts e.full_message
    # end
    if $command
        $stderr.puts "In command: #$command."
    end
    # $command = nil
    exit(exit_code) if fatal
}

require_relative "stack.rb"

# main loop function

def main_loop(&on_byte)
    if $stdin.closed?
        # no interior loop
    elsif $stdin.tty?
        # is interactive
        loop do
            char = getch
            break if char == nil
            $chars_read += 1
            on_byte.call char
        end
    else
        STDIN.each_byte { |ord|
            $chars_read += 1
            on_byte.call ord.chr
        }
    end
    on_byte.call -1 while $buffer.size > 0
end

require_relative "terminals.rb"   # for Terminals module

$buffer = Stack.new
$stack = Stack.new
$memory = {}
$chnum = 0
$domain = "abcdefghijklmnopqrstuvwxyzaABCDEFGHIJKLMNOPQRSTUVWXYZA"
$status = Terminals::EMPTY

require_relative "definitions.rb" # for $funcs, $ext

program = ARGV[0]
if program == "-e"
    program = File.read ARGV[1]
end

$string     = '`(?:[\s\S]+?|``)*`'
$number     = '\d+'
$defcommand = '&([.:!])?(\w+)'
$extseq     = Regexp.escape($ext) + '?.'
$char       = '\'.'
$extchar    = '\\\\..'
$whitespace = '\s+'
$other      = '\S'

$tokarr = [
    $number,
    # $string,
    $defcommand,
    $char,
    $extchar,
    $whitespace,
    $extseq,
    $other,
].map { |e| /#{e}/ }

def tokenize(program)
    $command = "tokenize"
    i = 0
    @toks = []
    while i < program.size
        if program[i] == '['
            depth = 1
            build = program[i]
            loop do
                i += 1
                depth += 1 if program[i] == '['
                depth -= 1 if program[i] == ']'
                if program[i] == nil
                    $handle_error["Unmatched `[` (final depth = #{depth} away)"]
                end
                build += program[i]
                break if depth == 0
            end
            # skip over last `]`
            i += 1
            @toks.push build
        elsif program[i] == '`'
            build = program[i]
            loop do
                i += 1
                if program[i] == nil
                    $handle_error["Unmatched string terminator '`'"]
                end
                build += program[i]
                if program[i] == '`'
                    if program[i + 1] == '`'
                        i += 1
                        build += program[i]
                    else
                        break
                    end
                end
            end
            # skip over last '`'
            i += 1
            @toks.push build
        else
            pr_slice = program[i..-1]
            $tokarr.each { |re|
                # p pr_slice, re, (pr_slice =~ re)
                if 0 == (pr_slice =~ re)
                    slice = pr_slice.match(re).to_s
                    @toks.push slice
                    i += slice.size
                    break
                end
            }
        end
    end
    @toks
end

def get_sections(program)
    sections = []
    build = []
    tokenize(program).each { |tok|
        build.push tok
        if tok == ';'
            sections.push build.clone
            build = []
        end
    }
    sections.push build if build.size
    sections
end

def execute(program)
    tokens = program.kind_of?(Array) ? program : tokenize(program)
    index = 0
    while index < tokens.size
        $command = tok = tokens[index]
        if /^#$number$/ === tok
            $stack.push tok.to_i
        elsif /^#$string$/ === tok
            $stack.push tok[1...-1].gsub(/``/, "`")
        elsif /^#$char$/ === tok
            $stack.push tok[1]
        elsif /^#$extchar$/ === tok
            $stack.push tok[1..2]
        elsif /^#$defcommand/ === tok
            # store operation
            op, name = $1, $2
            case op
            when ":"
                fn = $stack.pop
                $memory[name] = fn
            when "."
                $stack.push $memory[name]
            when "!", nil
                $stack.push $memory[name]
                execute "!"
            else
                STDERR.puts "Unknown signal character #{op} in #{tok}."
            end
        elsif /^#$whitespace/ === tok
            # no-op
        elsif tok[0] == '['
            $stack.push tok[1...-1]
        elsif $funcs.has_key? tok
            effect = $funcs[tok]
            args = effect.raw ? [index, tokens] : $stack.pop(effect.arity)
            res = effect[*args]
            if effect.raw
                index = res[1] if res and res[0] == :update
            else
                $stack.push res unless res == nil
            end
        else
            $stderr.puts "No such command `#{tok}`"
        end
        index += 1
        break if $status & Terminals::QUIT != 0
    end
end

sections = get_sections(program)
# p sections
preamble, program, postamble = sections
if program == nil and postamble == nil and preamble != nil and preamble[-1] != ';'
    program = preamble
    preamble = ""
end
preamble  ||= ""
program   ||= ""
postamble ||= ""

execute(preamble)

$final = $status
$status = Terminals::EMPTY

$net_mask = 0
main_loop { |byte|
    $buffer.push byte unless byte == -1
    until $buffer.size == 0
        $stack.push $buffer.pop
        execute(program)
        $command = "<Implicit Print>"
        print $stack.pop unless $status & Terminals::DISABLE_PRINT != 0
        $net_mask |= $status
        $status = 0
    end
    $chnum += 1
}

execute(postamble)

$net_mask |= $final

puts $stack.repr if $net_mask & Terminals::DISPLAY_AT_END != 0
puts $stack.join if $net_mask & Terminals::SHOW_AT_END != 0

# p $stack
# }