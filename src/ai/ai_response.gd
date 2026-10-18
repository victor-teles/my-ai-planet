class_name AIResponse
extends RefCounted

var ok: bool = false
var data: Dictionary = {}
var error: String = ""
var provider_id: String = ""
var input_tokens: int = 0
var output_tokens: int = 0
var cost_usd: float = 0.0 ## 0 when the provider doesn't report it
var latency_ms: int = 0 ## wall time of the call, set by the Oracle
var cached: bool = false ## true when the Oracle answered from its cache: no call, no cost


static func success(provider: String, reply: Dictionary) -> AIResponse:
	var response := AIResponse.new()
	response.ok = true
	response.provider_id = provider
	response.data = reply
	return response


static func failure(provider: String, message: String) -> AIResponse:
	var response := AIResponse.new()
	response.provider_id = provider
	response.error = message
	return response
