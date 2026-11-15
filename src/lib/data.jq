# softwary: structural checks of the data model architecture/data/model.json.
# Input: the data model. Output: one "<json path>: <problem>" per line.
# Used by lib/product.sh; written for jq 1.6 and later.

def fmt: map(if type == "number" then "[\(.)]" else ".\(.)" end) | join("") | ltrimstr(".")
	| if . == "" then "(root)" else . end;
def nonempty_string: type == "string" and length > 0;
def str_problem($p): if nonempty_string then empty else [$p, "missing or not a non-empty string"] end;
["one-to-one", "one-to-many", "many-to-one", "many-to-many"] as $kinds

| def field_problems($p):
	if type != "object" then [$p, "must be an object"]
	else
		(.name | str_problem($p + ["name"])),
		(.type | str_problem($p + ["type"])),
		(if has("required") and (.required | type) != "boolean" then [$p + ["required"], "must be true or false"] else empty end)
	end;
def relation_problems($p; $ids):
	if type != "object" then [$p, "must be an object"]
	else
		(.to as $t
			| if ($t | nonempty_string | not) then [$p + ["to"], "missing or not a non-empty string"]
			elif $t == "UNSET" or any($ids[]; . == $t) then empty
			else [$p + ["to"], "unknown entity '\($t)'"] end),
		(if (.kind | IN($kinds[])) then empty
		else [$p + ["kind"], "must be one of \($kinds | join(", "))"] end)
	end;
def entity_problems($p; $ids):
	if type != "object" then [$p, "must be an object"]
	else
		(.id | str_problem($p + ["id"])),
		(if (.id | type) == "string" and .id != "UNSET" and (.id | test("^[a-z][a-z0-9_-]*$") | not)
		then [$p + ["id"], "must match ^[a-z][a-z0-9_-]*$"] else empty end),
		(.name | str_problem($p + ["name"])),
		(if (.fields | type) != "array" or (.fields | length) == 0 then [$p + ["fields"], "must be a non-empty array"]
		else
			(.fields | to_entries[] | .key as $j | .value | field_problems($p + ["fields", $j])),
			([.fields | to_entries[] | select((.value | type) == "object" and (.value.name | type) == "string") | [.key, .value.name]] as $fn
				| range($fn | length) as $k | $fn[$k] as $e
				| select(any($fn[:$k][]; .[1] == $e[1])) | [$p + ["fields", $e[0], "name"], "duplicate field '\($e[1])'"])
		end),
		(if has("relations") then
			if (.relations | type) != "array" then [$p + ["relations"], "must be an array"]
			else (.relations | to_entries[] | .key as $j | .value | relation_problems($p + ["relations", $j]; $ids)) end
		else empty end)
	end;

if type != "object" then [[], "must be a JSON object"]
elif (.entities | type) != "array" then [["entities"], "must be an array"]
else
	[.entities[] | objects | .id | strings] as $ids
	| ([.entities | to_entries[] | select((.value | type) == "object" and (.value.id | type) == "string") | [.key, .value.id]] as $en
		| range($en | length) as $k | $en[$k] as $e
		| select(any($en[:$k][]; .[1] == $e[1])) | [["entities", $e[0], "id"], "duplicate '\($e[1])'"]),
	(.entities | to_entries[] | .key as $i | .value | entity_problems(["entities", $i]; $ids)),
	(paths(type == "string" and . == "UNSET") as $q | [$q, "is UNSET"])
end
| "\(.[0] | fmt): \(.[1])"
