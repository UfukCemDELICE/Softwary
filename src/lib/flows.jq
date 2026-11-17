# softwary: structural checks of one flow file architecture/flows/<id>.json.
# Input: the flow. Arguments: $id (the file name without .json), $nodes (the
# unique ids of the model's components), $entities (the data model's entity
# ids), $features (the product's feature ids).
# Output: one "<json path>: <problem>" per line. Used by lib/flows.sh;
# written for jq 1.6 and later.

def fmt: map(if type == "number" then "[\(.)]" else ".\(.)" end) | join("") | ltrimstr(".")
	| if . == "" then "(root)" else . end;
def nonempty_string: type == "string" and length > 0;
def str_problem($p): if nonempty_string then empty else [$p, "missing or not a non-empty string"] end;
["concurrency", "retry", "crash"] as $traits

| def ids_problem($p; $what; $known; $label):
	if type != "array" or length == 0 or (all(.[]; nonempty_string) | not) then [$p, "must be a non-empty array of \($what)"]
	else to_entries[] | .key as $i | .value as $v
		| if any($known[]; . == $v) then empty else [$p + [$i], ($label | sub("@"; "'\($v)'"))] end
	end;

if type != "object" then [[], "must be a JSON object"]
else
	(.participants | if type == "array" then [.[] | strings] else [] end) as $parts
	| (if (.id | type) != "string" then [["id"], "missing or not a non-empty string"]
	elif (.id | test("^[a-z][a-z0-9-]*$") | not) then [["id"], "must match ^[a-z][a-z0-9-]*$"]
	elif .id != $id then [["id"], "'\(.id)' must be the file name '\($id)'"]
	else empty end),
	(.name | str_problem(["name"])),
	(.features | if type != "array" or length == 0 or (all(.[]; type == "string" and test("^F[1-9][0-9]*$") or . == "UNSET") | not)
		then [["features"], "must be a non-empty array of feature ids (F1, F2, ...)"]
		else to_entries[] | .key as $i | .value as $f
			| if $f == "UNSET" or any($features[]; . == $f) then empty
			else [["features", $i], "feature \($f) is not in the product"] end
		end),
	(.participants | ids_problem(["participants"]; "component ids"; $nodes; "unknown component @")),
	(if has("entities") then
		.entities | if type != "array" or (all(.[]; nonempty_string) | not) then [["entities"], "must be an array of entity ids"]
		else to_entries[] | .key as $i | .value as $e
			| if any($entities[]; . == $e) then empty else [["entities", $i], "unknown entity '\($e)'"] end
		end
	else empty end),
	(.steps | if type != "array" or length == 0 then [["steps"], "must be a non-empty array"]
		else to_entries[] | .key as $i | .value
			| if type != "object" then [["steps", $i], "must be an object"]
			else
				(("from", "to") as $e | .[$e] | . as $v
					| if nonempty_string | not then [["steps", $i, $e], "missing or not a non-empty string"]
					elif any($parts[]; . == $v) then empty
					else [["steps", $i, $e], "'\($v)' is not a participant of this flow"] end),
				(.action | str_problem(["steps", $i, "action"])),
				(if has("data") and (.data | type) != "string" then [["steps", $i, "data"], "must be a string"] else empty end)
			end
		end),
	(if has("traits") then
		.traits | if type != "array" then [["traits"], "must be an array"]
		else to_entries[] | .key as $i | .value as $t
			| if (($t | type) == "string") and any($traits[]; . == $t) then empty
			else [["traits", $i], "unknown trait '\($t)' (use \($traits | join(", ")))"] end
		end
	else empty end),
	(if has("formal") then
		(.formal | if type == "string" and (test("^[a-z][a-z0-9_]*$") or . == "UNSET") then empty
			else [["formal"], "must match ^[a-z][a-z0-9_]*$"] end)
	elif ((.traits // []) | type) == "array" and ((.traits // []) | length) > 0 then
		[["formal"], "missing; a flow with traits needs a formal specification"]
	else empty end),
	(paths(type == "string" and . == "UNSET") as $q | [$q, "is UNSET"])
end
| "\(.[0] | fmt): \(.[1])"
