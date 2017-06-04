# ruby implementation of the `str` language
# goals:
#   C or C++ implementation

require 'io/console'
$ctrlC = "\u0003"
$ctrlD = "\u0004"
def getch
    char = STDIN.getch
    exit(1) if char == $ctrlC
    char == $ctrlD ? -1 : char
end

$handle_error = Proc.new { |message, fatal = true, exit_code = -1|
    $stderr.puts "Error: #{message}"
    exit(exit_code) if fatal
}

require_relative "stack.rb"

# main loop function

def main_loop(&on_byte)
    # is interactive
    if $stdin.tty?
        loop do
            char = getch
            on_byte.call char
        end
    else
        STDIN.each_byte { |ord|
            on_byte.call ord.chr
        }
    end
end

require_relative "terminals.rb"   # for Terminals module

$buffer = Stack.new
$stack = Stack.new
$chnum = 0
$domain = "abcdefghijklmnopqrstuvwxyz"
$status = Terminals::EMPTY

require_relative "definitions.rb" # for $funcs, $ext

program = ARGV[0]

$string = '`(?:.+?|``)*`'
$number = '\d+'
$extseq = Regexp.escape($ext) + '?.'
$char   = '\'.'

$tokarr = [$number, $string, $char, $extseq].map { |e| /#{e}/ }

def tokenize(program)
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
    # p @toks
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
    tokens.each { |tok|
        if /^#$number$/ === tok
            $stack.push tok.to_i
        elsif /^#$string$/ === tok
            $stack.push tok[1...-1].gsub(/``/, "`")
        elsif /^#$char$/ === tok
            $stack.push tok[1]
        elsif tok[0] == '['
            $stack.push tok[1...-1]
        elsif $funcs.has_key? tok
            effect = $funcs[tok]
            args = effect.raw ? [] : $stack.pop(effect.arity)
            res = effect[*args]
            $stack.push res unless effect.raw or res == nil
        else
            $stderr.puts "No such command `#{tok}`"
        end
        break if $status & Terminals::QUIT != 0
    }
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
    break if byte == -1
    $buffer.push byte
    until $buffer.size == 0
        $stack.push $buffer.pop
        execute(program)
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