#include "minilang.h"

Node *node_new(NodeType type, int line) {
    Node *n = calloc(1, sizeof(Node));
    n->type = type;
    n->line = line;
    return n;
}

void node_free(Node *n) {
    if (!n) return;
    switch (n->type) {
        case NODE_STRING: free(n->string.value); break;
        case NODE_ARRAY_LIT:
            for (int i = 0; i < n->array_lit.count; i++) node_free(n->array_lit.items[i]);
            free(n->array_lit.items); break;
        case NODE_VAR: free(n->var.name); break;
        case NODE_VAR_DECL: free(n->var_decl.name); node_free(n->var_decl.value); break;
        case NODE_ASSIGN: free(n->assign.name); node_free(n->assign.value); break;
        case NODE_INDEX_ASSIGN:
            node_free(n->index_assign.target); node_free(n->index_assign.index);
            node_free(n->index_assign.value); break;
        case NODE_BINARY: node_free(n->binary.left); node_free(n->binary.right); break;
        case NODE_UNARY: node_free(n->unary.operand); break;
        case NODE_IF: node_free(n->if_stmt.cond); node_free(n->if_stmt.then_branch);
            node_free(n->if_stmt.else_branch); break;
        case NODE_WHILE: node_free(n->while_stmt.cond); node_free(n->while_stmt.body); break;
        case NODE_RETURN: node_free(n->return_stmt.value); break;
        case NODE_FUNC:
            free(n->func.name);
            for (int i = 0; i < n->func.param_count; i++) free(n->func.params[i]);
            free(n->func.params); node_free(n->func.body); break;
        case NODE_CALL:
            free(n->call.name);
            for (int i = 0; i < n->call.arg_count; i++) node_free(n->call.args[i]);
            free(n->call.args); break;
        case NODE_INDEX: node_free(n->index.array); node_free(n->index.index); break;
        case NODE_PRINT: node_free(n->print.value); break;
        case NODE_BLOCK:
            for (int i = 0; i < n->block.count; i++) node_free(n->block.stmts[i]);
            free(n->block.stmts); break;
        case NODE_EXPR_STMT: node_free(n->expr_stmt.expr); break;
        default: break;
    }
    free(n);
}

Parser *parser_new(Lexer *l) {
    Parser *p = calloc(1, sizeof(Parser));
    p->lexer = l; p->pos = 0;
    p->funcs = NULL; p->func_count = 0; p->func_cap = 0;
    p->globals = NULL; p->global_count = 0; p->global_cap = 0;
    return p;
}

void parser_free(Parser *p) {
    for (int i = 0; i < p->func_count; i++) node_free(p->funcs[i]);
    free(p->funcs);
    for (int i = 0; i < p->global_count; i++) node_free(p->globals[i]);
    free(p->globals);
    free(p);
}

static Token *cur(Parser *p) { return &p->lexer->tokens[p->pos]; }
static Token *peek_tok(Parser *p, int o) { return &p->lexer->tokens[p->pos + o]; }
static Token *advance_p(Parser *p) { return &p->lexer->tokens[p->pos++]; }
static int check(Parser *p, TokenType t) { return cur(p)->type == t; }
static Token *expect(Parser *p, TokenType t, const char *msg) {
    if (!check(p, t)) {
        fprintf(stderr, "Parse error line %d: expected %s, got type %d", cur(p)->line, msg, cur(p)->type);
        if (cur(p)->text) fprintf(stderr, " ('%s')", cur(p)->text);
        fprintf(stderr, "\n"); exit(1);
    }
    return advance_p(p);
}

static Node *parse_expr(Parser *p);
static Node *parse_stmt(Parser *p);
static Node *parse_block(Parser *p);
static Node *parse_postfix(Parser *p);

static Node *parse_primary(Parser *p) {
    Token *t = cur(p);
    if (t->type == TOK_INT) {
        advance_p(p);
        Node *n = node_new(NODE_INT, t->line);
        n->integer.value = t->intval; return n;
    }
    if (t->type == TOK_STRING) {
        advance_p(p);
        Node *n = node_new(NODE_STRING, t->line);
        n->string.value = strdup(t->text); return n;
    }
    if (t->type == TOK_LPAREN) {
        advance_p(p);
        Node *e = parse_expr(p);
        expect(p, TOK_RPAREN, "')'"); return e;
    }
    if (t->type == TOK_LBRACKET) {
        advance_p(p);
        Node **items = NULL; int count = 0, cap = 0;
        if (!check(p, TOK_RBRACKET)) {
            while (1) {
                Node *e = parse_expr(p);
                if (count >= cap) { cap = cap ? cap*2 : 4; items = realloc(items, sizeof(Node*)*cap); }
                items[count++] = e;
                if (check(p, TOK_COMMA)) { advance_p(p); continue; }
                break;
            }
        }
        expect(p, TOK_RBRACKET, "']'");
        Node *n = node_new(NODE_ARRAY_LIT, t->line);
        n->array_lit.items = items; n->array_lit.count = count; return n;
    }
    if (t->type == TOK_IDENT) {
        advance_p(p);
        if (check(p, TOK_LPAREN)) {
            advance_p(p);
            Node **args = NULL; int argc = 0, acap = 0;
            if (!check(p, TOK_RPAREN)) {
                while (1) {
                    Node *a = parse_expr(p);
                    if (argc >= acap) { acap = acap ? acap*2 : 4; args = realloc(args, sizeof(Node*)*acap); }
                    args[argc++] = a;
                    if (check(p, TOK_COMMA)) { advance_p(p); continue; }
                    break;
                }
            }
            expect(p, TOK_RPAREN, "')'");
            Node *n = node_new(NODE_CALL, t->line);
            n->call.name = strdup(t->text);
            n->call.args = args; n->call.arg_count = argc; return n;
        }
        Node *n = node_new(NODE_VAR, t->line);
        n->var.name = strdup(t->text); return n;
    }
    fprintf(stderr, "Parse error line %d: unexpected token", t->line);
    if (t->text) fprintf(stderr, " '%s'", t->text);
    fprintf(stderr, "\n"); exit(1);
}

static Node *parse_postfix(Parser *p) {
    Node *left = parse_primary(p);
    while (check(p, TOK_LBRACKET)) {
        advance_p(p);
        Node *idx = parse_expr(p);
        expect(p, TOK_RBRACKET, "']'");
        Node *n = node_new(NODE_INDEX, left->line);
        n->index.array = left; n->index.index = idx;
        left = n;
    }
    return left;
}

static Node *parse_unary(Parser *p) {
    if (check(p, TOK_MINUS) || check(p, TOK_NOT)) {
        Token *t = advance_p(p);
        Node *operand = parse_unary(p);
        Node *n = node_new(NODE_UNARY, t->line);
        n->unary.operand = operand; n->unary.op = t->type; return n;
    }
    return parse_postfix(p);
}

static Node *parse_mul(Parser *p) {
    Node *left = parse_unary(p);
    while (check(p, TOK_STAR) || check(p, TOK_SLASH) || check(p, TOK_PERCENT)) {
        Token *t = advance_p(p);
        Node *right = parse_unary(p);
        Node *n = node_new(NODE_BINARY, t->line);
        n->binary.left = left; n->binary.right = right; n->binary.op = t->type;
        left = n;
    }
    return left;
}

static Node *parse_add(Parser *p) {
    Node *left = parse_mul(p);
    while (check(p, TOK_PLUS) || check(p, TOK_MINUS)) {
        Token *t = advance_p(p);
        Node *right = parse_mul(p);
        Node *n = node_new(NODE_BINARY, t->line);
        n->binary.left = left; n->binary.right = right; n->binary.op = t->type;
        left = n;
    }
    return left;
}

static Node *parse_comparison(Parser *p) {
    Node *left = parse_add(p);
    while (check(p, TOK_LT) || check(p, TOK_GT) || check(p, TOK_LTE) || check(p, TOK_GTE)) {
        Token *t = advance_p(p);
        Node *right = parse_add(p);
        Node *n = node_new(NODE_BINARY, t->line);
        n->binary.left = left; n->binary.right = right; n->binary.op = t->type;
        left = n;
    }
    return left;
}

static Node *parse_equality(Parser *p) {
    Node *left = parse_comparison(p);
    while (check(p, TOK_EQEQ) || check(p, TOK_NEQ)) {
        Token *t = advance_p(p);
        Node *right = parse_comparison(p);
        Node *n = node_new(NODE_BINARY, t->line);
        n->binary.left = left; n->binary.right = right; n->binary.op = t->type;
        left = n;
    }
    return left;
}

static Node *parse_and(Parser *p) {
    Node *left = parse_equality(p);
    while (check(p, TOK_AND)) {
        Token *t = advance_p(p);
        Node *right = parse_equality(p);
        Node *n = node_new(NODE_BINARY, t->line);
        n->binary.left = left; n->binary.right = right; n->binary.op = t->type;
        left = n;
    }
    return left;
}

static Node *parse_or(Parser *p) {
    Node *left = parse_and(p);
    while (check(p, TOK_OR)) {
        Token *t = advance_p(p);
        Node *right = parse_and(p);
        Node *n = node_new(NODE_BINARY, t->line);
        n->binary.left = left; n->binary.right = right; n->binary.op = t->type;
        left = n;
    }
    return left;
}

static Node *parse_expr(Parser *p) { return parse_or(p); }

static Node *parse_block(Parser *p) {
    expect(p, TOK_LBRACE, "'{'");
    Node **stmts = NULL; int count = 0, cap = 0;
    while (!check(p, TOK_RBRACE) && !check(p, TOK_EOF)) {
        Node *s = parse_stmt(p);
        if (count >= cap) { cap = cap ? cap*2 : 8; stmts = realloc(stmts, sizeof(Node*)*cap); }
        stmts[count++] = s;
    }
    expect(p, TOK_RBRACE, "'}'");
    Node *n = node_new(NODE_BLOCK, 0);
    n->block.stmts = stmts; n->block.count = count; return n;
}

static Node *parse_stmt(Parser *p) {
    Token *t = cur(p);

    if (t->type == TOK_VAR) {
        advance_p(p);
        Token *name = expect(p, TOK_IDENT, "identifier after 'var'");
        expect(p, TOK_EQ, "'=' in var");
        Node *val = parse_expr(p);
        expect(p, TOK_SEMICOLON, "';'");
        Node *n = node_new(NODE_VAR_DECL, t->line);
        n->var_decl.name = strdup(name->text); n->var_decl.value = val; return n;
    }
    if (t->type == TOK_IF) {
        advance_p(p);
        expect(p, TOK_LPAREN, "'('");
        Node *cond = parse_expr(p);
        expect(p, TOK_RPAREN, "')'");
        Node *then_b = parse_stmt(p);
        Node *else_b = NULL;
        if (check(p, TOK_ELSE)) { advance_p(p); else_b = parse_stmt(p); }
        Node *n = node_new(NODE_IF, t->line);
        n->if_stmt.cond = cond; n->if_stmt.then_branch = then_b; n->if_stmt.else_branch = else_b;
        return n;
    }
    if (t->type == TOK_WHILE) {
        advance_p(p);
        expect(p, TOK_LPAREN, "'('");
        Node *cond = parse_expr(p);
        expect(p, TOK_RPAREN, "')'");
        Node *body = parse_stmt(p);
        Node *n = node_new(NODE_WHILE, t->line);
        n->while_stmt.cond = cond; n->while_stmt.body = body; return n;
    }
    if (t->type == TOK_RETURN) {
        advance_p(p);
        Node *val = NULL;
        if (!check(p, TOK_SEMICOLON)) val = parse_expr(p);
        expect(p, TOK_SEMICOLON, "';'");
        Node *n = node_new(NODE_RETURN, t->line);
        n->return_stmt.value = val; return n;
    }
    if (t->type == TOK_PRINT || t->type == TOK_PRINTLN) {
        advance_p(p);
        Node *val = parse_expr(p);
        expect(p, TOK_SEMICOLON, "';'");
        Node *n = node_new(NODE_PRINT, t->line);
        n->print.value = val; n->print.newline = (t->type == TOK_PRINTLN); return n;
    }
    if (t->type == TOK_BREAK) {
        advance_p(p);
        expect(p, TOK_SEMICOLON, "';'");
        return node_new(NODE_BREAK, t->line);
    }
    if (t->type == TOK_LBRACE) return parse_block(p);

    // Assignment: IDENT '='  (lookahead, no consume)
    if (t->type == TOK_IDENT && peek_tok(p, 1)->type == TOK_EQ) {
        Token *name = advance_p(p);
        advance_p(p); // '='
        Node *val = parse_expr(p);
        expect(p, TOK_SEMICOLON, "';'");
        Node *n = node_new(NODE_ASSIGN, t->line);
        n->assign.name = strdup(name->text); n->assign.value = val; return n;
    }
    // Index assignment: IDENT '[' ... ']' '='
    if (t->type == TOK_IDENT && peek_tok(p, 1)->type == TOK_LBRACKET) {
        Node *left = parse_postfix(p);
        if (left->type == NODE_INDEX && check(p, TOK_EQ)) {
            advance_p(p);
            Node *val = parse_expr(p);
            expect(p, TOK_SEMICOLON, "';'");
            Node *n = node_new(NODE_INDEX_ASSIGN, t->line);
            n->index_assign.target = left->index.array;
            n->index_assign.index = left->index.index;
            n->index_assign.value = val;
            free(left); return n;
        }
        // Expression statement starting with index access
        expect(p, TOK_SEMICOLON, "';'");
        Node *n = node_new(NODE_EXPR_STMT, t->line);
        n->expr_stmt.expr = left; return n;
    }

    // Expression statement
    Node *e = parse_expr(p);
    expect(p, TOK_SEMICOLON, "';'");
    Node *n = node_new(NODE_EXPR_STMT, t->line);
    n->expr_stmt.expr = e; return n;
}

static Node *parse_func(Parser *p) {
    Token *t = expect(p, TOK_FUNC, "'func'");
    Token *name = expect(p, TOK_IDENT, "function name");
    expect(p, TOK_LPAREN, "'('");
    char **params = NULL; int pcount = 0, pcap = 0;
    if (!check(p, TOK_RPAREN)) {
        while (1) {
            Token *pn = expect(p, TOK_IDENT, "param name");
            if (pcount >= pcap) { pcap = pcap ? pcap*2 : 4; params = realloc(params, sizeof(char*)*pcap); }
            params[pcount++] = strdup(pn->text);
            if (check(p, TOK_COMMA)) { advance_p(p); continue; }
            break;
        }
    }
    expect(p, TOK_RPAREN, "')'");
    Node *body = parse_block(p);
    Node *n = node_new(NODE_FUNC, t->line);
    n->func.name = strdup(name->text);
    n->func.params = params; n->func.param_count = pcount;
    n->func.body = body; return n;
}

void parse(Parser *p) {
    while (!check(p, TOK_EOF)) {
        if (check(p, TOK_FUNC)) {
            Node *f = parse_func(p);
            if (p->func_count >= p->func_cap) {
                p->func_cap = p->func_cap ? p->func_cap*2 : 8;
                p->funcs = realloc(p->funcs, sizeof(Node*)*p->func_cap);
            }
            p->funcs[p->func_count++] = f;
        } else if (check(p, TOK_VAR)) {
            // Top-level var declaration
            advance_p(p);
            Token *name = expect(p, TOK_IDENT, "identifier after 'var'");
            expect(p, TOK_EQ, "'=' in var");
            Node *val = parse_expr(p);
            expect(p, TOK_SEMICOLON, "';'");
            Node *n = node_new(NODE_VAR_DECL, name->line);
            n->var_decl.name = strdup(name->text);
            n->var_decl.value = val;
            if (p->global_count >= p->global_cap) {
                p->global_cap = p->global_cap ? p->global_cap*2 : 16;
                p->globals = realloc(p->globals, sizeof(Node*)*p->global_cap);
            }
            p->globals[p->global_count++] = n;
        } else {
            fprintf(stderr, "Parse error line %d: expected 'func' or 'var' at top level\n", cur(p)->line);
            exit(1);
        }
    }
}
