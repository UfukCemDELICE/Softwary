# softwary: structural checks of a CALM 1.3 model plus softwary's component
# fields. Input: the model. Output: one "<json path>: <problem>" per line.
# Used by lib/model.sh; written for jq 1.6 and later.

def fmt: map(if type == "number" then "[\(.)]" else ".\(.)" end) | join("") | ltrimstr(".")
	| if . == "" then "(root)" else . end;
def nonempty_string: type == "string" and length > 0;
def str_problem($p): if nonempty_string then empty else [$p, "missing or not a non-empty string"] end;
# metadata as one object: an object, or an array of objects merged in order.
def meta:
	if type == "object" then .
	elif type == "array" and all(.[]; type == "object") then (add // {})
	else null end;

def meta_problems($p; $m):
	(if $m | has("paths") then
		(if ($m.paths | type) == "array" and ($m.paths | length) > 0 and all($m.paths[]; nonempty_string)
		then empty else [$p + ["paths"], "must be a non-empty array of non-empty strings"] end)
	else empty end),
	(if ($m | has("risk")) and $m.risk != "UNSET" and ($m.risk | IN("R1", "R2", "R3") | not)
	then [$p + ["risk"], "must be R1, R2 or R3"] else empty end),
	(if ($m | has("status")) and $m.status != "UNSET" and ($m.status | IN("planned", "active", "deprecated") | not)
	then [$p + ["status"], "must be planned, active or deprecated"] else empty end),
	(if ($m | has("features")) and (($m.features | type) != "array" or ($m.features | length) == 0
		or (all($m.features[]; type == "string" and test("^F[1-9][0-9]*$")) | not))
	then [$p + ["features"], "must be a non-empty array of feature ids (F1, F2, ...)"] else empty end),
	(if $m | has("paths") then
		("risk", "status") as $f | select($m | has($f) | not) | [$p + [$f], "required when paths is set"]
	else empty end);

def node_problems($p):
	if type != "object" then [$p, "must be an object"]
	else
		(("unique-id", "node-type", "name", "description") as $f | .[$f] | str_problem($p + [$f])),
		(if has("metadata") then
			(.metadata | meta) as $m
			| if $m == null then [$p + ["metadata"], "must be an object or an array of objects"]
			else meta_problems($p + ["metadata"]; $m) end
		else empty end)
	end;

if type != "object" then [[], "must be a JSON object"]
else
	(if (.nodes | type) == "array" then .nodes else [] end) as $nodes
	| (if (.relationships | type) == "array" then .relationships else [] end) as $rels
	| [$nodes[] | objects | ."unique-id" | strings] as $nids
	| (reduce ($nodes[] | objects | select(."unique-id" | type == "string")) as $n ({};
		.[$n."unique-id"] = [($n.interfaces // [])[]? | objects | ."unique-id" | strings])) as $ifaces
	| def ref($q; $id):
		if ($id | nonempty_string | not) then [$q, "missing or not a non-empty string"]
		elif any($nids[]; . == $id) then empty
		else [$q, "unknown node '\($id)'"] end;
	def refs($q):
		if type == "array" and length > 0 then to_entries[] | ref($q + [.key]; .value)
		else [$q, "must be a non-empty array of node ids"] end;
	def end_ref($q; $e):
		if ($e | type) != "object" then [$q, "must be an object"]
		else ref($q + ["node"]; $e.node),
			(($e.interfaces // []) | if type == "array" then to_entries[]
				| .key as $j | .value as $iv
				| if any(($ifaces[$e.node | tostring] // [])[]; . == $iv) then empty
				else [$q + ["interfaces", $j], "unknown interface '\($iv)' on node '\($e.node)'"] end
			else [$q + ["interfaces"], "must be an array"] end)
		end;
	def rel_problems($p):
		if type != "object" then [$p, "must be an object"]
		else
			(."unique-id" | str_problem($p + ["unique-id"])),
			(."relationship-type" as $rt
			| ["interacts", "connects", "deployed-in", "composed-of", "options"] as $types
			| if ($rt | type) != "object" or ($rt | length) != 1 or ($rt | keys[0] | IN($types[]) | not)
			then [$p + ["relationship-type"], "must have exactly one of interacts, connects, deployed-in, composed-of, options"]
			else ($rt | keys[0]) as $k | $rt[$k] as $v | ($p + ["relationship-type", $k]) as $q
				| if ($v | type) != "object" then [$q, "must be an object"]
				elif $k == "interacts" then ref($q + ["actor"]; $v.actor), ($v.nodes | refs($q + ["nodes"]))
				elif $k == "connects" then end_ref($q + ["source"]; $v.source), end_ref($q + ["destination"]; $v.destination)
				elif $k == "options" then empty
				else ref($q + ["container"]; $v.container), ($v.nodes | refs($q + ["nodes"]))
				end
			end)
		end;
	# every unique-id with its path, in document order
	[($nodes | to_entries[] | .key as $i | .value | objects
		| (select(."unique-id" | type == "string") | [["nodes", $i, "unique-id"], ."unique-id"]),
		(.interfaces // [] | if type == "array" then to_entries[] | .key as $j | .value | objects
			| select(."unique-id" | type == "string") | [["nodes", $i, "interfaces", $j, "unique-id"], ."unique-id"]
		else empty end)),
	($rels | to_entries[] | .key as $i | .value | objects
		| select(."unique-id" | type == "string") | [["relationships", $i, "unique-id"], ."unique-id"])] as $ids
	| (if (.nodes | type) != "array" or (.nodes | length) == 0 then [["nodes"], "must be a non-empty array"] else empty end),
	(if has("relationships") and (.relationships | type) != "array" then [["relationships"], "must be an array"] else empty end),
	($nodes | to_entries[] | .key as $i | .value | node_problems(["nodes", $i])),
	($rels | to_entries[] | .key as $i | .value | rel_problems(["relationships", $i])),
	(range($ids | length) as $k | $ids[$k] as $e
		| select(any($ids[:$k][]; .[1] == $e[1])) | [$e[0], "duplicate '\($e[1])'"]),
	(paths(type == "string" and . == "UNSET") as $q | [$q, "is UNSET"])
end
| "\(.[0] | fmt): \(.[1])"
