# Recursive descent parser for eric-lang
# Matches the Python parser behaviour exactly.

struct ParseError <: Exception
    message::String
    location::SourceLocation
end

Base.showerror(io::IO, e::ParseError) = print(io, "ParseError at $(e.location): $(e.message)")

mutable struct Parser
    tokens::Vector{Token}
    pos::Int
end

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

"""Return the current token (without advancing)."""
function current(p::Parser)::Token
    if p.pos > length(p.tokens)
        return p.tokens[end]  # should be EOF
    end
    return p.tokens[p.pos]
end

"""Advance to the next token and return the consumed token."""
function advance!(p::Parser)::Token
    tok = current(p)
    p.pos += 1
    return tok
end

"""Check whether the current token matches a given type or value."""
function peek(p::Parser, tt::TokenType)::Bool
    return current(p).type == tt
end

function peek(p::Parser, value::String)::Bool
    return current(p).value == value
end

"""If the current token's value matches `value`, consume it and return true."""
function accept!(p::Parser, tt::TokenType)::Bool
    if current(p).type == tt
        advance!(p)
        return true
    end
    return false
end

function accept!(p::Parser, value::String)::Bool
    if current(p).value == value
        advance!(p)
        return true
    end
    return false
end

"""Consume the current token if it matches; otherwise throw ParseError."""
function expect!(p::Parser, tt::TokenType)::Token
    tok = current(p)
    if tok.type != tt
        throw(ParseError("expected $(tt), got $(tok.type) ($(repr(tok.value)))", tok.location))
    end
    return advance!(p)
end

function expect!(p::Parser, value::String)::Token
    tok = current(p)
    if tok.value != value
        throw(ParseError("expected $(repr(value)), got $(repr(tok.value))", tok.location))
    end
    return advance!(p)
end

# ---------------------------------------------------------------------------
# Grammar
# ---------------------------------------------------------------------------

"""
    parse_module!(p) -> ModuleNode

Module = Block (EMPTY Block)*
"""
function parse_module!(p::Parser)::ModuleNode
    loc = current(p).location
    blocks = BlockNode[]

    push!(blocks, parse_block!(p))

    while peek(p, T_EMPTY)
        advance!(p)
        # skip consecutive EMPTYs
        while peek(p, T_EMPTY)
            advance!(p)
        end
        # don't parse a block if we've hit EOF / DEDENT
        if peek(p, T_EOF) || peek(p, T_DEDENT)
            break
        end
        push!(blocks, parse_block!(p))
    end

    return ModuleNode(blocks, loc)
end

"""
    parse_block!(p) -> BlockNode

Block = Stmt (NEWLINE Stmt)*
"""
function parse_block!(p::Parser)::BlockNode
    loc = current(p).location
    stmts = StatementNode[]

    push!(stmts, parse_stmt!(p))

    while peek(p, T_NEWLINE)
        advance!(p)
        push!(stmts, parse_stmt!(p))
    end

    return BlockNode(stmts, loc)
end

"""
    parse_stmt!(p) -> StatementNode

Stmt = Expr [ '=' Expr ]
     | Expr [ '=' INDENT Module DEDENT ]
     | Expr [ 'as' Ident (',' Ident)* ] [ INDENT Module DEDENT ]
"""
function parse_stmt!(p::Parser)::StatementNode
    loc = current(p).location
    expr = parse_expr!(p)
    names = IdentifierNode[]
    block = nothing

    if peek(p, T_ASSIGN)
        advance!(p)
        # Assignment: either indented block or simple expression
        if peek(p, T_INDENT)
            advance!(p)
            block = parse_module!(p)
            expect!(p, T_DEDENT)
            return StatementNode(expr, names, block, loc)
        else
            rhs = parse_expr!(p)
            return StatementNode(AssignmentNode(expr, rhs, loc), names, nothing, loc)
        end
    end

    # Optional `as name, name, ...`
    if peek(p, T_AS)
        advance!(p)
        nametok = expect!(p, T_IDENT)
        push!(names, IdentifierNode(nametok.value, nametok.location))
        while peek(p, T_COMMA)
            advance!(p)
            nametok = expect!(p, T_IDENT)
            push!(names, IdentifierNode(nametok.value, nametok.location))
        end
    end

    # Optional indented block
    if peek(p, T_INDENT)
        advance!(p)
        block = parse_module!(p)
        expect!(p, T_DEDENT)
    end

    return StatementNode(expr, names, block, loc)
end

"""
    parse_expr!(p) -> ASTNode

Expr = Literal | List | Identifier [ '(' Expr (',' Expr)* ')' ]
"""
function parse_expr!(p::Parser)::ASTNode
    tok = current(p)

    # Literal
    if tok.type == T_LITERAL || tok.type == T_STRING || tok.type == T_TRUE || tok.type == T_FALSE
        return parse_literal!(p)
    end

    # List
    if tok.type == T_LPAREN
        return parse_list!(p)
    end

    # Identifier (possibly with arguments)
    if tok.type == T_IDENT
        idtok = advance!(p)
        ident = IdentifierNode(idtok.value, idtok.location)

        if peek(p, T_LPAREN)
            advance!(p)  # consume '('
            args = ASTNode[]
            if !peek(p, T_RPAREN)
                push!(args, parse_expr!(p))
                while peek(p, T_COMMA)
                    advance!(p)
                    push!(args, parse_expr!(p))
                end
            end
            expect!(p, T_RPAREN)
            return ExpressionNode(ident, args, idtok.location)
        end

        return ident
    end

    throw(ParseError("unexpected token $(tok.type) ($(repr(tok.value)))", tok.location))
end

"""
    parse_literal!(p) -> LiteralNode

Literal = integer | string | true | false
"""
function parse_literal!(p::Parser)::LiteralNode
    tok = advance!(p)
    if tok.type == T_LITERAL
        return LiteralNode(parse(Int, tok.value), tok.location)
    elseif tok.type == T_STRING
        return LiteralNode(tok.value, tok.location)
    elseif tok.type == T_TRUE
        return LiteralNode(true, tok.location)
    elseif tok.type == T_FALSE
        return LiteralNode(false, tok.location)
    end
    throw(ParseError("expected literal, got $(tok.type)", tok.location))
end

"""
    parse_list!(p) -> CollectionNode

List = '(' [ Item (',' Item)* ] ')'
Item = Expr [ '...' ]
"""
function parse_list!(p::Parser)::CollectionNode
    loc = current(p).location
    expect!(p, T_LPAREN)
    items = CollectionItemNode[]

    if !peek(p, T_RPAREN)
        item_expr = parse_expr!(p)
        expand = false
        if peek(p, T_SPREAD)
            advance!(p)
            expand = true
        end
        push!(items, CollectionItemNode(item_expr, expand, item_expr isa ASTNode ? loc : loc))

        while peek(p, T_COMMA)
            advance!(p)
            if peek(p, T_RPAREN)
                break  # trailing comma
            end
            item_expr = parse_expr!(p)
            expand = false
            if peek(p, T_SPREAD)
                advance!(p)
                expand = true
            end
            push!(items, CollectionItemNode(item_expr, expand, loc))
        end
    end

    expect!(p, T_RPAREN)
    return CollectionNode(items, loc)
end

# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

"""
    parse_eric(tokens::Vector{Token}) -> ModuleNode

Parse a flat token stream into an eric-lang AST.
"""
function parse_eric(tokens::Vector{Token})::ModuleNode
    p = Parser(tokens, 1)
    mod = parse_module!(p)
    return mod
end
