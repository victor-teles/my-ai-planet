class_name SseParser
extends RefCounted
## Splits a server-sent events stream into the data of each event. Feed it bytes as they
## arrive: lines are cut on bytes, so a character split between two chunks stays whole.

var _buffer := PackedByteArray()
var _data := PackedStringArray()


## Returns the data of every event completed by these bytes.
func feed(bytes: PackedByteArray) -> PackedStringArray:
	_buffer.append_array(bytes)
	var events := PackedStringArray()
	var start := 0
	var newline := _buffer.find(10, start)
	while newline != -1:
		_add(events, _read_line(_buffer.slice(start, newline).get_string_from_utf8().trim_suffix("\r")))
		start = newline + 1
		newline = _buffer.find(10, start)
	_buffer = _buffer.slice(start)
	return events


## Call when the stream ends: returns the last event if it wasn't followed by a blank line.
func finish() -> PackedStringArray:
	var events := PackedStringArray()
	if not _buffer.is_empty():
		_add(events, _read_line(_buffer.get_string_from_utf8().trim_suffix("\r")))
		_buffer = PackedByteArray()
	_add(events, _read_line(""))
	return events


## Every event's data in a complete stream.
static func parse(text: String) -> PackedStringArray:
	var parser := SseParser.new()
	var events := parser.feed(text.to_utf8_buffer())
	events.append_array(parser.finish())
	return events


## Returns the event's data when the line ends an event, else "". Only data lines matter here;
## comments (":") and event, id and retry fields are skipped.
func _read_line(line: String) -> String:
	if line.is_empty() and not _data.is_empty():
		var data := "\n".join(_data)
		_data = PackedStringArray()
		return data
	if line.begins_with("data:"):
		_data.append(line.substr(5).trim_prefix(" "))
	return ""


static func _add(events: PackedStringArray, data: String) -> void:
	if not data.is_empty():
		events.append(data)
