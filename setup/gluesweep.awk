# Finds script-callable glue that hands a Dynamic to something Dynamic cannot become.
#
# Under -D scriptable the compiler writes a wrapper per class member that reads every argument off
# the cppia stack as Dynamic. Dynamic converts to the numeric types, bool and hx::Object*, and to
# nothing else -- so a member whose signature mentions a raw pointer, a reference or a va_list
# produces C++ that does not compile.

# A glue call site: the wrapper handing stack slots to the real member.
/_obj::[a-zA-Z0-9_]+\(ctx->/ {
	line = $0
	while (match(line, /[A-Za-z0-9_]+_obj::[a-zA-Z0-9_]+\(ctx->/)) {
		call = substr(line, RSTART, RLENGTH - 6)
		glue[FILENAME, call] = 1
		line = substr(line, RSTART + RLENGTH)
	}
}

# A real definition: a return type, then the member, then the opening brace and nothing else.
# A call site sits inside an expression, where a `*` is multiplication -- matching those instead is
# how this reports pointers that are not there. Anchoring on the trailing `){` separates them, and
# leading whitespace has to be allowed because a definition may be indented by one space.
/^[ \t]*[A-Za-z_:][A-Za-z0-9_:<>, ]* [A-Za-z0-9_]+_obj::[a-zA-Z0-9_]+\([^)]*\)[ \t]*\{[ \t]*$/ {
	if ($0 ~ /ctx->/) next
	if (match($0, /[A-Za-z0-9_]+_obj::[a-zA-Z0-9_]+\([^)]*\)/)) {
		whole = substr($0, RSTART, RLENGTH)
		split(whole, part, "(")
		name = part[1]
		params = substr(whole, index(whole, "(") + 1)
		sub(/\)$/, "", params)
		if (!((FILENAME, name) in def)) {
			def[FILENAME, name] = params
			ret[FILENAME, name] = substr($0, 1, RSTART - 1)
		}
	}
}

END {
	for (key in glue) {
		if (!(key in def))
			continue

		params = def[key]
		reason = ""
		if (index(params, "*")) reason = "pointer parameter"
		else if (index(params, "&")) reason = "reference parameter"
		else if (index(params, "va_list")) reason = "va_list parameter"

		# A return the wrapper cannot publish back is the same defect on the way out.
		if (reason == "") {
			r = ret[key]
			if (index(r, "*") || index(r, "&"))
				reason = "pointer or reference return"
		}

		if (reason == "")
			continue

		split(key, k, SUBSEP)
		printf "  %-46s %-20s [%s]\n", k[2], reason, k[1]
	}
}
