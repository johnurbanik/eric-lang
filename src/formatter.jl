# AST Pretty-Printer (Formatter)
# "The formatter is refreshingly free of academic PL theory."
#
# This is the only component that doesn't use unification, continuations,
# laziness, or reversibility. It just prints strings. Like a normal program.

function format_ast(node::ASTNode, indent::Int=0)::String
    return _format(node, indent)
end

function _format(node::LiteralNode, indent::Int)::String
    v = node.value
    if v isa String
        return "\"$v\""
    elseif v isa Bool
        return v ? "true" : "false"
    else
        return string(v)
    end
end

function _format(node::IdentifierNode, indent::Int)::String
    return node.name
end

function _format(node::ExpressionNode, indent::Int)::String
    if isempty(node.args)
        return node.identifier.name
    end
    args_str = join([_format(a, indent) for a in node.args], ", ")
    return "$(node.identifier.name)($args_str)"
end

function _format(node::CollectionItemNode, indent::Int)::String
    prefix = node.expand ? "..." : ""
    return prefix * _format(node.item, indent)
end

function _format(node::CollectionNode, indent::Int)::String
    items_str = join([_format(i, indent) for i in node.items], ", ")
    full = "($items_str)"
    if length(full) > 80
        # Multi-line formatting for long collections
        lines = String[]
        push!(lines, "(")
        for (i, item) in enumerate(node.items)
            suffix = i < length(node.items) ? "," : ""
            push!(lines, "  " * repeat(" ", indent) * _format(item, indent) * suffix)
        end
        push!(lines, repeat(" ", indent) * ")")
        return join(lines, "\n")
    end
    return full
end

function _format(node::StatementNode, indent::Int)::String
    expr_str = _format(node.expr, indent)

    # FIX for review issue #6: handle names as a LIST, not a single node
    # The Python code crashed here because it did name.name on a list
    if !isempty(node.names)
        name_strs = [n.name for n in node.names]
        padding = max(1, 30 - indent - length(expr_str))
        expr_str *= repeat(" ", padding) * "as " * join(name_strs, ", ")
    end

    if node.block !== nothing
        block_str = _format(node.block, indent + 4)
        return expr_str * "\n" * repeat(" ", indent + 4) * block_str
    end

    return expr_str
end

function _format(node::BlockNode, indent::Int)::String
    return join([_format(s, indent) for s in node.stmts], "\n" * repeat(" ", indent))
end

function _format(node::ModuleNode, indent::Int)::String
    return join([_format(b, indent) for b in node.blocks], "\n\n" * repeat(" ", indent))
end

function _format(node::AssignmentNode, indent::Int)::String
    left_str = _format(node.left, indent)
    right_str = _format(node.right, indent + 4)
    if contains(right_str, "\n")
        return "$left_str =\n" * repeat(" ", indent + 4) * right_str
    else
        return "$left_str = $right_str"
    end
end
