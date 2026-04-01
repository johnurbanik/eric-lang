# Indentation-aware lexer for eric-lang
# Hand-written character scanner since Julia doesn't have Python's re module.
# Supports escaped quotes in strings (Review Issue #2).

"""
    tokenize(source::String, filename::String="<stdin>") -> Vector{Token}

Tokenize eric-lang source code into a flat vector of tokens with
indentation tracking (INDENT/DEDENT), pipe-as-newline, comment stripping,
and empty-line detection.
"""
function tokenize(source::String, filename::String="<stdin>")::Vector{Token}
    tokens = Token[]
    indent_stack = Int[0]  # stack of indentation levels; starts at 0
    paren_depth = 0        # inside parens, suppress indent tracking
    prev_was_code = false  # did the previous non-blank line emit code tokens?

    lines = split(source, '\n')

    for (lineno, raw_line) in enumerate(lines)
        # --- strip trailing whitespace (but not leading — we need indent) ---
        line = rstrip(raw_line)

        # --- strip comment (outside strings) ---
        line = strip_comment(line)

        # --- measure indentation ---
        indent = 0
        for ch in line
            if ch == ' '
                indent += 1
            elseif ch == '\t'
                indent += 4  # treat tab as 4 spaces
            else
                break
            end
        end

        content = lstrip(line)

        # --- blank / empty line ---
        if isempty(content)
            if prev_was_code && paren_depth == 0
                push!(tokens, Token(T_EMPTY, "", SourceLocation(filename, lineno, 1)))
                prev_was_code = false
            end
            continue
        end

        # --- indentation changes (only outside parens) ---
        if paren_depth == 0
            if indent > indent_stack[end]
                push!(indent_stack, indent)
                push!(tokens, Token(T_INDENT, "", SourceLocation(filename, lineno, 1)))
            elseif indent < indent_stack[end]
                while indent < indent_stack[end]
                    pop!(indent_stack)
                    push!(tokens, Token(T_DEDENT, "", SourceLocation(filename, lineno, 1)))
                end
            else
                # Same indentation level: emit NEWLINE between consecutive code lines
                if prev_was_code
                    push!(tokens, Token(T_NEWLINE, "", SourceLocation(filename, lineno, 1)))
                end
            end
        end

        # --- scan tokens on this line ---
        line_tokens = scan_line(content, filename, lineno, indent)

        for tok in line_tokens
            if tok.type == T_LPAREN
                paren_depth += 1
            elseif tok.type == T_RPAREN
                paren_depth = max(0, paren_depth - 1)
            end
            push!(tokens, tok)
        end

        prev_was_code = true
    end

    # --- emit remaining DEDENTs ---
    while length(indent_stack) > 1
        pop!(indent_stack)
        push!(tokens, Token(T_DEDENT, "", SourceLocation(filename, length(lines), 1)))
    end

    push!(tokens, Token(T_EOF, "", SourceLocation(filename, length(lines), 1)))
    return tokens
end

"""
Strip a `#` comment from a line, respecting strings.
"""
function strip_comment(line::AbstractString)::String
    in_string = false
    i = 1
    chars = collect(line)
    n = length(chars)
    while i <= n
        ch = chars[i]
        if in_string
            if ch == '\\' && i < n
                i += 2  # skip escaped char
                continue
            elseif ch == '"'
                in_string = false
            end
        else
            if ch == '"'
                in_string = true
            elseif ch == '#'
                return String(chars[1:i-1])
            end
        end
        i += 1
    end
    return String(line)
end

"""
Scan a single (already-stripped) line into tokens.
`base_col` is the column offset from indentation.
"""
function scan_line(content::AbstractString, filename::String, lineno::Int, base_col::Int)::Vector{Token}
    tokens = Token[]
    chars = collect(content)
    n = length(chars)
    i = 1

    while i <= n
        ch = chars[i]
        col = base_col + i  # 1-based column in the original line

        # --- whitespace ---
        if ch == ' ' || ch == '\t'
            i += 1
            continue
        end

        # --- pipe => NEWLINE ---
        if ch == '|'
            push!(tokens, Token(T_NEWLINE, "|", SourceLocation(filename, lineno, col)))
            i += 1
            continue
        end

        # --- single-char tokens ---
        if ch == '('
            push!(tokens, Token(T_LPAREN, "(", SourceLocation(filename, lineno, col)))
            i += 1
            continue
        end
        if ch == ')'
            push!(tokens, Token(T_RPAREN, ")", SourceLocation(filename, lineno, col)))
            i += 1
            continue
        end
        if ch == '='
            push!(tokens, Token(T_ASSIGN, "=", SourceLocation(filename, lineno, col)))
            i += 1
            continue
        end
        if ch == ','
            push!(tokens, Token(T_COMMA, ",", SourceLocation(filename, lineno, col)))
            i += 1
            continue
        end

        # --- spread `...` ---
        if ch == '.' && i + 2 <= n && chars[i+1] == '.' && chars[i+2] == '.'
            push!(tokens, Token(T_SPREAD, "...", SourceLocation(filename, lineno, col)))
            i += 3
            continue
        end

        # --- string literal (with escaped quotes support, Review Issue #2) ---
        if ch == '"'
            str_start = i
            i += 1
            buf = Char[]
            while i <= n
                sc = chars[i]
                if sc == '\\' && i < n
                    nc = chars[i+1]
                    if nc == '"'
                        push!(buf, '"')
                        i += 2
                        continue
                    elseif nc == '\\'
                        push!(buf, '\\')
                        i += 2
                        continue
                    elseif nc == 'n'
                        push!(buf, '\n')
                        i += 2
                        continue
                    elseif nc == 't'
                        push!(buf, '\t')
                        i += 2
                        continue
                    else
                        push!(buf, '\\')
                        push!(buf, nc)
                        i += 2
                        continue
                    end
                elseif sc == '"'
                    i += 1
                    break
                else
                    push!(buf, sc)
                    i += 1
                end
            end
            push!(tokens, Token(T_STRING, String(buf), SourceLocation(filename, lineno, col)))
            continue
        end

        # --- number (possibly negative) ---
        if isdigit(ch) || (ch == '-' && i < n && isdigit(chars[i+1]))
            num_start = i
            i += 1  # consume first char (digit or minus)
            while i <= n && isdigit(chars[i])
                i += 1
            end
            push!(tokens, Token(T_LITERAL, String(chars[num_start:i-1]), SourceLocation(filename, lineno, col)))
            continue
        end

        # --- identifier / keyword ---
        if isletter(ch) || ch == '_'
            id_start = i
            i += 1
            while i <= n && (isletter(chars[i]) || isdigit(chars[i]) || chars[i] == '_')
                i += 1
            end
            word = String(chars[id_start:i-1])
            if word == "as"
                push!(tokens, Token(T_AS, "as", SourceLocation(filename, lineno, col)))
            elseif word == "true"
                push!(tokens, Token(T_TRUE, "true", SourceLocation(filename, lineno, col)))
            elseif word == "false"
                push!(tokens, Token(T_FALSE, "false", SourceLocation(filename, lineno, col)))
            else
                push!(tokens, Token(T_IDENT, word, SourceLocation(filename, lineno, col)))
            end
            continue
        end

        # --- unknown character: skip ---
        i += 1
    end

    return tokens
end
