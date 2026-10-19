class_name PartialJson
extends RefCounted
## Reads one string field out of a JSON object that is still arriving, so streamed chronicles can
## show their story while the model writes it. Tolerates anything before the first "{" (a code
## fence, a preamble) and a reply cut off anywhere: mid-key, mid-value or mid-escape.


## The decoded value of the top-level string field `key` so far, or "" if it hasn't started.
static func string_field(raw: String, key: String) -> String:
	var i := raw.find("{")
	if i == -1:
		return ""
	var depth := 0
	var expect_key := false
	while i < raw.length():
		var c := raw[i]
		if c == "\"":
			var read := _read_string(raw, i + 1)
			if not read[2]:
				return ""
			i = read[1]
			if depth != 1 or not expect_key:
				continue
			expect_key = false
			i = _skip_space(raw, i)
			if i >= raw.length() or raw[i] != ":":
				return ""
			i = _skip_space(raw, i + 1)
			if read[0] == key:
				return _read_string(raw, i + 1)[0] if i < raw.length() and raw[i] == "\"" else ""
			continue
		if c == "{" or c == "[":
			depth += 1
			expect_key = c == "{" and depth == 1
		elif c == "}" or c == "]":
			depth -= 1
		elif c == ",":
			expect_key = depth == 1
		i += 1
	return ""


## Decodes a JSON string starting after its opening quote: [text, index after the closing quote,
## closed]. A truncated string returns what is readable so far, never half an escape.
static func _read_string(raw: String, start: int) -> Array:
	var text := ""
	var i := start
	while i < raw.length():
		var c := raw[i]
		if c == "\"":
			return [text, i + 1, true]
		if c != "\\":
			text += c
			i += 1
			continue
		if i + 1 >= raw.length():
			break
		var escape := raw[i + 1]
		if escape == "u":
			var code := _hex(raw, i + 2)
			if code < 0:
				break
			i += 6
			if code >= 0xD800 and code <= 0xDBFF:
				# A surrogate pair: wait for its second half before showing the character.
				var low := _hex(raw, i + 2) if raw.substr(i, 2) == "\\u" else -1
				if low < 0:
					break
				code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
				i += 6
			text += char(code)
			continue
		text += {"n": "\n", "t": "\t", "r": "", "b": "", "f": "", "/": "/", "\\": "\\", "\"": "\""}.get(escape, escape)
		i += 2
	return [text, i, false]


## The four hex digits at `at` as a number, or -1 if they aren't all there yet.
static func _hex(raw: String, at: int) -> int:
	var digits := raw.substr(at, 4)
	if digits.length() < 4 or not digits.is_valid_hex_number():
		return -1
	return digits.hex_to_int()


static func _skip_space(raw: String, i: int) -> int:
	while i < raw.length() and raw[i] in [" ", "\n", "\r", "\t"]:
		i += 1
	return i
