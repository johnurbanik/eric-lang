# AST Node Types
# "Julia's type system for the AST -- algebraic data types via manual dispatch"

abstract type ASTNode end

struct LiteralNode <: ASTNode
    value::Any
    location::SourceLocation
end
LiteralNode(value) = LiteralNode(value, SourceLocation())

struct IdentifierNode <: ASTNode
    name::String
    location::SourceLocation
end
IdentifierNode(name::String) = IdentifierNode(name, SourceLocation())

struct ExpressionNode <: ASTNode
    identifier::IdentifierNode
    args::Vector{ASTNode}
    location::SourceLocation
end

struct CollectionItemNode <: ASTNode
    item::ASTNode
    expand::Bool
    location::SourceLocation
end

struct CollectionNode <: ASTNode
    items::Vector{CollectionItemNode}
    location::SourceLocation
end

struct StatementNode <: ASTNode
    expr::ASTNode
    names::Vector{IdentifierNode}
    block::Union{ASTNode, Nothing}
    location::SourceLocation
end

struct BlockNode <: ASTNode
    stmts::Vector{StatementNode}
    location::SourceLocation
end

struct ModuleNode <: ASTNode
    blocks::Vector{BlockNode}
    location::SourceLocation
end

struct AssignmentNode <: ASTNode
    left::ASTNode
    right::ASTNode
    location::SourceLocation
end
