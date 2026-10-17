class_name HttpJson
extends RefCounted
## Minimal async JSON-over-HTTP client built on HTTPClient. Polls once per frame, so it works
## anywhere a SceneTree is running (the game, or headless tests) without needing a Node.


## Returns {"ok": bool, "status": int, "body": Variant, "error": String}.
static func post(url: String, headers: PackedStringArray, body: Dictionary, timeout_sec: float = 120.0) -> Dictionary:
	var parsed := _parse_url(url)
	if parsed.is_empty():
		return _fail("Invalid URL: " + url)
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
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
	all_headers.append("content-type: application/json")
	error = client.request(HTTPClient.METHOD_POST, parsed["path"], all_headers, JSON.stringify(body))
	if error != OK:
		return _fail("Request failed: " + error_string(error))

	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		if Time.get_ticks_msec() > deadline:
			return _fail("Timed out waiting for a response")
		await Frames.next()
	if not client.has_response():
		return _fail("No response (status %d)" % client.get_status())

	var bytes := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var chunk := client.read_response_body_chunk()
		if chunk.is_empty():
			if Time.get_ticks_msec() > deadline:
				return _fail("Timed out reading the response")
			await Frames.next()
		else:
			bytes.append_array(chunk)

	var status := client.get_response_code()
	client.close()
	var text := bytes.get_string_from_utf8()
	var json: Variant = JSON.parse_string(text) if not text.is_empty() else null
	var ok := status >= 200 and status < 300
	return {"ok": ok, "status": status, "body": json, "error": "" if ok else "HTTP %d: %s" % [status, text.left(500)]}


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
