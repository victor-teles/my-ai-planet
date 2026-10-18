class_name HttpJson
extends RefCounted
## Minimal async JSON-over-HTTP client built on HTTPClient. Polls once per frame, so it works
## anywhere a SceneTree is running (the game, or headless tests) without needing a Node.


## Returns {"ok": bool, "status": int, "body": Variant, "error": String}.
static func post(url: String, headers: PackedStringArray, body: Dictionary, timeout_sec: float = 120.0) -> Dictionary:
	return await _fetch(HTTPClient.METHOD_POST, url, headers, JSON.stringify(body), timeout_sec)


## GET a JSON document, e.g. a local server's model list. Same result shape as post().
static func get_json(url: String, headers: PackedStringArray = PackedStringArray(), timeout_sec: float = 15.0) -> Dictionary:
	return await _fetch(HTTPClient.METHOD_GET, url, headers, "", timeout_sec)


## POSTs a request whose reply is a server-sent event stream, calling on_data(data: String)
## with each event's data as it arrives. Same result shape as post(); "body" is the parsed
## error reply when the server refuses with an HTTP error, and null otherwise.
static func post_stream(url: String, headers: PackedStringArray, body: Dictionary, on_data: Callable, timeout_sec: float = 120.0) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	var opened: Dictionary = await _open(HTTPClient.METHOD_POST, url, headers, JSON.stringify(body), deadline)
	if not opened["ok"]:
		return opened
	var client: HTTPClient = opened["client"]
	var status := client.get_response_code()
	if status < 200 or status >= 300:
		return await _finish(client, deadline)
	var parser := SseParser.new()
	var read: Dictionary = await _read_body(client, deadline, func(chunk: PackedByteArray) -> void:
		for data: String in parser.feed(chunk):
			on_data.call(data)
	)
	for data: String in parser.finish():
		on_data.call(data)
	client.close()
	if not read["error"].is_empty():
		return _fail(read["error"])
	return {"ok": true, "status": status, "body": null, "error": ""}


static func _fetch(method: HTTPClient.Method, url: String, headers: PackedStringArray, body_text: String, timeout_sec: float) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	var opened: Dictionary = await _open(method, url, headers, body_text, deadline)
	if not opened["ok"]:
		return opened
	return await _finish(opened["client"], deadline)


## Reads the whole body and parses it as JSON.
static func _finish(client: HTTPClient, deadline: int) -> Dictionary:
	var read: Dictionary = await _read_body(client, deadline, Callable())
	var status := client.get_response_code()
	client.close()
	if not read["error"].is_empty():
		return _fail(read["error"])
	var text := (read["bytes"] as PackedByteArray).get_string_from_utf8()
	var json: Variant = JSON.parse_string(text) if not text.is_empty() else null
	var ok := status >= 200 and status < 300
	return {"ok": ok, "status": status, "body": json, "error": "" if ok else "HTTP %d: %s" % [status, text.left(500)]}


## Connects, sends the request and waits for the response headers.
## Returns {"ok": true, "client": HTTPClient} or a failure.
static func _open(method: HTTPClient.Method, url: String, headers: PackedStringArray, body_text: String, deadline: int) -> Dictionary:
	var parsed := _parse_url(url)
	if parsed.is_empty():
		return _fail("Invalid URL: " + url)
	var client := HTTPClient.new()
	var tls: TLSOptions = TLSOptions.client() if parsed["https"] else null
	var error := client.connect_to_host(parsed["host"], parsed["port"], tls)
	if error != OK:
		return _fail("Could not connect to %s (%s)" % [parsed["host"], error_string(error)])

	while client.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
		client.poll()
		if Time.get_ticks_msec() > deadline:
			return _fail("Timed out connecting to " + parsed["host"])
		await Frames.next()
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return _fail("Could not connect to %s (status %d)" % [parsed["host"], client.get_status()])

	var all_headers := headers.duplicate()
	if method == HTTPClient.METHOD_POST:
		all_headers.append("content-type: application/json")
	error = client.request(method, parsed["path"], all_headers, body_text)
	if error != OK:
		return _fail("Request failed: " + error_string(error))

	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		if Time.get_ticks_msec() > deadline:
			return _fail("Timed out waiting for a response")
		await Frames.next()
	if not client.has_response():
		return _fail("No response (status %d)" % client.get_status())
	return {"ok": true, "client": client}


## Reads the body to the end, handing each chunk to on_chunk (if valid) as it arrives.
## Returns {"bytes": PackedByteArray, "error": String}.
static func _read_body(client: HTTPClient, deadline: int, on_chunk: Callable) -> Dictionary:
	var bytes := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var chunk := client.read_response_body_chunk()
		if chunk.is_empty():
			if Time.get_ticks_msec() > deadline:
				return {"bytes": bytes, "error": "Timed out reading the response"}
			await Frames.next()
		else:
			bytes.append_array(chunk)
			if on_chunk.is_valid():
				on_chunk.call(chunk)
	return {"bytes": bytes, "error": ""}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "status": 0, "body": null, "error": message}


static func _parse_url(url: String) -> Dictionary:
	var https := url.begins_with("https://")
	if not https and not url.begins_with("http://"):
		return {}
	var rest := url.substr(8 if https else 7)
	var slash := rest.find("/")
	var host_port := rest if slash == -1 else rest.left(slash)
	var path := "/" if slash == -1 else rest.substr(slash)
	var port := 443 if https else 80
	var colon := host_port.rfind(":")
	if colon != -1:
		port = host_port.substr(colon + 1).to_int()
		host_port = host_port.left(colon)
	return {"https": https, "host": host_port, "port": port, "path": path}
