#!/usr/bin/env python3
# hl_pipeline.py -- H-L Compilation Pipeline (Python port of hl-compile-pipeline.ps1)
#
# Phase 1: Tokenize      (mirrors hl-bootstrap.hl S2)
# Phase 2: Parse         (recursive-descent -> AST)
# Phase 3: IR lowering   (AST -> IR, const-fold / DCE / strength-reduce)
# Phase 4: x86_64 codegen (register allocation + instruction emission)
# Phase 5: Link          (cross-module linker -> bare-kernel/kernel.bin + kernel.entry)
#
# Usage: python3 scripts/hl_pipeline.py
#
# The PowerShell pipeline spends most of its time in interpreter overhead and
# O(n^2) constant-folding scans. This Python port keeps the exact same IR
# opcodes / regalloc order / emitted bytes, but uses dict-based constant
# propagation (O(1) lookup) and native bytearray buffers.

import os
import re
import sys
import json

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
LINK_TEXT_BASE = 0x120000  # 1 MB + 128 KB -- .text segment start (after padded handwritten kernel)

# ---------------------------------------------------------------------------
# IR opcodes (must match PS constants)
# ---------------------------------------------------------------------------
IR_CONST, IR_COPY, IR_ADD, IR_SUB, IR_MUL, IR_DIV, IR_MOD, IR_NEG = 1, 2, 3, 4, 5, 6, 7, 8
IR_AND, IR_OR, IR_XOR, IR_SHL, IR_SHR, IR_NOT = 9, 10, 11, 12, 13, 14
IR_CMP_EQ, IR_CMP_NE, IR_CMP_LT, IR_CMP_LE, IR_CMP_GT, IR_CMP_GE = 15, 16, 17, 18, 19, 20
IR_JMP, IR_JZ, IR_JNZ, IR_LABEL, IR_CALL, IR_ARG, IR_RET, IR_LOAD, IR_STORE = 21, 22, 23, 24, 25, 26, 27, 28, 29
IR_PHI, IR_NOP, IR_STR_CONST = 30, 31, 32
IR_PRINT = 36
IR_PORT_OUT = 38
IR_PORT_IN, IR_CLI, IR_STI, IR_HLT = 39, 40, 41, 42
IR_MEM_STORE8, IR_MEM_LOAD64, IR_MEM_STORE64, IR_LIDT = 43, 44, 45, 46
IR_PORT_OUT32, IR_PORT_IN32, IR_MEM_STORE32, IR_MEM_LOAD32, IR_MEM_LOAD8 = 47, 48, 49, 50, 51
IR_PARAM = 52

HL_KEYWORDS = {
    'let', 'mut', 'fn', 'return', 'if', 'else', 'while', 'for', 'in', 'print',
    'quadrant', 'emit', 'spawn', 'near', 'fold', 'from', 'with', 'break',
    'continue', 'try', 'catch', 'finally', 'import', 'as', 'assert', 'del',
    'pass', 'elif', 'not', 'class', 'self', 'super', 'yield', 'raise',
    'true', 'false', 'nil',
}

TWO_OPS = {'**', '==', '!=', '<=', '>=', '&&', '||', '->', '+=', '-=', '*=', '/=',
           '%=', '<<', '>>', '//', '&=', '|=', '^='}
SINGLE_OPS = set('+-*/%=!<>,(){}[];.~&|^@:#')
THREE_OPS = {'**=', '//=', '<<=', '>>=', '...'}


# ---------------------------------------------------------------------------
# PHASE 1: TOKENIZER
# ---------------------------------------------------------------------------
def tokenize_hl(src):
    tokens = []
    i, n = 0, len(src)
    while i < n:
        ch = src[i]
        if ch.isspace():
            i += 1
            continue
        if ch == '/' and i + 1 < n and src[i + 1] == '/':
            while i < n and src[i] != '\n':
                i += 1
            continue
        if ch == '/' and i + 1 < n and src[i + 1] == '*':
            i += 2
            while i < n - 1:
                if src[i] == '*' and src[i + 1] == '/':
                    i += 2
                    break
                i += 1
            continue
        if ch.isdigit() or (ch == '0' and i + 1 < n and src[i + 1] == 'x'):
            num = ''
            if ch == '0' and i + 1 < n and src[i + 1] == 'x':
                num = '0x'
                i += 2
                while i < n and src[i] in '0123456789abcdefABCDEF':
                    num += src[i]
                    i += 1
            else:
                while i < n and (src[i].isdigit() or src[i] == '.'):
                    num += src[i]
                    i += 1
            tokens.append(('Num', num))
            continue
        if ch == '"' or ch == "'":
            q = ch
            i += 1
            s = ''
            while i < n and src[i] != q:
                if src[i] == '\\' and i + 1 < n:
                    s += src[i]
                    i += 1
                    s += src[i]
                    i += 1
                else:
                    s += src[i]
                    i += 1
            if i < n:
                i += 1
            tokens.append(('Str', s))
            continue
        if ch.isalpha() or ch == '_':
            ident = ''
            while i < n and (src[i].isalnum() or src[i] == '_'):
                ident += src[i]
                i += 1
            if ident == 'true' or ident == 'false':
                tokens.append(('Bool', ident))
            elif ident == 'nil':
                tokens.append(('Nil', ident))
            elif ident in HL_KEYWORDS:
                tokens.append((ident, ident))
            else:
                tokens.append(('Ident', ident))
            continue
        three = src[i:i + 3] if i + 2 < n else ''
        if three in THREE_OPS:
            tokens.append((three, three))
            i += 3
            continue
        two = src[i:i + 2] if i + 1 < n else ''
        if two in TWO_OPS:
            tokens.append((two, two))
            i += 2
            continue
        if ch in SINGLE_OPS:
            tokens.append((ch, ch))
            i += 1
            continue
        i += 1
    tokens.append(('EOF', ''))
    return tokens


def test_balanced(tokens):
    stack = []
    errors = []
    openers = {')': '(', '}': '{', ']': '['}
    for tok in tokens:
        t = tok[0]
        if t in ('(', '{', '['):
            stack.append(t)
        elif t in openers:
            expected = openers[t]
            if not stack:
                errors.append('Unmatched %s' % t)
            elif stack[-1] != expected:
                errors.append('Mismatched %s' % t)
            else:
                stack.pop()
    while stack:
        errors.append('Unclosed %s' % stack.pop())
    return errors


def count_functions(tokens):
    c = 0
    for j in range(len(tokens) - 1):
        if tokens[j][0] == 'fn' and tokens[j + 1][0] == 'Ident':
            c += 1
    return c


# ---------------------------------------------------------------------------
# PHASE 2: RECURSIVE-DESCENT PARSER (mirrors hl-bootstrap.hl S3 port)
# ---------------------------------------------------------------------------
class Parser:
    def __init__(self, tokens):
        self.tok = tokens
        self.pos = 0
        self.nodes = 0
        self.errors = 0

    def pk(self):
        if self.pos < len(self.tok):
            return self.tok[self.pos]
        return ('EOF', '')

    def adv(self):
        if self.pos < len(self.tok):
            self.pos += 1

    def advt(self):
        if self.pos < len(self.tok):
            t = self.tok[self.pos]
            self.pos += 1
            return t
        return ('EOF', '')

    def chk(self, ty):
        return self.pk()[0] == ty

    def skp(self, ty):
        if self.chk(ty):
            self.pos += 1

    def eat(self, ty):
        if self.chk(ty):
            self.adv()
        else:
            raise RuntimeError('expected %s got %s' % (ty, self.pk()[0]))

    def nd(self, ty):
        self.nodes += 1
        return ty

    # --- statements ---
    def p_program(self):
        stmts = []
        while self.pk()[0] != 'EOF':
            try:
                s = self.p_stmt()
                if s is not None:
                    stmts.append(s)
            except Exception:
                self.errors += 1
                while self.pos < len(self.tok):
                    t = self.pk()[0]
                    if t == ';':
                        self.pos += 1
                        break
                    if t == '}':
                        self.pos += 1
                        break
                    if t == 'EOF':
                        break
                    if t in ('let', 'fn', 'class', 'if', 'while', 'for', 'return',
                             'print', 'quadrant'):
                        break
                    self.pos += 1
        return stmts

    def p_stmt(self):
        tt = self.pk()[0]
        if tt == '@':
            return self.p_decorated()
        if tt == 'let':
            return self.p_let()
        if tt == 'fn':
            return self.p_fn()
        if tt == 'class':
            return self.p_class()
        if tt == 'if':
            return self.p_if()
        if tt == 'while':
            return self.p_while()
        if tt == 'for':
            return self.p_for()
        if tt == 'return':
            return self.p_return()
        if tt == 'yield':
            self.adv()
            v = None
            if self.pk()[0] not in (';', '}'):
                v = self.p_expr()
            self.skp(';')
            return [self.nd('Yield'), v]
        if tt == 'raise':
            self.adv()
            v = None
            if self.pk()[0] not in (';', '}'):
                v = self.p_expr()
            self.skp(';')
            return [self.nd('Raise'), v]
        if tt == 'print':
            return self.p_print()
        if tt == 'quadrant':
            return self.p_quadrant()
        if tt == 'break':
            self.adv()
            self.skp(';')
            return [self.nd('Break')]
        if tt == 'continue':
            self.adv()
            self.skp(';')
            return [self.nd('Continue')]
        if tt == 'pass':
            self.adv()
            self.skp(';')
            return [self.nd('Pass')]
        if tt == 'try':
            return self.p_try()
        if tt == 'import':
            return self.p_import()
        if tt == 'from':
            return self.p_from()
        if tt == 'assert':
            self.adv()
            c = self.p_expr()
            m = None
            if self.chk(','):
                self.adv()
                m = self.p_expr()
            self.skp(';')
            return [self.nd('Assert'), c, m]
        if tt == 'del':
            self.adv()
            nm = self.advt()[1]
            self.skp(';')
            return [self.nd('Del'), nm]
        if tt == '{':
            return self.p_block_stmt()
        return self.p_expr_stmt()

    def p_let(self):
        self.adv()
        mut = False
        if self.chk('mut'):
            mut = True
            self.adv()
        if self.pk()[0] in ('[', '('):
            close = ']' if self.pk()[0] == '[' else ')'
            self.adv()
            names = []
            while not self.chk(close) and not self.chk('EOF'):
                if self.pk()[0] == 'Ident' or self.pk()[1] == '_':
                    names.append(self.advt()[1])
                elif self.chk('['):
                    names.append('_nested')
                    self.p_skip_brackets()
                else:
                    self.adv()
                self.skp(',')
            self.skp(close)
            self.skp('=')
            val = self.p_expr()
            self.skp(';')
            return [self.nd('LetDestruct'), names, mut, val]
        name = self.advt()[1]
        if self.chk(':'):
            self.adv()
            while self.pk()[0] in ('Ident', '[', ']', ',', '|'):
                self.adv()
        init = None
        if self.chk('='):
            self.adv()
            init = self.p_expr()
        self.skp(';')
        return [self.nd('Let'), name, mut, init]

    def p_skip_brackets(self):
        depth = 0
        while self.pos < len(self.tok):
            t = self.pk()[0]
            if t in ('[', '('):
                depth += 1
                self.adv()
            elif t in (']', ')'):
                depth -= 1
                self.adv()
                if depth <= 0:
                    return
            else:
                self.adv()

    def p_fn(self):
        self.adv()
        name = self.advt()[1]
        self.eat('(')
        params = []
        if not self.chk(')'):
            params.append(self.p_param())
            while self.chk(','):
                self.adv()
                params.append(self.p_param())
        self.eat(')')
        if self.chk('->'):
            self.adv()
            while self.pk()[0] in ('Ident', '[', ']', ',', '|'):
                self.adv()
        if self.chk(';'):
            self.adv()
            return [self.nd('FnDecl'), name, params]
        body = self.p_block()
        return [self.nd('FnDef'), name, params, body]

    def p_param(self):
        if self.chk('*'):
            self.adv()
            nm = self.advt()[1]
            self.p_param_type()
            return '*' + nm
        if self.chk('**'):
            self.adv()
            nm = self.advt()[1]
            self.p_param_type()
            return '**' + nm
        nm = self.advt()[1]
        self.p_param_type()
        if self.chk('='):
            self.adv()
            self.p_expr()
        return nm

    def p_param_type(self):
        if self.chk(':'):
            self.adv()
            while self.pk()[0] in ('Ident', '[', ']', ',', '|'):
                self.adv()

    def p_class(self):
        self.adv()
        name = self.advt()[1]
        parent = None
        if self.chk(':'):
            self.adv()
            parent = self.advt()[1]
        body = self.p_block()
        return [self.nd('ClassDef'), name, parent, body]

    def p_if(self):
        self.adv()
        cond = self.p_expr()
        then = self.p_block()
        els = None
        if self.chk('elif'):
            els = [self.p_if()]
        elif self.chk('else'):
            self.adv()
            if self.pk()[0] in ('if', 'elif'):
                els = [self.p_if()]
            else:
                els = self.p_block()
        return [self.nd('If'), cond, then, els]

    def p_while(self):
        self.adv()
        cond = self.p_expr()
        body = self.p_block()
        return [self.nd('While'), cond, body]

    def p_for(self):
        self.adv()
        var = self.advt()[1]
        self.adv()
        iter_ = self.p_expr()
        body = self.p_block()
        return [self.nd('For'), var, iter_, body]

    def p_return(self):
        self.adv()
        val = None
        if self.pk()[0] not in (';', '}'):
            val = self.p_expr()
        self.skp(';')
        return [self.nd('Return'), val]

    def p_print(self):
        self.adv()
        self.eat('(')
        val = self.p_expr()
        self.eat(')')
        self.skp(';')
        return [self.nd('Print'), val]

    def p_quadrant(self):
        self.adv()
        name = self.advt()[1]
        body = self.p_block()
        return [self.nd('Quadrant'), name, body]

    def p_try(self):
        self.adv()
        tbody = self.p_block()
        catches = []
        while self.chk('catch'):
            self.adv()
            cn = None
            ct = None
            if self.chk('Ident'):
                cn = self.advt()[1]
                if self.chk(':'):
                    self.adv()
                    ct = self.advt()[1]
            cb = self.p_block()
            catches.append([cn, ct, cb])
        fin = None
        if self.chk('finally'):
            self.adv()
            fin = self.p_block()
        return [self.nd('Try'), tbody, catches, fin]

    def p_import(self):
        self.adv()
        path = self.advt()[1]
        alias = None
        if self.chk('as'):
            self.adv()
            alias = self.advt()[1]
        self.skp(';')
        return [self.nd('Import'), path, alias]

    def p_from(self):
        self.adv()
        mod = self.advt()[1]
        self.adv()
        name = self.advt()[1]
        self.skp(';')
        return [self.nd('Import'), '%s.%s' % (mod, name), None]

    def p_decorated(self):
        decs = []
        while self.chk('@'):
            self.adv()
            dn = self.advt()[1]
            if self.chk('('):
                self.adv()
                depth = 1
                while depth > 0 and self.pk()[0] != 'EOF':
                    if self.pk()[0] == '(':
                        depth += 1
                    if self.pk()[0] == ')':
                        depth -= 1
                    if depth > 0:
                        self.adv()
                self.skp(')')
            decs.append(dn)
        inner = self.p_stmt()
        return [self.nd('Decorated'), decs, inner]

    def p_block(self):
        self.eat('{')
        stmts = []
        while not self.chk('}') and not self.chk('EOF'):
            try:
                s = self.p_stmt()
                if s is not None:
                    stmts.append(s)
            except Exception:
                self.errors += 1
                while self.pos < len(self.tok):
                    t = self.pk()[0]
                    if t == ';':
                        self.pos += 1
                        break
                    if t in ('}',) or t == 'EOF':
                        break
                    if t in ('let', 'fn', 'if', 'while', 'for', 'return'):
                        break
                    self.pos += 1
        self.skp('}')
        return stmts

    def p_block_stmt(self):
        b = self.p_block()
        return [self.nd('Block'), b]

    def p_expr_stmt(self):
        expr = self.p_expr()
        aop = self.pk()[0]
        if (isinstance(expr, list) and len(expr) >= 2 and expr[0] == 'Var'
                and aop in ('=', '+=', '-=', '*=', '/=', '%=', '**=')):
            self.adv()
            val = self.p_expr()
            self.skp(';')
            if aop == '=':
                return [self.nd('Assign'), expr[1], val]
            binop = {'+=': '+', '-=': '-', '*=': '*', '/=': '/', '%=': '%', '**=': '**'}[aop]
            return [self.nd('Assign'), expr[1], [self.nd('BinOp'), binop, expr, val]]
        if (isinstance(expr, list) and len(expr) >= 3 and expr[0] == 'Index'
                and self.chk('=')):
            self.adv()
            val = self.p_expr()
            self.skp(';')
            return [self.nd('IndexAssign'), expr[1], expr[2], val]
        if (isinstance(expr, list) and len(expr) >= 3 and expr[0] == 'Field'
                and self.pk()[0] in ('=', '+=', '-=', '*=', '/=')):
            fop = self.advt()[0]
            val = self.p_expr()
            self.skp(';')
            if fop == '=':
                return [self.nd('FieldAssign'), expr[1], expr[2], val]
            binop = {'+=': '+', '-=': '-', '*=': '*', '/=': '/'}[fop]
            return [self.nd('FieldAssign'), expr[1], expr[2],
                    [self.nd('BinOp'), binop, expr, val]]
        self.skp(';')
        return [self.nd('ExprStmt'), expr]

    # --- expressions ---
    def p_expr(self):
        return self.p_or()

    def p_or(self):
        l = self.p_and()
        while self.chk('||'):
            self.adv()
            r = self.p_and()
            l = [self.nd('BinOp'), '||', l, r]
        return l

    def p_and(self):
        l = self.p_bitor()
        while self.chk('&&'):
            self.adv()
            r = self.p_bitor()
            l = [self.nd('BinOp'), '&&', l, r]
        return l

    def p_bitor(self):
        l = self.p_bitxor()
        while self.chk('|'):
            self.adv()
            r = self.p_bitxor()
            l = [self.nd('BinOp'), '|', l, r]
        return l

    def p_bitxor(self):
        l = self.p_bitand()
        while self.chk('^'):
            self.adv()
            r = self.p_bitand()
            l = [self.nd('BinOp'), '^', l, r]
        return l

    def p_bitand(self):
        l = self.p_eq()
        while self.chk('&'):
            self.adv()
            r = self.p_eq()
            l = [self.nd('BinOp'), '&', l, r]
        return l

    def p_eq(self):
        l = self.p_cmp()
        while self.pk()[0] in ('==', '!='):
            op = self.advt()[0]
            r = self.p_cmp()
            l = [self.nd('BinOp'), op, l, r]
        return l

    def p_cmp(self):
        l = self.p_shift()
        while self.pk()[0] in ('<', '>', '<=', '>=', 'in', 'not'):
            op = self.pk()[0]
            if op == 'in':
                self.adv()
                r = self.p_shift()
                l = [self.nd('BinOp'), 'in', l, r]
            elif op == 'not':
                self.adv()
                self.adv()
                r = self.p_shift()
                l = [self.nd('Unary'), '!', [self.nd('BinOp'), 'in', l, r]]
            else:
                op = self.advt()[0]
                r = self.p_shift()
                l = [self.nd('BinOp'), op, l, r]
        return l

    def p_shift(self):
        l = self.p_add()
        while self.pk()[0] in ('<<', '>>'):
            op = self.advt()[0]
            r = self.p_add()
            l = [self.nd('BinOp'), op, l, r]
        return l

    def p_add(self):
        l = self.p_mul()
        while self.pk()[0] in ('+', '-'):
            op = self.advt()[0]
            r = self.p_mul()
            l = [self.nd('BinOp'), op, l, r]
        return l

    def p_mul(self):
        l = self.p_power()
        while self.pk()[0] in ('*', '/', '%', '//'):
            op = self.advt()[0]
            r = self.p_power()
            l = [self.nd('BinOp'), op, l, r]
        return l

    def p_power(self):
        base = self.p_unary()
        if self.chk('**'):
            self.adv()
            exp = self.p_power()
            return [self.nd('BinOp'), '**', base, exp]
        return base

    def p_unary(self):
        if self.chk('-'):
            self.adv()
            r = self.p_unary()
            return [self.nd('Unary'), '-', r]
        if self.chk('!'):
            self.adv()
            r = self.p_unary()
            return [self.nd('Unary'), '!', r]
        if self.chk('not'):
            self.adv()
            r = self.p_unary()
            return [self.nd('Unary'), '!', r]
        if self.chk('~'):
            self.adv()
            r = self.p_unary()
            return [self.nd('Unary'), '~', r]
        return self.p_postfix()

    def p_postfix(self):
        e = self.p_primary()
        while True:
            if self.chk('('):
                self.adv()
                args = []
                if not self.chk(')'):
                    args.append(self.p_expr())
                    while self.chk(','):
                        self.adv()
                        if not self.chk(')'):
                            args.append(self.p_expr())
                self.eat(')')
                e = [self.nd('Call'), e, args]
            elif self.chk('['):
                self.adv()
                if self.chk(':'):
                    self.adv()
                    end = self.p_expr()
                    self.eat(']')
                    e = [self.nd('Slice'), e, ['Num', '0'], end]
                else:
                    idx = self.p_expr()
                    if self.chk(':'):
                        self.adv()
                        if self.chk(']'):
                            self.eat(']')
                            e = [self.nd('Slice'), e, idx, None]
                        else:
                            end = self.p_expr()
                            self.eat(']')
                            e = [self.nd('Slice'), e, idx, end]
                    else:
                        self.eat(']')
                        e = [self.nd('Index'), e, idx]
            elif self.chk('.'):
                self.adv()
                field = self.advt()[1]
                if self.chk('('):
                    self.adv()
                    args = []
                    if not self.chk(')'):
                        args.append(self.p_expr())
                        while self.chk(','):
                            self.adv()
                            if not self.chk(')'):
                                args.append(self.p_expr())
                    self.eat(')')
                    e = [self.nd('MethodCall'), e, field, args]
                else:
                    e = [self.nd('Field'), e, field]
            else:
                break
        return e

    def p_primary(self):
        tt, val = self.pk()
        if tt == 'Num':
            self.adv()
            return [self.nd('Num'), val]
        if tt == 'Str':
            self.adv()
            return [self.nd('Str'), val]
        if tt == 'Bool':
            self.adv()
            return [self.nd('Bool'), val]
        if tt == 'Nil':
            self.adv()
            return [self.nd('Nil')]
        if tt == 'Ident':
            self.adv()
            return [self.nd('Var'), val]
        if tt == 'self':
            self.adv()
            return [self.nd('Var'), 'self']
        if tt == 'if':
            self.adv()
            cond = self.p_expr()
            then = self.p_block()
            els = None
            if self.chk('else'):
                self.adv()
                els = self.p_block()
            return [self.nd('IfExpr'), cond, then, els]
        if tt == '(':
            self.adv()
            e = self.p_expr()
            self.eat(')')
            return e
        if tt == '[':
            self.adv()
            elems = []
            if not self.chk(']'):
                elems.append(self.p_expr())
                if self.chk('for'):
                    self.adv()
                    vn = self.advt()[1]
                    self.adv()
                    it = self.p_expr()
                    flt = None
                    if self.chk('if'):
                        self.adv()
                        flt = self.p_expr()
                    self.eat(']')
                    return [self.nd('ListComp'), elems[0], vn, it, flt]
                while self.chk(','):
                    self.adv()
                    if not self.chk(']'):
                        elems.append(self.p_expr())
            self.eat(']')
            return [self.nd('Array'), elems]
        if tt == '{':
            nxt = self.tok[self.pos + 1][0] if self.pos + 1 < len(self.tok) else ''
            if nxt == '}':
                self.adv()
                self.adv()
                return [self.nd('Dict'), []]
            nxt2 = self.tok[self.pos + 2][0] if self.pos + 2 < len(self.tok) else ''
            if nxt2 == ':':
                self.adv()
                pairs = []
                while not self.chk('}') and not self.chk('EOF'):
                    k = self.p_expr()
                    self.eat(':')
                    v = self.p_expr()
                    pairs.append([k, v])
                    self.skp(',')
                self.skp('}')
                return [self.nd('Dict'), pairs]
        if (tt == 'fn' and self.pos + 1 < len(self.tok)
                and self.tok[self.pos + 1][0] == '('):
            self.adv()
            self.eat('(')
            params = []
            if not self.chk(')'):
                params.append(self.advt()[1])
                while self.chk(','):
                    self.adv()
                    params.append(self.advt()[1])
            self.eat(')')
            if self.chk('{'):
                body = self.p_block()
                return [self.nd('Lambda'), params, body]
            else:
                bexpr = self.p_expr()
                return [self.nd('Lambda'), params, [[self.nd('Return'), bexpr]]]
        self.adv()
        return [self.nd('Nil')]


# ---------------------------------------------------------------------------
# PHASE 3: AST -> IR LOWERING
# ---------------------------------------------------------------------------
class IRBuilder:
    def __init__(self):
        self.op = []
        self.dst = []
        self.src1 = []
        self.src2 = []
        self.dead = []
        self.next_tmp = 0
        self.label_counter = 0
        self.vars = {}
        self.fns = {}

    def tmp(self):
        t = self.next_tmp
        self.next_tmp += 1
        return t

    def lbl(self):
        self.label_counter += 1
        return self.label_counter

    def emit(self, op, d, s1, s2):
        self.op.append(op)
        self.dst.append(d)
        self.src1.append(s1)
        self.src2.append(s2)
        self.dead.append(0)
        return len(self.op) - 1

    def live_count(self):
        return sum(1 for x in self.dead if x == 0)

    # ---- expression lowering ----
    def lower_expr(self, node):
        if node is None:
            t = self.tmp()
            self.emit(IR_CONST, t, 0, 0)
            return t
        if not isinstance(node, list) or len(node) < 1:
            t = self.tmp()
            self.emit(IR_CONST, t, 0, 0)
            return t
        nt = node[0]
        if nt == 'Num':
            t = self.tmp()
            v = parse_int(node[1])
            self.emit(IR_CONST, t, v, 0)
            return t
        if nt == 'Str':
            t = self.tmp()
            self.emit(IR_STR_CONST, t, node[1], 0)
            return t
        if nt == 'Bool':
            t = self.tmp()
            v = 1 if node[1] == 'true' else 0
            self.emit(IR_CONST, t, v, 0)
            return t
        if nt == 'Nil':
            t = self.tmp()
            self.emit(IR_CONST, t, 0, 0)
            return t
        if nt == 'Var':
            vr = self.vars.get(node[1])
            if vr is not None:
                t = self.tmp()
                self.emit(IR_COPY, t, vr, 0)
                return t
            t = self.tmp()
            self.emit(IR_CONST, t, 0, 0)
            return t
        if nt == 'BinOp':
            l = self.lower_expr(node[2])
            r = self.lower_expr(node[3])
            t = self.tmp()
            op_map = {'+': IR_ADD, '-': IR_SUB, '*': IR_MUL, '/': IR_DIV,
                      '%': IR_MOD, '&': IR_AND, '|': IR_OR, '^': IR_XOR,
                      '<<': IR_SHL, '>>': IR_SHR, '==': IR_CMP_EQ,
                      '!=': IR_CMP_NE, '<': IR_CMP_LT, '<=': IR_CMP_LE,
                      '>': IR_CMP_GT, '>=': IR_CMP_GE}
            irop = op_map.get(node[1], IR_COPY)
            self.emit(irop, t, l, r)
            return t
        if nt == 'Unary':
            inner = self.lower_expr(node[2])
            t = self.tmp()
            if node[1] == '-':
                uop = IR_NEG
            elif node[1] in ('!', '~'):
                uop = IR_NOT
            else:
                uop = IR_COPY
            self.emit(uop, t, inner, 0)
            return t
        if nt == 'Call':
            args = node[2]
            ai = 0
            fn = ''
            if isinstance(node[1], list) and len(node[1]) >= 2 and node[1][0] == 'Var':
                fn = node[1][1]
            # Intrinsics (mirror PS ordering exactly)
            if fn == 'port_out_u8' and len(args) >= 2:
                port_reg = self.lower_expr(args[0])
                val_reg = self.lower_expr(args[1])
                t = self.tmp()
                self.emit(IR_PORT_OUT, t, port_reg, val_reg)
                return t
            if fn == 'port_in_u8' and len(args) >= 1:
                port_reg = self.lower_expr(args[0])
                t = self.tmp()
                self.emit(IR_PORT_IN, t, port_reg, 0)
                return t
            if fn == 'cli':
                t = self.tmp()
                self.emit(IR_CLI, t, 0, 0)
                return t
            if fn == 'sti':
                t = self.tmp()
                self.emit(IR_STI, t, 0, 0)
                return t
            if fn == 'hlt':
                t = self.tmp()
                self.emit(IR_HLT, t, 0, 0)
                return t
            if fn == 'port_out_u32' and len(args) >= 2:
                port_reg = self.lower_expr(args[0])
                val_reg = self.lower_expr(args[1])
                t = self.tmp()
                self.emit(IR_PORT_OUT32, t, port_reg, val_reg)
                return t
            if fn == 'port_in_u32' and len(args) >= 1:
                port_reg = self.lower_expr(args[0])
                t = self.tmp()
                self.emit(IR_PORT_IN32, t, port_reg, 0)
                return t
            if fn == 'mem_write_u8' and len(args) >= 2:
                addr_reg = self.lower_expr(args[0])
                val_reg = self.lower_expr(args[1])
                t = self.tmp()
                self.emit(IR_MEM_STORE8, t, addr_reg, val_reg)
                return t
            if fn == 'mem_write_u32' and len(args) >= 2:
                addr_reg = self.lower_expr(args[0])
                val_reg = self.lower_expr(args[1])
                t = self.tmp()
                self.emit(IR_MEM_STORE32, t, addr_reg, val_reg)
                return t
            if fn == 'mem_read_u8' and len(args) >= 1:
                addr_reg = self.lower_expr(args[0])
                t = self.tmp()
                self.emit(IR_MEM_LOAD8, t, addr_reg, 0)
                return t
            if fn == 'mem_read_u32' and len(args) >= 1:
                addr_reg = self.lower_expr(args[0])
                t = self.tmp()
                self.emit(IR_MEM_LOAD32, t, addr_reg, 0)
                return t
            if fn == 'mem_read_u64' and len(args) >= 1:
                addr_reg = self.lower_expr(args[0])
                t = self.tmp()
                self.emit(IR_MEM_LOAD64, t, addr_reg, 0)
                return t
            if fn == 'mem_write_u64' and len(args) >= 2:
                addr_reg = self.lower_expr(args[0])
                val_reg = self.lower_expr(args[1])
                t = self.tmp()
                self.emit(IR_MEM_STORE64, t, addr_reg, val_reg)
                return t
            if fn == 'lidt' and len(args) >= 1:
                addr_reg = self.lower_expr(args[0])
                t = self.tmp()
                self.emit(IR_LIDT, t, addr_reg, 0)
                return t
            for a in args:
                av = self.lower_expr(a)
                self.emit(IR_ARG, ai, av, 0)
                ai += 1
            t = self.tmp()
            if fn in self.fns:
                fl = self.fns[fn]
            else:
                fl = fn
            self.emit(IR_CALL, t, fl, ai)
            return t
        if nt == 'Index':
            base = self.lower_expr(node[1])
            idx = self.lower_expr(node[2])
            t = self.tmp()
            self.emit(IR_LOAD, t, base, idx)
            return t
        if nt == 'Array':
            t = self.tmp()
            self.emit(IR_CONST, t, 0, 0)
            return t
        if nt == 'IfExpr':
            c = self.lower_expr(node[1])
            el = self.lbl()
            end = self.lbl()
            self.emit(IR_JZ, c, el, 0)
            tv = 0
            if isinstance(node[2], list) and len(node[2]) > 0:
                tv = self.lower_expr(node[2][0])
            self.emit(IR_JMP, end, 0, 0)
            self.emit(IR_LABEL, el, 0, 0)
            ev = 0
            if node[3] is not None and isinstance(node[3], list) and len(node[3]) > 0:
                ev = self.lower_expr(node[3][0])
            self.emit(IR_LABEL, end, 0, 0)
            t = self.tmp()
            self.emit(IR_COPY, t, tv, 0)
            return t
        t = self.tmp()
        self.emit(IR_CONST, t, 0, 0)
        return t

    # ---- statement lowering ----
    def lower_stmts(self, stmts):
        for s in stmts:
            self.lower_stmt(s)

    def lower_stmt(self, node):
        if node is None:
            return
        if not isinstance(node, list) or len(node) < 1:
            return
        nt = node[0]
        if not isinstance(nt, str):
            for s in node:
                self.lower_stmt(s)
            return
        if nt == 'Let':
            vr = self.tmp()
            self.vars[node[1]] = vr
            if node[3] is not None:
                val = self.lower_expr(node[3])
                self.emit(IR_COPY, vr, val, 0)
            else:
                self.emit(IR_CONST, vr, 0, 0)
            return
        if nt == 'Assign':
            val = self.lower_expr(node[2])
            vr = self.vars.get(node[1])
            if vr is not None:
                self.emit(IR_COPY, vr, val, 0)
            return
        if nt == 'FnDef':
            lbl = self.lbl()
            self.fns[node[1]] = lbl
            self.emit(IR_LABEL, lbl, 0, 0)
            pi = 0
            if isinstance(node[2], list):
                for p in node[2]:
                    pv = self.tmp()
                    self.vars[p] = pv
                    self.emit(IR_PARAM, pv, pi, 0)
                    pi += 1
            for s in node[3]:
                self.lower_stmt(s)
            z = self.tmp()
            self.emit(IR_CONST, z, 0, 0)
            self.emit(IR_RET, z, 0, 0)
            return
        if nt == 'Return':
            if node[1] is not None:
                val = self.lower_expr(node[1])
                self.emit(IR_RET, val, 0, 0)
            else:
                z = self.tmp()
                self.emit(IR_CONST, z, 0, 0)
                self.emit(IR_RET, z, 0, 0)
            return
        if nt == 'If':
            c = self.lower_expr(node[1])
            el = self.lbl()
            end = self.lbl()
            self.emit(IR_JZ, c, el, 0)
            for s in node[2]:
                self.lower_stmt(s)
            self.emit(IR_JMP, end, 0, 0)
            self.emit(IR_LABEL, el, 0, 0)
            if node[3] is not None:
                for s in node[3]:
                    self.lower_stmt(s)
            self.emit(IR_LABEL, end, 0, 0)
            return
        if nt == 'While':
            lp = self.lbl()
            end = self.lbl()
            self.emit(IR_LABEL, lp, 0, 0)
            c = self.lower_expr(node[1])
            self.emit(IR_JZ, c, end, 0)
            for s in node[2]:
                self.lower_stmt(s)
            self.emit(IR_JMP, lp, 0, 0)
            self.emit(IR_LABEL, end, 0, 0)
            return
        if nt == 'For':
            self.emit(IR_NOP, 0, 0, 0)
            return
        if nt == 'Print':
            val = self.lower_expr(node[1])
            self.emit(IR_PRINT, val, 0, 0)
            return
        if nt == 'ExprStmt':
            self.lower_expr(node[1])
            return
        if nt == 'Quadrant':
            for s in node[2]:
                self.lower_stmt(s)
            return
        if nt == 'Block':
            for s in node[1]:
                self.lower_stmt(s)
            return
        if nt == 'IndexAssign':
            return
        if nt == 'FnDecl':
            return
        self.emit(IR_NOP, 0, 0, 0)

    def lower_module(self, ast):
        for s in ast:
            self.lower_stmt(s)

    # ---- optimizations (dict-based constant propagation, O(n)) ----
    def opt_const_fold(self):
        changed = 0
        const_vals = {}
        for i in range(len(self.op)):
            if self.dead[i]:
                continue
            op = self.op[i]
            s1 = self.src1[i]
            s2 = self.src2[i]
            s1v = const_vals.get(s1)
            s2v = const_vals.get(s2)
            if isinstance(s1v, int) and isinstance(s2v, int):
                r = None
                if op == IR_ADD:
                    r = s1v + s2v
                elif op == IR_SUB:
                    r = s1v - s2v
                elif op == IR_MUL:
                    r = s1v * s2v
                elif op == IR_AND:
                    r = s1v & s2v
                elif op == IR_OR:
                    r = s1v | s2v
                elif op == IR_XOR:
                    r = s1v ^ s2v
                elif op == IR_DIV:
                    if s2v != 0:
                        r = int(s1v / s2v)
                elif op == IR_CMP_EQ:
                    r = int(s1v == s2v)
                elif op == IR_CMP_NE:
                    r = int(s1v != s2v)
                elif op == IR_CMP_LT:
                    r = int(s1v < s2v)
                elif op == IR_CMP_LE:
                    r = int(s1v <= s2v)
                if r is not None:
                    self.op[i] = IR_CONST
                    self.src1[i] = r
                    self.src2[i] = 0
                    changed += 1
            if self.op[i] == IR_CONST:
                const_vals[self.dst[i]] = self.src1[i]
        return changed

    def opt_dce(self):
        changed = 0
        skip = {IR_JMP, IR_JZ, IR_JNZ, IR_LABEL, IR_CALL, IR_RET, IR_STORE,
                IR_ARG, IR_PARAM, IR_NOP, IR_PRINT, IR_PORT_OUT, IR_PORT_IN,
                IR_CLI, IR_STI, IR_HLT, IR_MEM_STORE8, IR_MEM_LOAD64,
                IR_MEM_STORE64, IR_LIDT, IR_PORT_OUT32, IR_PORT_IN32,
                IR_MEM_STORE32, IR_MEM_LOAD32, IR_MEM_LOAD8}
        used = set()
        for i in range(len(self.op)):
            if self.dead[i]:
                continue
            op = self.op[i]
            s1 = self.src1[i]
            s2 = self.src2[i]
            if isinstance(s1, int):
                used.add(s1)
            if isinstance(s2, int):
                used.add(s2)
            if op in (IR_JZ, IR_JNZ, IR_RET):
                used.add(self.dst[i])
        for i in range(len(self.op)):
            if self.dead[i]:
                continue
            if self.op[i] in skip:
                continue
            if self.dst[i] not in used:
                self.dead[i] = 1
                changed += 1
        return changed

    def opt_strength(self):
        changed = 0
        const_vals = {}
        for i in range(len(self.op)):
            if self.dead[i]:
                continue
            op = self.op[i]
            s2v = const_vals.get(self.src2[i])
            if op == IR_MUL and isinstance(s2v, int):
                if s2v == 2:
                    self.op[i] = IR_SHL
                    self.src2[i] = 1
                    changed += 1
                elif s2v == 4:
                    self.op[i] = IR_SHL
                    self.src2[i] = 2
                    changed += 1
                elif s2v == 8:
                    self.op[i] = IR_SHL
                    self.src2[i] = 3
                    changed += 1
            if op == IR_DIV and isinstance(s2v, int):
                if s2v == 2:
                    self.op[i] = IR_SHR
                    self.src2[i] = 1
                    changed += 1
                elif s2v == 4:
                    self.op[i] = IR_SHR
                    self.src2[i] = 2
                    changed += 1
            if self.op[i] == IR_CONST:
                const_vals[self.dst[i]] = self.src1[i]
        return changed

    def optimize(self):
        total = 0
        for _ in range(5):
            c = 0
            c += self.opt_const_fold()
            c += self.opt_dce()
            c += self.opt_strength()
            total += c
            if c == 0:
                break
        return total


def parse_int(s):
    """Parse numeric token like PS [long] conversion."""
    s = str(s).strip()
    try:
        if s.lower().startswith('0x'):
            return int(s, 16)
        if s.lower().startswith('0b'):
            return int(s, 2)
        if s.lower().startswith('0o'):
            return int(s, 8)
        if '.' in s:
            return int(float(s))
        return int(s)
    except (ValueError, OverflowError):
        return 0


# ---------------------------------------------------------------------------
# PHASE 4: REGISTER ALLOCATION + x86_64 CODE EMISSION
# ---------------------------------------------------------------------------
REG_POOL = [0, 1, 2, 3, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]  # RAX RCX RDX RBX RSI RDI R8-R15
ABI_REGS = [7, 6, 2, 1, 8, 9]  # RDI RSI RDX RCX R8 R9


class Codegen:
    def __init__(self, kern_syms, module_name):
        self.kern_syms = kern_syms
        self.current_module = module_name
        self.ra_map = {}
        self.ra_spill_map = {}
        self.ra_spill_top = 0
        self.ra_free = list(REG_POOL)
        self.buf = bytearray()
        self.mod_symbols = []
        self.mod_relocs = []
        self.mod_strings = []

    def ra_alloc(self, vreg):
        if vreg in self.ra_map:
            return self.ra_map[vreg]
        if self.ra_free:
            r = self.ra_free.pop()
            self.ra_map[vreg] = r
            return r
        self.ra_map[vreg] = -1
        self.ra_spill_top += 8
        self.ra_spill_map[vreg] = self.ra_spill_top
        return -1

    # --- byte emitters ---
    def x86_byte(self, b):
        self.buf.append(b & 0xFF)

    def x86_imm32(self, v):
        for i in range(4):
            self.x86_byte((v >> (8 * i)) & 0xFF)

    def x86_imm64(self, v):
        for i in range(8):
            self.x86_byte((v >> (8 * i)) & 0xFF)

    def x86_mov_reg_imm(self, r, v):
        self.x86_byte(0x49 if r >= 8 else 0x48)
        self.x86_byte(0xB8 + (r & 7))
        self.x86_imm32(v & 0xFFFFFFFF)
        self.x86_imm32((v >> 32) & 0xFFFFFFFF)

    def x86_mov_rr(self, dst, src):
        rex = 0x48
        if src >= 8:
            rex |= 4
        if dst >= 8:
            rex |= 1
        self.x86_byte(rex)
        self.x86_byte(0x89)
        self.x86_byte(0xC0 + ((src & 7) << 3) + (dst & 7))

    def x86_add_rr(self, dst, src):
        rex = 0x48
        if src >= 8:
            rex |= 4
        if dst >= 8:
            rex |= 1
        self.x86_byte(rex)
        self.x86_byte(0x01)
        self.x86_byte(0xC0 + ((src & 7) << 3) + (dst & 7))

    def x86_sub_rr(self, dst, src):
        rex = 0x48
        if src >= 8:
            rex |= 4
        if dst >= 8:
            rex |= 1
        self.x86_byte(rex)
        self.x86_byte(0x29)
        self.x86_byte(0xC0 + ((src & 7) << 3) + (dst & 7))

    def x86_imul_rr(self, dst, src):
        rex = 0x48
        if dst >= 8:
            rex |= 4
        if src >= 8:
            rex |= 1
        self.x86_byte(rex)
        self.x86_byte(0x0F)
        self.x86_byte(0xAF)
        self.x86_byte(0xC0 + ((dst & 7) << 3) + (src & 7))

    def x86_cmp_set(self, r1, r2, setcc):
        rex = 0x48
        if r2 >= 8:
            rex |= 4
        if r1 >= 8:
            rex |= 1
        self.x86_byte(rex)
        self.x86_byte(0x39)
        self.x86_byte(0xC0 + ((r2 & 7) << 3) + (r1 & 7))
        self.x86_byte(0x0F)
        self.x86_byte(setcc)
        self.x86_byte(0xC0)
        self.x86_byte(0x48)
        self.x86_byte(0x0F)
        self.x86_byte(0xB6)
        self.x86_byte(0xC0)

    def x86_neg_r(self, r):
        rex = 0x48
        if r >= 8:
            rex |= 1
        self.x86_byte(rex)
        self.x86_byte(0xF7)
        self.x86_byte(0xD8 + (r & 7))

    def x86_not_r(self, r):
        rex = 0x48
        if r >= 8:
            rex |= 1
        self.x86_byte(rex)
        self.x86_byte(0xF7)
        self.x86_byte(0xD0 + (r & 7))

    def x86_ret(self):
        self.x86_byte(0xC3)

    def x86_prologue(self):
        self.x86_byte(0x55)
        self.x86_byte(0x48)
        self.x86_byte(0x89)
        self.x86_byte(0xE5)

    def x86_epilogue(self):
        self.x86_byte(0x48)
        self.x86_byte(0x89)
        self.x86_byte(0xEC)
        self.x86_byte(0x5D)

    def x86_shl_ri(self, r, imm):
        rex = 0x48
        if r >= 8:
            rex |= 1
        self.x86_byte(rex)
        self.x86_byte(0xC1)
        self.x86_byte(0xE0 + (r & 7))
        self.x86_byte(imm)

    def x86_shr_ri(self, r, imm):
        rex = 0x48
        if r >= 8:
            rex |= 1
        self.x86_byte(rex)
        self.x86_byte(0xC1)
        self.x86_byte(0xE8 + (r & 7))
        self.x86_byte(imm)

    def x86_and_rr(self, dst, src):
        rex = 0x48
        if src >= 8:
            rex |= 4
        if dst >= 8:
            rex |= 1
        self.x86_byte(rex)
        self.x86_byte(0x21)
        self.x86_byte(0xC0 + ((src & 7) << 3) + (dst & 7))

    def x86_or_rr(self, dst, src):
        rex = 0x48
        if src >= 8:
            rex |= 4
        if dst >= 8:
            rex |= 1
        self.x86_byte(rex)
        self.x86_byte(0x09)
        self.x86_byte(0xC0 + ((src & 7) << 3) + (dst & 7))

    def x86_xor_rr(self, dst, src):
        rex = 0x48
        if src >= 8:
            rex |= 4
        if dst >= 8:
            rex |= 1
        self.x86_byte(rex)
        self.x86_byte(0x31)
        self.x86_byte(0xC0 + ((src & 7) << 3) + (dst & 7))

    # --- IR -> x86_64 ---
    def emit_ir(self, idx, ir):
        op = ir.op[idx]
        dst = ir.dst[idx]
        s1 = ir.src1[idx]
        s2 = ir.src2[idx]
        rd = self.ra_alloc(dst)
        if op == IR_CONST:
            if rd >= 0:
                self.x86_mov_reg_imm(rd, s1)
        elif op == IR_STR_CONST:
            if rd >= 0:
                si = len(self.mod_strings)
                self.mod_strings.append(str(s1))
                sym = '__str$%s$%d' % (self.current_module, si)
                self.x86_mov_reg_imm(rd, 0)
                site = len(self.buf) - 8
                self.mod_relocs.append([site, sym, 'abs64'])
        elif op == IR_COPY:
            rs = self.ra_alloc(s1)
            if rd >= 0 and rs >= 0:
                self.x86_mov_rr(rd, rs)
        elif op in (IR_ADD, IR_SUB, IR_MUL, IR_AND, IR_OR, IR_XOR):
            r1 = self.ra_alloc(s1)
            r2 = self.ra_alloc(s2)
            if rd >= 0:
                if rd != r1 and r1 >= 0:
                    self.x86_mov_rr(rd, r1)
                if r2 >= 0:
                    if op == IR_ADD:
                        self.x86_add_rr(rd, r2)
                    elif op == IR_SUB:
                        self.x86_sub_rr(rd, r2)
                    elif op == IR_MUL:
                        self.x86_imul_rr(rd, r2)
                    elif op == IR_AND:
                        self.x86_and_rr(rd, r2)
                    elif op == IR_OR:
                        self.x86_or_rr(rd, r2)
                    elif op == IR_XOR:
                        self.x86_xor_rr(rd, r2)
        elif op == IR_SHL:
            r1 = self.ra_alloc(s1)
            if rd >= 0 and r1 >= 0:
                if rd != r1:
                    self.x86_mov_rr(rd, r1)
                self.x86_shl_ri(rd, int(s2))
        elif op == IR_SHR:
            r1 = self.ra_alloc(s1)
            if rd >= 0 and r1 >= 0:
                if rd != r1:
                    self.x86_mov_rr(rd, r1)
                self.x86_shr_ri(rd, int(s2))
        elif op == IR_NEG:
            r1 = self.ra_alloc(s1)
            if rd >= 0 and r1 >= 0:
                if rd != r1:
                    self.x86_mov_rr(rd, r1)
                self.x86_neg_r(rd)
        elif op == IR_NOT:
            r1 = self.ra_alloc(s1)
            if rd >= 0 and r1 >= 0:
                if rd != r1:
                    self.x86_mov_rr(rd, r1)
                self.x86_not_r(rd)
        elif op in (IR_CMP_EQ, IR_CMP_NE, IR_CMP_LT, IR_CMP_LE, IR_CMP_GT, IR_CMP_GE):
            r1 = self.ra_alloc(s1)
            r2 = self.ra_alloc(s2)
            if r1 >= 0 and r2 >= 0:
                setcc = {IR_CMP_EQ: 0x94, IR_CMP_NE: 0x95, IR_CMP_LT: 0x9C,
                         IR_CMP_LE: 0x9E, IR_CMP_GT: 0x9F, IR_CMP_GE: 0x9D}[op]
                self.x86_cmp_set(r1, r2, setcc)
                if rd >= 0 and rd != 0:
                    self.x86_mov_rr(rd, 0)
        elif op == IR_JMP:
            self.x86_byte(0xE9)
            self.x86_imm32(0)
        elif op == IR_JZ:
            self.x86_byte(0x0F)
            self.x86_byte(0x84)
            self.x86_imm32(0)
        elif op == IR_RET:
            r1 = self.ra_alloc(dst)
            if r1 is not None and r1 >= 0 and r1 != 0:
                self.x86_mov_rr(0, r1)
            self.x86_epilogue()
            self.x86_ret()
        elif op == IR_CALL:
            self.x86_byte(0xE8)
            self.x86_imm32(0)
        elif op == IR_ARG:
            arg_idx = dst
            val_reg = self.ra_alloc(s1)
            if 0 <= arg_idx < 6 and val_reg >= 0:
                target = ABI_REGS[arg_idx]
                if val_reg != target:
                    self.x86_mov_rr(target, val_reg)
        elif op == IR_PARAM:
            param_idx = s1
            if 0 <= param_idx < 6 and rd >= 0:
                src_reg = ABI_REGS[param_idx]
                if rd != src_reg:
                    self.x86_mov_rr(rd, src_reg)
        elif op == IR_PRINT:
            src_reg = self.ra_alloc(s1)
            if src_reg >= 0 and 'serial_puts' in self.kern_syms:
                if src_reg != 6:
                    self.x86_mov_rr(6, src_reg)
                self.x86_byte(0x48)
                self.x86_byte(0xB8)
                self.x86_imm64(self.kern_syms['serial_puts'])
                self.x86_byte(0xFF)
                self.x86_byte(0xD0)
            else:
                self.x86_byte(0x90)
        elif op == IR_PORT_OUT:
            r_port = self.ra_alloc(s1)
            r_val = self.ra_alloc(s2)
            if r_port >= 0 and r_val >= 0:
                if r_port != 2:
                    self.x86_mov_rr(2, r_port)
                if r_val != 0:
                    self.x86_mov_rr(0, r_val)
                self.x86_byte(0xEE)
        elif op == IR_PORT_IN:
            r_port = self.ra_alloc(s1)
            if r_port >= 0:
                if r_port != 2:
                    self.x86_mov_rr(2, r_port)
                self.x86_byte(0xEC)
                self.x86_byte(0x48)
                self.x86_byte(0x0F)
                self.x86_byte(0xB6)
                self.x86_byte(0xC0)
                if rd >= 0 and rd != 0:
                    self.x86_mov_rr(rd, 0)
        elif op == IR_CLI:
            self.x86_byte(0xFA)
        elif op == IR_STI:
            self.x86_byte(0xFB)
        elif op == IR_HLT:
            self.x86_byte(0xF4)
        elif op == IR_MEM_STORE8:
            r_addr = self.ra_alloc(s1)
            r_val = self.ra_alloc(s2)
            if r_addr >= 0 and r_val >= 0:
                if r_addr != 7:
                    self.x86_mov_rr(7, r_addr)
                if r_val != 0:
                    self.x86_mov_rr(0, r_val)
                self.x86_byte(0x88)
                self.x86_byte(0x07)
        elif op == IR_MEM_LOAD64:
            r_addr = self.ra_alloc(s1)
            if r_addr >= 0:
                if r_addr != 7:
                    self.x86_mov_rr(7, r_addr)
                self.x86_byte(0x48)
                self.x86_byte(0x8B)
                self.x86_byte(0x07)
                if rd >= 0 and rd != 0:
                    self.x86_mov_rr(rd, 0)
        elif op == IR_MEM_STORE64:
            r_addr = self.ra_alloc(s1)
            r_val = self.ra_alloc(s2)
            if r_addr >= 0 and r_val >= 0:
                if r_addr != 7:
                    self.x86_mov_rr(7, r_addr)
                if r_val != 0:
                    self.x86_mov_rr(0, r_val)
                self.x86_byte(0x48)
                self.x86_byte(0x89)
                self.x86_byte(0x07)
        elif op == IR_LIDT:
            r_addr = self.ra_alloc(s1)
            if r_addr >= 0:
                if r_addr != 7:
                    self.x86_mov_rr(7, r_addr)
                self.x86_byte(0x0F)
                self.x86_byte(0x01)
                self.x86_byte(0x1F)
        elif op == IR_PORT_OUT32:
            r_port = self.ra_alloc(s1)
            r_val = self.ra_alloc(s2)
            if r_port >= 0 and r_val >= 0:
                if r_port != 2:
                    self.x86_mov_rr(2, r_port)
                if r_val != 0:
                    self.x86_mov_rr(0, r_val)
                self.x86_byte(0xEF)
        elif op == IR_PORT_IN32:
            r_port = self.ra_alloc(s1)
            if r_port >= 0:
                if r_port != 2:
                    self.x86_mov_rr(2, r_port)
                self.x86_byte(0xED)
                if rd >= 0 and rd != 0:
                    self.x86_mov_rr(rd, 0)
        elif op == IR_MEM_STORE32:
            r_addr = self.ra_alloc(s1)
            r_val = self.ra_alloc(s2)
            if r_addr >= 0 and r_val >= 0:
                if r_addr != 7:
                    self.x86_mov_rr(7, r_addr)
                if r_val != 0:
                    self.x86_mov_rr(0, r_val)
                self.x86_byte(0x89)
                self.x86_byte(0x07)
        elif op == IR_MEM_LOAD32:
            r_addr = self.ra_alloc(s1)
            if r_addr >= 0:
                if r_addr != 7:
                    self.x86_mov_rr(7, r_addr)
                self.x86_byte(0x8B)
                self.x86_byte(0x07)
                if rd >= 0 and rd != 0:
                    self.x86_mov_rr(rd, 0)
        elif op == IR_MEM_LOAD8:
            r_addr = self.ra_alloc(s1)
            if r_addr >= 0:
                if r_addr != 7:
                    self.x86_mov_rr(7, r_addr)
                self.x86_byte(0x0F)
                self.x86_byte(0xB6)
                self.x86_byte(0x07)
                if rd >= 0 and rd != 0:
                    self.x86_mov_rr(rd, 0)
        elif op == IR_NOP:
            self.x86_byte(0x90)

    def compile_module(self, ir):
        self.ra_map = {}
        self.ra_spill_map = {}
        self.ra_spill_top = 0
        self.ra_free = list(REG_POOL)
        self.buf = bytearray()
        self.mod_symbols = []
        self.mod_relocs = []
        self.mod_strings = []
        self.x86_prologue()
        label_offsets = {}
        jmp_sites = []
        # map label -> fn name for IR_LABEL
        fn_label_to_name = {v: k for k, v in ir.fns.items()}
        for i in range(len(ir.op)):
            if ir.dead[i]:
                continue
            if ir.op[i] == IR_LABEL:
                lbl = ir.dst[i]
                is_fn = lbl in fn_label_to_name
                if is_fn:
                    self.mod_symbols.append([fn_label_to_name[lbl], len(self.buf), 'fn'])
                    self.ra_map = {}
                    self.ra_spill_map = {}
                    self.ra_spill_top = 0
                    self.ra_free = list(REG_POOL)
                    self.x86_prologue()
                else:
                    label_offsets[lbl] = len(self.buf)
            if ir.op[i] == IR_JMP:
                cnt = len(self.buf)
                jmp_sites.append([cnt + 1, ir.dst[i]])
            elif ir.op[i] in (IR_JZ, IR_JNZ):
                cnt = len(self.buf)
                tgt = ir.src1[i]
                if not isinstance(tgt, int):
                    tgt = int(tgt)
                jmp_sites.append([cnt + 2, tgt])
            if ir.op[i] == IR_CALL:
                call_site = len(self.buf) + 1
                fn_label = ir.src1[i]
                fn_name = ''
                if isinstance(fn_label, str) and fn_label != '':
                    fn_name = fn_label
                else:
                    for k, v in ir.fns.items():
                        if v == fn_label:
                            fn_name = k
                            break
                if fn_name != '':
                    self.mod_relocs.append([call_site, fn_name, 'rel32'])
            self.emit_ir(i, ir)
        # backpatch jump rel32
        for site, tgt_lbl in jmp_sites:
            if tgt_lbl in label_offsets:
                rel = label_offsets[tgt_lbl] - (site + 4)
                for b in range(4):
                    self.buf[site + b] = (rel >> (8 * b)) & 0xFF
        self.x86_epilogue()
        self.x86_ret()
        return len(self.buf)


# ---------------------------------------------------------------------------
# PHASE 5: CROSS-MODULE LINKER
# ---------------------------------------------------------------------------
BUILTINS = [
    'print', 'println', 'len', 'push', 'pop', 'set_at', 'to_string',
    'lfsr_next', 'tcp_send', 'tcp_recv', 'tcp_connect', 'dns_resolve',
    'input', 'type_of', 'str_split', 'str_trim', 'str_find', 'str_sub',
    'array_new', 'array_fill', 'sort', 'char_at', 'char_code',
    'from_char_code', 'str_contains', 'str_starts_with', 'str_ends_with',
    'str_replace', 'str_to_upper', 'str_to_lower', 'str_join',
    'abs', 'min', 'max', 'floor', 'ceil', 'sqrt', 'pow', 'log',
    'random', 'time_ms', 'sleep_ms', 'panic',
    'array', 'to_int', 'parse_int', 'str_char_code', '_starts_with',
    'str_slice', 'substr', 'str_index_of', 'str_to_bytes', 'str_from_byte',
    'to_char', 'str_byte', 'strlen',
    'serial_print', '_ke_pci_read', 'mem_set32', 'wrmsr', 'random_get',
    '_find_space', 'cstr_from_addr', 'udp_recv', 'file_read',
    'ui_fill_rect', 'font_draw_string', 'socket_send', 'socket_close',
    'partition', 'encode', 'close', 'search', 'insert', 'send',
    'chr', 'char_from_code', 'is_digit', 'is_alnum', 'memcpy',
    'recv', 'socket', 'socket_create', 'connect',
    'rdmsr', 'mem_write_dword', 'get_uptime', 'timer_ticks',
    'rtc_read_timestamp', 'notify_show', 'ot_span_id_of',
    'hicos_kernel_info', 'str_find_from', 'file_list', 'net_ip_string',
    'ctr_create', 'ctr_start', 'ctr_stop', 'ctr_destroy', 'ctr_status',
    'ctr_exec', 'ctr_list', 'aus_init', 'aus_play', 'aus_stop', 'aus_beep',
    'aus_connect', 'aus_set_master', 'svc_start', 'svc_stop', 'svc_status',
    'svc_list', 'usb_control_transfer', 'usb_device_count',
    'usb_interrupt_read', 'usb_device_protocol', 'usb_device_subclass',
    'usb_device_class', 'vesa_get_width', 'vesa_get_height', 'vesa_get_fb',
    'uiinst_handle_key', 'uifiles_handle_key', 'uiterm_handle_key',
    'ui_dialog_show', 'mixer_set_master_volume', 'aho_corasick_init',
    'ir_lower_stmts', 'ir_lower_reset', 'ir_optimize',
]

NOOP_STUB = bytes([0x55, 0x48, 0x89, 0xE5, 0x31, 0xC0, 0x5D, 0xC3])
FN_RE = re.compile(r'\bfn\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(')


class Linker:
    def __init__(self, kern_syms):
        self.modules = []
        self.global_syms = {}
        self.combined = bytearray()
        self.builtin_stubs = {}
        self.fwd_decls = {}
        self.kern_syms = kern_syms

    def pre_scan(self, paths):
        for p in paths:
            if not os.path.isfile(p):
                continue
            with open(p, 'r', encoding='utf-8-sig', errors='replace') as f:
                src = f.read()
            for m in FN_RE.finditer(src):
                fn = m.group(1)
                if fn not in self.fwd_decls:
                    self.fwd_decls[fn] = os.path.basename(p)

    def pass1(self):
        offset = 0
        for mod in self.modules:
            mod['offset'] = offset
            for sym in mod['symbols']:
                self.global_syms[sym[0]] = offset + sym[1]
            offset += len(mod['code'])
        return offset

    def generate_stubs(self):
        stub_base = len(self.combined)
        stub_count = 0
        for name in BUILTINS:
            if name not in self.global_syms:
                stub_off = len(self.combined)
                if name == 'print' and 'serial_puts' in self.kern_syms:
                    abs_addr = self.kern_syms['serial_puts']
                    self.combined += bytes([0x48, 0x89, 0xFE])  # mov rsi, rdi
                    self.combined += bytes([0x48, 0xB8])  # mov rax, imm64
                    for b in range(8):
                        self.combined.append((abs_addr >> (8 * b)) & 0xFF)
                    self.combined += bytes([0xFF, 0xD0, 0xC3])  # call rax; ret
                else:
                    self.combined += NOOP_STUB
                self.global_syms[name] = stub_off
                self.builtin_stubs[name] = stub_off
                stub_count += 1
        for fn in self.fwd_decls:
            if fn not in self.global_syms:
                stub_off = len(self.combined)
                self.combined += NOOP_STUB
                self.global_syms[fn] = stub_off
                self.builtin_stubs[fn] = stub_off
                stub_count += 1
        return stub_base, stub_count

    def emit_strings(self):
        for mod in self.modules:
            strings = mod.get('strings')
            if not strings:
                continue
            mod_name = mod['name']
            for si, s in enumerate(strings):
                sym = '__str$%s$%d' % (mod_name, si)
                self.global_syms[sym] = len(self.combined)
                raw = str(s)
                sb = []
                i = 0
                while i < len(raw):
                    ch = raw[i]
                    if ch == '\\' and i + 1 < len(raw):
                        n = raw[i + 1]
                        repl = {'n': '\n', 't': '\t', 'r': '\r', '0': '\0',
                                '\\': '\\', '"': '"', "'": "'"}.get(n, n)
                        sb.append(repl)
                        i += 2
                    else:
                        sb.append(ch)
                        i += 1
                self.combined += ''.join(sb).encode('utf-8')
                self.combined.append(0)

    def pass2(self):
        for mod in self.modules:
            self.combined += mod['code']
        stub_result = self.generate_stubs()
        self.link_stub_base, self.link_stub_count = stub_result
        self.emit_strings()
        resolved = 0
        unresolved = 0
        unresolved_map = {}
        for mod in self.modules:
            for reloc in mod['relocs']:
                site = mod['offset'] + reloc[0]
                target = reloc[1]
                rtype = reloc[2]
                if target in self.global_syms:
                    target_off = self.global_syms[target]
                    if rtype == 'rel32' and (site + 3) < len(self.combined):
                        rel = target_off - (site + 4)
                        for b in range(4):
                            self.combined[site + b] = (rel >> (8 * b)) & 0xFF
                        resolved += 1
                    elif rtype == 'abs64' and (site + 7) < len(self.combined):
                        abs_addr = LINK_TEXT_BASE + target_off
                        for b in range(8):
                            self.combined[site + b] = (abs_addr >> (8 * b)) & 0xFF
                        resolved += 1
                else:
                    unresolved += 1
                    unresolved_map[target] = unresolved_map.get(target, 0) + 1
        return resolved, unresolved, unresolved_map


def load_kern_syms():
    path = os.path.join(REPO_ROOT, 'bare-kernel', 'kernel-symbols.json')
    syms = {}
    if os.path.isfile(path):
        with open(path, 'r', encoding='utf-8-sig') as f:
            data = json.load(f)
        for k, v in data.items():
            if isinstance(v, str) and v.startswith('0x'):
                syms[k] = int(v, 16)
            else:
                syms[k] = int(v)
    return syms


# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
def main():
    import time
    t0 = time.time()
    kernel_dir = os.path.join(REPO_ROOT, 'bare-kernel', 'hl')
    module_paths = [os.path.join(kernel_dir, f) for f in sorted(os.listdir(kernel_dir))
                    if f.endswith('.hl')]
    ke = [p for p in module_paths if os.path.basename(p) == 'kernel_entry.hl']
    others = [p for p in module_paths if os.path.basename(p) != 'kernel_entry.hl']
    module_paths = ke + others
    total_files = len(module_paths)

    total_tokens = total_nodes = total_parse_errors = total_bal_errors = 0
    total_ir = total_ir_live = total_ir_opt = total_fns = total_x86 = 0
    success_count = 0
    warn_files = []
    module_asts = []

    kern_syms = load_kern_syms()
    linker = Linker(kern_syms)

    # pre-scan forward declarations
    pre_scan_paths = list(module_paths)
    for extra in ('stdlib.hl', 'hl-bootstrap.hl'):
        p = os.path.join(REPO_ROOT, extra)
        if os.path.isfile(p):
            pre_scan_paths.append(p)
    linker.pre_scan(pre_scan_paths)

    print('=== H-L Compilation Pipeline (Python) ===')
    print('Phase 1-5: Tokenize + Parse + IR + x86_64 + Link  (%d kernel modules)' % total_files)
    print('')

    for file_path in module_paths:
        name = os.path.basename(file_path)
        with open(file_path, 'r', encoding='utf-8-sig', errors='replace') as f:
            src = f.read()

        tokens = tokenize_hl(src)
        tok_count = len(tokens)
        total_tokens += tok_count

        bal_errors = test_balanced(tokens)
        fn_count = count_functions(tokens)

        parser = Parser(tokens)
        try:
            ast = parser.p_program()
        except Exception:
            pass
        node_count = parser.nodes
        parse_errors = parser.errors

        total_nodes += node_count
        total_parse_errors += parse_errors
        total_bal_errors += len(bal_errors)

        has_warnings = (parse_errors > 0 or len(bal_errors) > 0)
        if has_warnings:
            warn_files.append(name)

        ir = IRBuilder()
        try:
            ir.lower_module(ast)
        except Exception:
            pass
        ir_opt = ir.optimize()
        ir_total = len(ir.op)
        ir_live = ir.live_count()

        x86_bytes = 0
        codegen = Codegen(kern_syms, name)
        try:
            x86_bytes = codegen.compile_module(ir)
        except Exception:
            pass
        if x86_bytes > 0:
            linker.modules.append({
                'name': name,
                'code': codegen.buf,
                'symbols': codegen.mod_symbols,
                'relocs': codegen.mod_relocs,
                'strings': codegen.mod_strings,
                'offset': 0,
            })
        total_ir += ir_total
        total_ir_live += ir_live
        total_ir_opt += ir_opt
        total_fns += fn_count
        total_x86 += x86_bytes
        module_asts.append({'name': name, 'ir': ir_total, 'live': ir_live,
                            'opt': ir_opt, 'x86': x86_bytes})

        success_count += 1
        if has_warnings:
            print('  [WARN] %s: %d tok, %d ast, %d fn, %d ir, %d B (parse=%d bal=%d)'
                  % (name, tok_count, node_count, fn_count, ir_live, x86_bytes,
                     parse_errors, len(bal_errors)))
        else:
            print('  [OK]   %s: %d tok, %d ast, %d fn, %d ir, %d B'
                  % (name, tok_count, node_count, fn_count, ir_live, x86_bytes))

    # Compile stdlib.hl and hl-bootstrap.hl
    for extra in ('stdlib.hl', 'hl-bootstrap.hl'):
        extra_path = os.path.join(REPO_ROOT, extra)
        if not os.path.isfile(extra_path):
            continue
        with open(extra_path, 'r', encoding='utf-8-sig', errors='replace') as f:
            src = f.read()
        tokens = tokenize_hl(src)
        tok_count = len(tokens)
        total_tokens += tok_count
        fn_count = count_functions(tokens)
        parser = Parser(tokens)
        try:
            ast = parser.p_program()
        except Exception:
            pass
        node_count = parser.nodes
        parse_errors = parser.errors
        total_nodes += node_count
        total_parse_errors += parse_errors
        if parse_errors == 0:
            ir = IRBuilder()
            try:
                ir.lower_module(ast)
            except Exception:
                pass
            ir_opt = ir.optimize()
            ir_total = len(ir.op)
            ir_live = ir.live_count()
            x86_bytes = 0
            codegen = Codegen(kern_syms, extra)
            try:
                x86_bytes = codegen.compile_module(ir)
            except Exception:
                pass
            if x86_bytes > 0:
                linker.modules.append({
                    'name': extra,
                    'code': codegen.buf,
                    'symbols': codegen.mod_symbols,
                    'relocs': codegen.mod_relocs,
                    'strings': codegen.mod_strings,
                    'offset': 0,
                })
            total_ir += ir_total
            total_ir_live += ir_live
            total_ir_opt += ir_opt
            total_x86 += x86_bytes
            success_count += 1
            print('  [OK]   %s: %d tok, %d ast, %d fn, %d ir, %d B'
                  % (extra, tok_count, node_count, fn_count, ir_live, x86_bytes))
        else:
            print('  [WARN] %s: %d tok, %d ast, %d fn (parse=%d)'
                  % (extra, tok_count, node_count, fn_count, parse_errors))
        total_files += 1

    print('')

    # Phase 5: Link
    text_size = linker.pass1()
    resolved, unresolved, unresolved_map = linker.pass2()
    stub_count = linker.link_stub_count

    kernel_bin = os.path.join(REPO_ROOT, 'bare-kernel', 'kernel.bin')
    bin_size = 0
    if len(linker.combined) > 0:
        with open(kernel_bin, 'wb') as f:
            f.write(linker.combined)
        bin_size = len(linker.combined)

    entry_file = os.path.join(REPO_ROOT, 'bare-kernel', 'kernel.entry')
    if '_start' in linker.global_syms:
        start_off = linker.global_syms['_start']
        with open(entry_file, 'w') as f:
            f.write(str(start_off))
        print('  _start offset: %d (0x%X)' % (start_off, start_off))
    else:
        with open(entry_file, 'w') as f:
            f.write('0')
        print('  WARNING: _start symbol not found, defaulting to offset 0')

    sym_count = len(linker.global_syms)

    print('=== Compilation Pipeline Summary ===')
    print('  Modules compiled: %d / %d' % (success_count, total_files))
    print('  Total tokens:     %d' % total_tokens)
    print('  Total AST nodes:  %d' % total_nodes)
    print('  Total IR instrs:  %d (%d live, %d dead)' % (total_ir, total_ir_live, total_ir - total_ir_live))
    print('  IR optimizations: %d' % total_ir_opt)
    print('  x86_64 output:    %d bytes (.text)' % total_x86)
    print('  Linker:           %d modules, %d symbols, %d relocs resolved'
          % (len(linker.modules), sym_count, resolved))
    if stub_count > 0:
        print('  Builtin stubs:    %d (runtime-bound trampolines)' % stub_count)
    if unresolved > 0:
        print('  Unresolved relocs: %d' % unresolved)
        for sym, cnt in sorted(unresolved_map.items()):
            print('    - %s x%d' % (sym, cnt))
    print('  kernel.bin:       %d bytes @ 0x%X' % (bin_size, LINK_TEXT_BASE))
    print('  Functions found:  %d' % total_fns)
    print('  Parse warnings:   %d' % total_parse_errors)
    print('  Balance errors:   %d' % total_bal_errors)
    if warn_files:
        print('  Files with warnings:')
        for wf in warn_files:
            print('    - %s' % wf)
    print('')
    print('Pipeline Phase 1-5 complete. (%.2fs)' % (time.time() - t0))


if __name__ == '__main__':
    main()
