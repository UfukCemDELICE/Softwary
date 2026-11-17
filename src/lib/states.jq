# softwary: structural checks of one state machine file
# architecture/states/<entity>.json.
# Input: the state machine. Arguments: $id (the file name without .json) and
# $entities (the data model's entity ids).
# Output: one "<json path>: <problem>" per line. Used by lib/flows.sh;
# written for jq 1.6 and later.

def fmt: map(if type == "number" then "[\(.)]" else ".\(.)" end) | join("") | ltrimstr(".")
	| if . == "" then "(root)" else . end;
def nonempty_string: type == "string" and length > 0;
def str_problem($p): if nonempty_string then empty else [$p, "missing or not a non-empty string"] end;
def ident: type == "string" and test("^[a-z][a-z0-9_]*$");

if type != "object" then [[], "must be a JSON object"]
else
	(.states | if type == "array" then [.[] | strings] else [] end) as $states
	| (.transitions | if type == "array" then [.[] | objects | select((.from | type) == "string" and (.to | type) == "string")] else [] end) as $edges
	| (.initial) as $init
	| (if ($init | type) == "string" and any($states[]; . == $init) then
		[$init] | until(. as $s | [$edges[] | select(. as $e | $s | index($e.from)) | .to] | all(.[]; . as $t | $s | index($t)); . as $s
			| $s + ([$edges[] | select(. as $e | $s | index($e.from)) | .to] | map(select(. as $t | $s | index($t) | not)) | unique))
	else null end) as $reach
	| (.entity | if (type != "string") or length == 0 then [["entity"], "missing or not a non-empty string"]
		elif . != $id then [["entity"], "'\(.)' must be the file name '\($id)'"]
		else empty end),
	(if any($entities[]; . == $id) then empty else [null, "file name '\($id)' is not an entity of the data model"] end),
	(.states | if type != "array" or length == 0 then [["states"], "must be a non-empty array of state names"]
		else to_entries[] | .key as $i | .value as $v
			| if ($v | ident | not) and $v != "UNSET" then [["states", $i], "must match ^[a-z][a-z0-9_]*$"] else empty end
		end),
	(if (.states | type) == "array" then
		([.states | to_entries[] | select((.value | type) == "string")] as $en
			| range($en | length) as $k | $en[$k] as $e
			| select(any($en[:$k][]; .value == $e.value)) | [["states", $e.key], "duplicate '\($e.value)'"])
	else empty end),
	(if ($init | type) != "string" or ($init | length) == 0 then [["initial"], "missing or not a non-empty string"]
	elif any($states[]; . == $init) | not then [["initial"], "'\($init)' is not a declared state"]
	else empty end),
	(if has("final") then
		.final | if type != "array" then [["final"], "must be an array of state names"]
		else to_entries[] | .key as $i | .value as $v
			| if any($states[]; . == $v) then empty else [["final", $i], "'\($v)' is not a declared state"] end
		end
	else empty end),
	(.transitions | if type != "array" or length == 0 then [["transitions"], "must be a non-empty array"]
		else to_entries[] | .key as $i | .value
			| if type != "object" then [["transitions", $i], "must be an object"]
			else
				(("from", "to") as $e | .[$e] | . as $v
					| if nonempty_string | not then [["transitions", $i, $e], "missing or not a non-empty string"]
					elif any($states[]; . == $v) then empty
					else [["transitions", $i, $e], "'\($v)' is not a declared state"] end),
				(.event | if ident or . == "UNSET" then empty
					elif nonempty_string then [["transitions", $i, "event"], "must match ^[a-z][a-z0-9_]*$"]
					else [["transitions", $i, "event"], "missing or not a non-empty string"] end),
				(if has("guard") and (.guard | type) != "string" then [["transitions", $i, "guard"], "must be a string"] else empty end)
			end
		end),
	([.transitions | if type == "array" then to_entries[] | select((.value | type) == "object" and (.value.from | type) == "string" and (.value.event | type) == "string") else empty end] as $te
		| range($te | length) as $k | $te[$k] as $e
		| ([$te[:$k][] | select(.value.from == $e.value.from and .value.event == $e.value.event)] | first // null) as $first
		| select($first != null)
		| [["transitions", $e.key], "state '\($e.value.from)' already has a transition on event '\($e.value.event)' (transitions[\($first.key)])"]),
	(if $reach != null then
		($states[] | select(. as $s | $reach | index($s) | not)
			| [null, "state '\(.)' is not reachable from the initial state '\($init)'"]) else empty end),
	(((.final // []) | if type == "array" then . else [] end) as $fin
		| $states[] | select(. as $s | ($fin | index($s) | not) and ([$edges[] | select(.from == $s)] | length == 0))
		| [null, "state '\(.)' has no transition out and is not final"]),
	(if has("formal") then
		(.formal | if type == "string" and (test("^[a-z][a-z0-9_]*$") or . == "UNSET") then empty
			else [["formal"], "must match ^[a-z][a-z0-9_]*$"] end)
	else [["formal"], "missing; every state machine needs a TLA+ specification"] end),
	(paths(type == "string" and . == "UNSET") as $q | [$q, "is UNSET"])
end
| if .[0] == null then .[1] else "\(.[0] | fmt): \(.[1])" end
