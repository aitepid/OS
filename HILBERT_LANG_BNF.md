# Hilbert-Lang (H-L) 
# BNF (Backus-Naur Form) + Spatial Semantics
# Version 1.0 -- HicOS Project Constellation
#
# Design Principles:
#   1. Instructions are NOT in linear arrays -- they live in Hilbert-curve cells
#   2. All addressing uses O(1) bit-interleaved Hilbert transforms
#   3. `near` replaces global variables with spatial-proximity binding
#   4. Scopes are fractal quadrants of the parent curve
#   5. No-std compatible -- runs on bare metal

# ============================================================================
# 1  NOTATION
# ============================================================================
#
#   <rule>    ::=  definition
#   |              alternative
#   { ... }        zero or more repetitions
#   [ ... ]        optional
#   'text'         terminal string
#   /regex/        terminal pattern

# ============================================================================
# 2  LEXICAL GRAMMAR
# ============================================================================

<program>       ::= { <statement> }

<statement>     ::= <let_stmt>
                  |  <assign_stmt>
                  |  <fn_def>
                  |  <class_def>
                  |  <quadrant_def>
                  |  <if_stmt>
                  |  <while_stmt>
                  |  <for_stmt>
                  |  <return_stmt>
                  |  <yield_stmt>
                  |  <raise_stmt>
                  |  <break_stmt>
                  |  <continue_stmt>
                  |  <try_stmt>
                  |  <import_stmt>
                  |  <assert_stmt>
                  |  <del_stmt>
                  |  <pass_stmt>
                  |  <warp_stmt>
                  |  <emit_stmt>
                  |  <spawn_stmt>
                  |  <expr_stmt>

# ---- Variable Binding ----
# Spatial semantics: each `let` is assigned a Hilbert address at compile time.
# The address is derived from: d2xy(scope_order, allocation_seq) interleaved with scope_depth.

<let_stmt>      ::= 'let' [ 'mut' ] <ident> [ ':' <type_hint> ] '=' <expr> ';'
                  |  'let' [ 'mut' ] <destruct_pattern> '=' <expr> ';'

<destruct_pattern> ::= '[' <destruct_elem> { ',' <destruct_elem> } ']'
                     |  '(' <destruct_elem> { ',' <destruct_elem> } ')'
<destruct_elem>    ::= <ident>
                     |  <destruct_pattern>              # nested: let [a, [b, c]] = x;
                     |  '_'                              # wildcard (discard)

<assign_stmt>   ::= <ident> <assign_op> <expr> ';'
                  |  <destruct_pattern> '=' <expr> ';'   # destructuring assignment

<assign_op>     ::= '=' | '+=' | '-=' | '*=' | '/=' | '%=' | '**=' | '&=' | '|=' | '^=' | '<<=' | '>>='

# ---- Loop Control ----
<break_stmt>    ::= 'break' ';'
<continue_stmt> ::= 'continue' ';'

# ---- Exception Handling ----
<try_stmt>      ::= 'try' <block> { <catch_clause> } [ 'finally' <block> ]
<catch_clause>  ::= 'catch' [ <ident> [ ':' <ident> ] ] <block>
                  # catch e { }          -- catch all, bind to e
                  # catch e : TypeError { } -- catch only TypeError

<raise_stmt>    ::= 'raise' <expr> ';'   # throw exception object
                  |  'raise' ';'          # re-raise current exception

# ---- Generators / Yield ----
<yield_stmt>    ::= 'yield' <expr> ';'
                  |  'yield' ';'          # yield nil

# ---- Module System ----
<import_stmt>   ::= 'import' <string_lit> ';'
                  |  'import' <string_lit> 'as' <ident> ';'

# ---- Assertions ----
<assert_stmt>   ::= 'assert' <expr> [ ',' <string_lit> ] ';'

# ---- Delete ----
<del_stmt>      ::= 'del' <ident> ';'

# ---- Pass (no-op) ----
<pass_stmt>     ::= 'pass' ';'

# ---- Functions ----
# Each function occupies a "quadrant" of the parent Hilbert curve.
# Parameters inherit the quadrant's spatial address.
# Decorators wrap a function: @cache fn fib(n) { ... } == fn fib(n){...}; fib = cache(fib);

<fn_def>        ::= { <decorator> } 'fn' <ident> '(' [ <param_list> ] ')' [ '->' <type_hint> ] <block>

<decorator>     ::= '@' <ident> [ '(' [ <arg_list> ] ')' ]

<param_list>    ::= <param> { ',' <param> }
<param>         ::= <ident> [ ':' <type_hint> ] [ '=' <expr> ]     # optional type hint + default
                  |  '*' <ident>                                    # variadic (*args)
                  |  '**' <ident>                                   # keyword args (**kwargs)

<type_hint>     ::= <ident>                          # int, str, bool, float, etc.
                  |  <ident> '[' <type_hint> { ',' <type_hint> } ']'  # array[int], dict[str,int]
                  |  <ident> '|' <type_hint>          # union: int | str
                  |  'fn' '(' [ <type_hint> { ',' <type_hint> } ] ')' '->' <type_hint>  # callable

# ---- Fractal Scoping (Quadrants) ----
# A `quadrant` defines a sub-region of Hilbert space. It acts as a namespace
# AND a spatial partition. Variables inside are only accessible via `near`.

<quadrant_def>  ::= 'quadrant' <ident> <block>

# ---- Class / OOP ----
# class Name [: Parent] { ... }
# Supports single inheritance, magic methods (__init__, __str__, __call__, __eq__, etc.)

<class_def>     ::= 'class' <ident> [ ':' <ident> ] <block>

# Inside class blocks:
#   fn __init__(self, ...)      constructor
#   fn __str__(self)            to_string conversion
#   fn __repr__(self)           debug representation
#   fn __eq__(self, other)      equality check
#   fn __lt__(self, other)      less-than
#   fn __add__(self, other)     + operator
#   fn __sub__(self, other)     - operator
#   fn __mul__(self, other)     * operator
#   fn __len__(self)            len() support
#   fn __getitem__(self, key)   [] indexing
#   fn __setitem__(self, k, v)  [] assignment
#   fn __call__(self, ...)      callable object
#   fn __contains__(self, v)    'in' operator
#   fn __iter__(self)           for-in iteration
#   fn __hash__(self)           hash support
#   let class_var = value       class-level variable (shared)

# ---- Control Flow ----

<if_stmt>       ::= 'if' <expr> <block> { 'elif' <expr> <block> } [ 'else' <block> ]

<while_stmt>    ::= 'while' <expr> <block>

<for_stmt>      ::= 'for' <ident> 'in' <expr> <block>

<return_stmt>   ::= 'return' [ <expr> ] ';'

# ---- Spatial Primitives ----

# `warp <addr>` -- jump to an arbitrary Hilbert address (non-local goto)
<warp_stmt>     ::= 'warp' <expr> ';'

# `emit <channel> <value>` -- broadcast to all cells within spatial radius
<emit_stmt>     ::= 'emit' <ident> <expr> ';'

# `spawn <fn>(args) @sector` -- launch concurrent task in a Hilbert sector
<spawn_stmt>    ::= 'spawn' <ident> '(' [ <arg_list> ] ')' ';'

# ---- Expression Statement ----

<expr_stmt>     ::= <expr> ';'

# ---- Block ----

<block>         ::= '{' { <statement> } '}'

# ============================================================================
# 3  EXPRESSION GRAMMAR (Precedence Climbing)
# ============================================================================

<expr>          ::= <ternary_expr>

# Ternary: value_if_true if condition else value_if_false
<ternary_expr>  ::= <or_expr> [ 'if' <or_expr> 'else' <ternary_expr> ]

# Lambda: fn (x, y) x + y
<lambda_expr>   ::= 'fn' '(' [ <param_list> ] ')' <expr>

<or_expr>       ::= <and_expr> { '||' <and_expr> }

<and_expr>      ::= <bitor_expr> { '&&' <bitor_expr> }

# Bitwise operators (new -- Python-level)
<bitor_expr>    ::= <bitxor_expr> { '|' <bitxor_expr> }
<bitxor_expr>   ::= <bitand_expr> { '^' <bitand_expr> }
<bitand_expr>   ::= <cmp_expr> { '&' <cmp_expr> }

<cmp_expr>      ::= <shift_expr> { <cmp_op> <shift_expr> }

<cmp_op>        ::= '==' | '!=' | '<' | '>' | '<=' | '>=' | 'in' | 'not' 'in'

<shift_expr>    ::= <add_expr> { ( '<<' | '>>' ) <add_expr> }

<add_expr>      ::= <mul_expr> { ( '+' | '-' ) <mul_expr> }

<mul_expr>      ::= <power_expr> { ( '*' | '/' | '//' | '%' ) <power_expr> }

<power_expr>    ::= <unary_expr> [ '**' <power_expr> ]    # right-associative

<unary_expr>    ::= '-' <unary_expr>
                  |  '!' <unary_expr>
                  |  '~' <unary_expr>        # bitwise NOT
                  |  'near' <ident>          # spatial nearest-binding
                  |  <fold_expr>             # Hilbert curve segment reduce
                  |  <postfix_expr>

# `fold` -- reduce over a Hilbert-curve-ordered array
# The iterator traverses elements in their spatial curve order.
# fold <array> from <init> with <acc>, <elem> -> <body_expr>

<fold_expr>     ::= 'fold' <primary> 'from' <primary> 'with' <ident> ',' <ident> '->' <expr>

<postfix_expr>  ::= <primary> { <postfix_op> }

<postfix_op>    ::= '[' <expr> ']'                       # index  (negative: a[-1])
                  |  '[' <expr> ':' <expr> ']'             # slice  a[1:3]
                  |  '[' ':' <expr> ']'                    # slice  a[:3]
                  |  '[' <expr> ':' ']'                    # slice  a[1:]
                  |  '(' [ <arg_list> ] ')'               # call
                  |  '.' <ident> '(' [ <arg_list> ] ')'   # method call (desugars to builtin)
                  |  '.' <ident>                           # field access

<primary>       ::= <int_lit>
                  |  <float_lit>
                  |  <fstring_lit>       # f"hello {name}"  (string interpolation)
                  |  <string_lit>
                  |  <bool_lit>
                  |  'nil'
                  |  <ident>
                  |  '(' <expr> ')'
                  |  <array_lit>
                  |  <dict_lit>
                  |  <lambda_expr>

<array_lit>     ::= '[' [ <expr> { ',' <expr> } ] ']'
                  |  '[' <expr> 'for' <ident> 'in' <expr> [ 'if' <expr> ] ']'  # list comprehension

<dict_comp>     ::= '{' <expr> ':' <expr> 'for' <ident> 'in' <expr> [ 'if' <expr> ] '}'  # dict comprehension
<dict_lit>      ::= '{' [ <dict_entry> { ',' <dict_entry> } ] '}'
<dict_entry>    ::= <expr> ':' <expr>
<fstring_lit>   ::= 'f"' { <fstring_part> } '"'
<fstring_part>  ::= /[^{}"\\]+/            # literal text
                  |  '{' <expr> '}'          # interpolated expression

<arg_list>      ::= <expr> { ',' <expr> }

# ============================================================================
# 3.1  TYPES
# ============================================================================
#
# int       64-bit signed integer
# float     64-bit IEEE 754
# str       interned string (u16 index)
# bool      true | false
# array     dynamic array of Values: [1, "hello", [2, 3]]
# dict      key-value map: {"a": 1, "b": 2}
# fn        first-class function / closure
# class     object instance (dict with __class__ reference)
# generator lazy iterator created by functions containing yield
# nil       null/unit type
#
# Type hints are optional annotations (not enforced at runtime):
#   let x: int = 42;
#   fn add(a: int, b: int) -> int { return a + b; }

# ============================================================================
# 4  TERMINALS
# ============================================================================

<ident>         ::= /[a-zA-Z_][a-zA-Z0-9_]*/
<int_lit>       ::= /[0-9]+/
<float_lit>     ::= /[0-9]+\.[0-9]*/
<string_lit>    ::= '"' { /[^"\\]/ | '\\' /[ntr"\\]/ } '"'
<bool_lit>      ::= 'true' | 'false'

# ---- Keywords (reserved) ----
# let  mut  fn  return  if  elif  else  while  for  in  not
# near  quadrant  warp  emit  fold  spawn
# true  false  nil
# break  continue  try  catch  finally  raise
# import  as  assert  del  pass
# class  self  super  yield
# and  or

# ============================================================================
# 4.1  BUILTIN FUNCTIONS (Python-level)
# ============================================================================
#
# -- I/O --
# print(value)                    Output a value
# input()                         Read a line from stdin (interpreter: "")
#
# -- Type Conversion --
# int(x)                          Convert to integer
# float(x)                        Convert to float
# str(x)                          Convert to string  (alias: to_string)
# bool(x)                         Convert to boolean
# chr(n)                          Int -> char string
# ord(s)                          Char string -> int code
# hex(n)                          Int -> hex string "0x..."
#
# -- Type Checking --
# type_of(x)                      -> "int" | "float" | "str" | "bool" | "array" | "dict" | "fn" | "nil"
# isinstance(x, type_str)         Check type
#
# -- Array --
# len(array)                      Array length (or string length)
# push(array, value)              Append element (mutates), return array
# pop(array)                      Remove + return last element
# range(n)                        Generate [0, 1, ..., n-1]
# set_at(array, index, value)     Set element at index
# array_slice(arr, start, end)    Sub-array [start, end)
# array_find(arr, val)            First index of val, or -1
# array_contains(arr, val)        true if val in arr
# array_remove(arr, index)        Remove element at index, return new array
# array_reverse(arr)              Return reversed copy
# array_concat(a, b)              Concatenate two arrays
# array_sort(arr)                 Return sorted copy (numeric/lexicographic)
# array_unique(arr)               Remove duplicates
# array_flat(arr)                 Flatten one level
# array_join(arr, sep)            Join array of strings with separator
#
# -- String --
# str_len(s)                      String length (same as len)
# str_char_at(s, i)               Character (int code) at position i
# str_sub(s, start, end)          Substring [start, end)
# str_find(s, needle)             Index of first occurrence, or -1
# str_contains(s, needle)         true if needle in s
# str_starts_with(s, prefix)      true if s starts with prefix
# str_ends_with(s, suffix)        true if s ends with suffix
# str_replace(s, old, new)        Replace all occurrences
# str_split(s, sep)               Split into array of strings
# str_trim(s)                     Strip leading/trailing whitespace
# str_upper(s)                    Uppercase copy
# str_lower(s)                    Lowercase copy
# str_repeat(s, n)                Repeat string n times
# str_pad_start(s, width, ch)     Pad start to width with ch
# str_from_code(code)             Int -> single-char string
# str_to_code(s)                  First char -> int code
#
# -- Math --
# abs(n)                          Absolute value
# min(a, b)                       Minimum of two integers
# max(a, b)                       Maximum of two integers
# floor(n)                        Floor (integer part)
# round(n)                        Round to nearest integer
# clamp(n, lo, hi)                Clamp to [lo, hi]
# pow(base, exp)                  Exponentiation (also: base ** exp)
# divmod(a, b)                    -> [a // b, a % b]
# sum(arr)                        Sum of array elements
# math_sqrt(n)                    Integer square root
# math_pow(base, exp)             Exponentiation (stdlib)
# math_log2(n)                    Integer log base 2
# math_gcd(a, b)                  Greatest common divisor
# math_lcm(a, b)                  Least common multiple
#
# -- Map (key-value) --
# map_new()                       Create empty map
# map_set(m, key, val)            Set key, return map
# map_get(m, key)                 Get value or nil
# map_has(m, key)                 true if key exists
# map_delete(m, key)              Remove key
# map_keys(m)                     Array of keys
# map_values(m)                   Array of values
# map_entries(m)                  Array of [key, value] pairs
# map_size(m)                     Number of entries
# map_clear(m)                    Remove all entries
#
# -- Spatial (Hilbert intrinsics) --
# hilbert_encode(x, y, z)         3D -> spatial key (bit-interleave)
# hilbert_decode(key)             spatial key -> [x, y, z]
# hilbert_dist(key_a, key_b)      Manhattan distance in Hilbert space
#
# -- Reflection --
# type_of(value)                  -> "int" | "float" | "str" | "bool" | "array" | "dict" | "fn" | "nil"
# to_string(value)                Convert any value to string representation
#
# -- Functional (Python builtins) --
# map(fn, iterable)               Apply fn to each element -> new array
# filter(fn, iterable)            Keep elements where fn returns truthy
# sorted(arr)                     Return sorted copy
# reversed(arr)                   Return reversed copy
# enumerate(arr)                  -> [[0, a], [1, b], ...]
# zip(a, b)                       -> [[a0, b0], [a1, b1], ...]
# any(arr)                        true if any element is truthy
# all(arr)                        true if all elements are truthy
#
# -- Object/Dict introspection --
# dict()                          Create empty dict
# list(x)                         Convert to array
# keys(d)                         Dict keys
# values(d)                       Dict values
# items(d)                        Dict entries (= map_entries)
# hasattr(obj, key)               Check if key exists in dict
# getattr(obj, key, default)      Get value or default
# setattr(obj, key, val)          Set key-value pair
#
# -- Set operations (stdlib, on arrays) --
# set_new()                       Create empty set (unique array)
# set_add(s, val)                 Add element
# set_union(a, b)                 Union
# set_intersection(a, b)          Intersection
# set_difference(a, b)            Difference
# set_is_subset(a, b)             Subset check
#
# -- Method-call syntax (desugaring) --
# value.method(args)  desugars to  builtin_method(value, args)
# Examples:
#   arr.len()           => len(arr)
#   arr.push(v)         => push(arr, v)
#   arr.find(v)         => array_find(arr, v)
#   arr.contains(v)     => array_contains(arr, v)
#   arr.slice(a, b)     => array_slice(arr, a, b)
#   arr.join(sep)       => array_join(arr, sep)
#   arr.sort()          => array_sort(arr)
#   s.len()             => str_len(s)
#   s.find(n)           => str_find(s, n)
#   s.contains(n)       => str_contains(s, n)
#   s.starts_with(p)    => str_starts_with(s, p)
#   s.ends_with(p)      => str_ends_with(s, p)
#   s.replace(o, n)     => str_replace(s, o, n)
#   s.split(sep)        => str_split(s, sep)
#   s.trim()            => str_trim(s)
#   s.upper()           => str_upper(s)
#   s.lower()           => str_lower(s)
#   s.sub(a, b)         => str_sub(s, a, b)
#   s.pad_start(w, c)   => str_pad_start(s, w, c)
#   m.get(k)            => map_get(m, k)
#   m.set(k, v)         => map_set(m, k, v)
#   m.has(k)            => map_has(m, k)
#   m.delete(k)         => map_delete(m, k)
#   m.keys()            => map_keys(m)
#   m.values()          => map_values(m)
#   m.entries()          => map_entries(m)
#   m.size()            => map_size(m)
#   m.clear()           => map_clear(m)

# ============================================================================
# 5  SPATIAL ADDRESSING MODEL
# ============================================================================
#
# Every AST node, variable, and bytecode instruction is assigned a Hilbert address:
#
#   SpatialAddr = interleave3(hx, hy, depth)
#
# Where:
#   (hx, hy) = d2xy(ORDER, linear_alloc_seq)
#   depth    = fractal scope nesting level
#
# This means:
#   - Sequentially declared variables are Hilbert-curve-adjacent in memory
#   - Deeper scopes occupy higher Z-planes (third dimension)
#   - `near x` resolves to the variable named `x` with minimum
#     hilbert_distance(current_addr, x.addr) = manhattan(hx, hy, depth)
#
# Memory layout example (ORDER=4, 1616 grid):
#
#   -----------------------------------------------
#   - Hilbert curve fills 256 cells in 1616 grid -
#   -                                             -
#   -  let a -> addr(0,0,0)    --                 -
#   -  let b -> addr(1,0,0)     -- adjacent       -
#   -  let c -> addr(1,1,0)    --  in memory      -
#   -                                             -
#   -  quadrant physics {      depth=1            -
#   -    let g -> addr(0,0,1)   -- same xy        -
#   -    let v -> addr(1,0,1)    -- but Z=1       -
#   -  }                       --                 -
#   -                                             -
#   -  near g  -> resolves to physics.g            -
#   -           (minimum spatial distance)         -
#   -----------------------------------------------

# ============================================================================
# 6  BYTECODE FORMAT (HilbertCode)
# ============================================================================
#
# Each bytecode cell:
#   struct CodeCell {
#       addr: SpatialAddr,  // u32 -- Hilbert-interleaved position
#       op:   Opcode,       // enum -- instruction
#   }
#
# Opcodes:
#   LoadInt(i64), LoadFloat(f64), LoadStr(u16), LoadBool(bool)
#   LoadVar(u16), StoreVar(u16)
#   Add, Sub, Mul, Div, Mod
#   Eq, Neq, Lt, Gt, Lte, Gte, And, Or, Not, Neg
#   Call(addr, argc), Return
#   Jump(SpatialAddr), JumpIfFalse(SpatialAddr)
#   Near(slot)           resolved at compile time via spatial distance
#   Emit(channel_id)     broadcast value on stack
#   Spawn(sector, argc)  launch in Hilbert sector
#   Print                builtin I/O
#   Halt
#
# Code execution:
#   PC is an index into the cells array.
#   Jump targets are SpatialAddr -> O(1) lookup via precomputed index table.
#   The index table is cache-line aligned for minimal fetch latency.

# ============================================================================
# 7  CONCURRENCY MODEL -- Spatial Sector Partitioning
# ============================================================================
#
# The Hilbert space is divided into sectors (quadrants at a chosen depth).
# Each sector can be assigned to a different hardware core.
#
# Properties:
#   - Sectors are spatially disjoint -> no cache coherency conflicts
#   - Variables in sector A are guaranteed to be on different cache lines
#     than variables in sector B (because Hilbert-adjacent items share lines,
#     and sectors are Hilbert-distant)
#   - `spawn task() @sector` pins the task to that spatial region
#   - `emit channel value` broadcasts only to the enclosing sector + neighbors
#
# This is fundamentally different from thread-based concurrency:
#   Traditional: thread 1 and thread 2 may access any memory -> need locks
#   H-L:         sector 1 and sector 2 own disjoint spatial regions -> lock-free

# ============================================================================
# 8  CACHE-AWARE EXECUTION
# ============================================================================
#
# The VM aligns variable storage to 64-byte cache lines:
#   #[repr(align(64))]
#   struct VarStorage { slots: [Value; 1024] }
#
# Because Hilbert-adjacent variables map to adjacent slots,
# accessing `a`, `b`, `c` (declared sequentially) fetches one cache line.
#
# Instruction fetch is similarly optimized:
#   - Code cells are stored in Hilbert curve order
#   - Sequential execution follows the curve -> stays in L1 cache
#   - Jumps within the same quadrant stay in L2 cache

# ============================================================================
# 9  EXAMPLE PROGRAMS
# ============================================================================

# --- Hello World ---
# print("Hello, Hilbert World!");

# --- Fibonacci with spatial variables ---
# let a = 0;
# let b = 1;
# let mut i = 0;
# while i < 10 {
#     let tmp = a + b;
#     a = b;
#     b = tmp;
#     i = i + 1;
# }
# print(b);

# --- Fractal scope with near ---
# quadrant physics {
#     let gravity = 9;
#     let mass = 42;
# }
# quadrant render {
#     let g = near gravity;  // resolves to physics.gravity (spatially closest)
#     print(g);
# }

# --- Spatial concurrency ---
# fn compute(x) {
#     return x * x;
# }
# spawn compute(42);  // launched in separate Hilbert sector

# ============================================================================
# END OF SPECIFICATION
# ============================================================================
