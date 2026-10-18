class_name AICache
extends RefCounted
## Remembers accepted AI replies, so the same question is never paid for twice. Keyed on everything
## that shapes an answer: provider, task, prompt version, tier, system, prompt and schema. Keeps the
## `capacity` most recently used replies in memory; with a directory it also keeps them on disk
## (one small JSON file each) across sessions.

const DISK_DIR := "user://ai_cache/"
const DISK_FACTOR := 4 ## the disk keeps up to this many times `capacity` replies

var capacity: int
var directory: String ## "" keeps the cache in memory only (tests)
var hits := 0
var misses := 0
var _entries := {} ## key -> reply; dictionaries keep insertion order, so the first key is the least recently used


func _init(max_entries: int = 256, persist_dir: String = "") -> void:
	capacity = maxi(max_entries, 1)
	directory = persist_dir
	if directory:
		DirAccess.make_dir_recursive_absolute(directory)
		_prune_disk(capacity * DISK_FACTOR)


static func key(provider_id: String, request: AIRequest) -> String:
	var parts := [provider_id, request.task, request.prompt_version, request.tier, request.system, request.prompt, request.schema]
	return JSON.stringify(parts, "", true).sha256_text()


## The cached reply, or {} on a miss.
func lookup(cache_key: String) -> Dictionary:
	var reply: Variant = _entries.get(cache_key)
	if reply == null and directory:
		reply = JSON.parse_string(FileAccess.get_file_as_string(_path(cache_key))) if FileAccess.file_exists(_path(cache_key)) else null
	if not reply is Dictionary:
		misses += 1
		return {}
	hits += 1
	_remember(cache_key, reply)
	return (reply as Dictionary).duplicate(true)


func store(cache_key: String, reply: Dictionary) -> void:
	_remember(cache_key, reply.duplicate(true))
	if directory:
		var file := FileAccess.open(_path(cache_key), FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(reply))


func forget(cache_key: String) -> void:
	_entries.erase(cache_key)
	if directory and FileAccess.file_exists(_path(cache_key)):
		DirAccess.remove_absolute(_path(cache_key))


func size() -> int:
	return _entries.size()


func _remember(cache_key: String, reply: Dictionary) -> void:
	_entries.erase(cache_key)
	_entries[cache_key] = reply
	while _entries.size() > capacity:
		_entries.erase(_entries.keys()[0])


## Keeps the disk cache from growing without end: past `limit` files, the oldest go.
func _prune_disk(limit: int) -> void:
	var files := Array(DirAccess.get_files_at(directory))
	if files.size() <= limit:
		return
	var age := func(file: String) -> int: return FileAccess.get_modified_time(directory.path_join(file))
	files.sort_custom(func(a: String, b: String) -> bool: return age.call(a) < age.call(b))
	for file: String in files.slice(0, files.size() - limit):
		DirAccess.remove_absolute(directory.path_join(file))


func _path(cache_key: String) -> String:
	return directory.path_join(cache_key + ".json")
