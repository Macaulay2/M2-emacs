-- Regenerate M2-operators.el from the parsing tables of the running
-- Macaulay2.  Run "make update-operators".
--
-- The Style package's generateGrammar has no placeholder for operators, so
-- the substitution is done here rather than there.

debug Core -- for getParsing

-- getParsing returns {precedence, binaryStrength, unaryStrength}, with a
-- strength of -1 where the operator has no such form.  binding.d gives a
-- binary operator the strength of its precedence when it is left
-- associative, and one less when it is right associative.
parsing = new HashTable from apply(
    select(values Core.Dictionary, s -> instance(value s, Keyword)),
    s -> toString s => getParsing s)

opPrecedence = op -> (parsing#op)#0
binaryStrength = op -> (parsing#op)#1
unaryStrength = op -> (parsing#op)#2
isBinary = op -> binaryStrength op != -1
isLeftAssociative = op -> binaryStrength op == opPrecedence op

-- SPACE is adjacency, which has no symbol to match, and ";" separates
-- statements, which M2-smie-grammar describes with a production of its own.
binaryOperators = sort select(keys parsing,
    op -> isBinary op and op != "SPACE" and op != ";")

-- A postfix operator has neither a binary nor a unary form.  That also
-- describes the closing delimiters, which belong to the grammar instead.
-- (*) is left out as well: it is already balanced parentheses, so both
-- directions of the lexer decline it and let SMIE step over it as a sexp,
-- which is what keeps them exact inverses of one another.
notReallyPostfix = set {")", "]", "}", "|>", "(*)"}
postfixOperators = sort select(keys parsing,
    op -> not isBinary op and unaryStrength op == -1
    and not notReallyPostfix#?op)

-- smie-precs->prec2 wants the loosest level first, and one associativity per
-- row.  Macaulay2 has one level of mixed associativity, the multiplicative
-- one holding both / and \, so split such a level in two.  Listing the
-- right associative half first is what the language grammar does, and is
-- observationally equivalent, since a right associative operator binds its
-- right operand one level down in any case.
-- Within a row smie-prec2->grammar hands each operator a distinct level
-- descending from the first rather than the shared one its docstring
-- describes, but the relations it derives them from are the same whatever
-- the order, and re-indenting Macaulay2's own sources gives identical output
-- either way.  Sort so that the generated file is reproducible.
row = (assoc, ops) -> concatenate("(", assoc, " ", demark(" ", format \ sort ops), ")")

levels = apply(sort unique apply(binaryOperators, opPrecedence), p -> (
	ops := select(binaryOperators, op -> opPrecedence op == p);
	rights := select(ops, op -> not isLeftAssociative op);
	lefts := select(ops, isLeftAssociative);
	rows := {};
	if #rights > 0 then rows = append(rows, row("right", rights));
	if #lefts > 0 then rows = append(rows, row("left", lefts));
	demark("\n    ", rows)))

-- replace treats a backslash in the replacement as an escape, so any that
-- format produced have to be doubled to survive the substitution.
protect' = s -> replace("\\\\", "\\\\\\\\", s)

template = get "./M2-operators.el.in"
bannerText = concatenate("Auto-generated for Macaulay2-", version#"VERSION",
    ". Do not modify this file manually.")
output = replace("@M2BANNER@", bannerText, template)
output = replace("@M2VERSION@", version#"VERSION", output)
output = replace("@M2BINARYOPS@", protect' demark("\n    ", levels), output)
output = replace("@M2POSTFIXOPS@", protect' demark(" ", format \ postfixOperators), output)
"./M2-operators.el" << output << close

printerr("generated M2-operators.el for Macaulay2-", version#"VERSION")
