class_name AssetKinds
extends RefCounted
## Every kind of AI-authored asset, in one list. Add a kind here, with its prompt task in
## prompt_library/manifest.json, its schema, and its offline writer.

const SCRIPTS: Array[Script] = [
]

static var _all: Array[AssetKind] = []


static func all() -> Array[AssetKind]:
	if _all.is_empty():
		for script: Script in SCRIPTS:
			_all.append(script.new() as AssetKind)
		_all.sort_custom(func(a: AssetKind, b: AssetKind) -> bool: return a.priority() < b.priority())
	return _all


## The kind whose task this is, or null.
static func find(task: String) -> AssetKind:
	for kind: AssetKind in all():
		if kind.task() == task:
			return kind
	return null


static func tasks() -> Array[String]:
	var names: Array[String] = []
	for kind: AssetKind in all():
		names.append(kind.task())
	return names
