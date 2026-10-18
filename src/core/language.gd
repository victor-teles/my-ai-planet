class_name Language
extends RefCounted
## A people's own tongue: the sounds its names are made of. Each people who first land on an
## island gets one of its own (generate()), so offline islands already sound different; the AI may
## propose a better one (the "language" asset), which is checked and clamped here before it is used.
## When a tribe splits, the new tribe takes its parents' tongue with a small drift (drift()), so
## neighbours sound like cousins.
##
## A phonology is a Dictionary of strings and whole numbers, saved with the world:
##   "onsets": consonant clusters that start a syllable ("k", "th", "str"),
##   "vowels": vowel clusters at a syllable's heart ("a", "ou"),
##   "codas": consonant clusters that may close a name ("n", "sh", "rk"),
##   "closed": percent of names that end in a coda (0 when there are no codas),
##   "long": percent of given names with a second syllable.
## The empty Dictionary means the old default sound (NameGen's own lists), which saves from before
## languages existed keep.

const CONSONANTS := "bcdfghjklmnpqrstvwxyz"
const VOWEL_LETTERS := "aeiouy"
const MAX_ONSETS := 16
const MAX_VOWELS := 10
const MAX_CODAS := 10
const MIN_ONSETS := 3
const MIN_VOWELS := 2
const MAX_CLOSED := 80
const MAX_LONG := 90
## How often a syllable takes a one-letter sound before any sound of the list (clusters are spice).
const PLAIN_SHARE := 0.6
## Two-letter onsets beyond the regular patterns checked in _is_onset().
const EXTRA_ONSETS: Array[String] = ["ts", "tz", "dz", "tl", "ps", "ks", "gn", "kn"]
## Two-letter codas beyond the regular patterns checked in _is_coda().
const EXTRA_CODAS: Array[String] = ["ks", "ts", "ps", "ft", "pt", "kt", "ll", "nn", "rr", "ss"]
## The default sound, written out as a phonology (what drift() and the AI start from on old saves).
const DEFAULT := {
	"onsets": ["k", "t", "m", "n", "r", "s", "v", "l", "h", "w", "z", "b", "d", "g"],
	"vowels": ["a", "e", "i", "o", "u", "aa", "ai", "ou"],
	"codas": ["n", "r", "sh", "l", "k"],
	"closed": 62,
	"long": 60,
}
## What a new people's tongue is drawn from.
const SINGLE_ONSETS: Array[String] = ["b", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "r", "s", "t", "v", "w", "y", "z"]
const CLUSTER_ONSETS: Array[String] = ["sh", "th", "ch", "kh", "zh", "ts", "kr", "tr", "pr", "br", "dr", "gr", "kl", "pl", "bl", "fl", "st", "sk", "sp", "kw", "tl", "ny", "mb", "nd", "ng", "hw"]
const PLAIN_VOWELS: Array[String] = ["a", "e", "i", "o", "u"]
const RICH_VOWELS: Array[String] = ["aa", "ee", "ii", "oo", "uu", "ai", "au", "ei", "ou", "oi", "ia", "ua", "ae", "y"]
const CODA_POOL: Array[String] = ["n", "r", "l", "s", "k", "m", "t", "sh", "th", "nd", "ng", "rn", "x", "rk", "lt", "ks"]
## How a sound shifts as a dialect drifts away: one step to a near neighbour.
const SHIFTS := {
	"k": "g", "g": "k", "t": "d", "d": "t", "p": "b", "b": "p", "s": "z", "z": "s", "f": "v", "v": "f",
	"r": "l", "l": "r", "m": "n", "n": "m", "sh": "s", "th": "t", "ch": "sh", "kh": "h", "h": "kh", "w": "v",
	"j": "y", "y": "j", "kr": "gr", "tr": "dr", "pr": "br", "st": "sh", "sk": "sh", "zh": "j", "ts": "s",
	"a": "e", "e": "i", "i": "e", "o": "u", "u": "o", "aa": "a", "ee": "i", "ii": "i", "oo": "u", "uu": "u",
	"ai": "ei", "ei": "e", "au": "o", "ou": "u", "oi": "ui", "ia": "ya", "ua": "o", "ae": "e",
	"nd": "n", "ng": "n", "rn": "rd", "rk": "k", "lt": "l", "ks": "x", "x": "ks",
}


# --- Validation ---------------------------------------------------------------------

## A phonology made safe: lowercase ASCII clusters of 1 to 3 letters that can be said aloud,
## duplicates dropped, lists and percents bounded. {} if too little is left to make names from
## (the caller then keeps the tongue it had). Clamping a clamped phonology changes nothing.
static func clamp_spec(spec: Variant) -> Dictionary:
	if not spec is Dictionary:
		return {}
	var data: Dictionary = spec
	var onsets := _clean_list(data.get("onsets", []), MAX_ONSETS, "onsets")
	var vowels := _clean_list(data.get("vowels", []), MAX_VOWELS, "vowels")
	var codas := _clean_list(data.get("codas", []), MAX_CODAS, "codas")
	if onsets.size() < MIN_ONSETS or vowels.size() < MIN_VOWELS:
		return {}
	var closed := clampi(_whole(data.get("closed", 0)), 0, MAX_CLOSED) if not codas.is_empty() else 0
	var long := clampi(_whole(data.get("long", 50)), 0, MAX_LONG)
	return {"onsets": onsets, "vowels": vowels, "codas": codas, "closed": closed, "long": long}


static func is_valid(spec: Variant) -> bool:
	return not clamp_spec(spec).is_empty()


## The phonology names are made from: the default sound for the empty one.
static func resolved(language: Dictionary) -> Dictionary:
	return language if not language.is_empty() else (DEFAULT.duplicate(true) as Dictionary)


## A tribe's tongue ({} is the default sound).
static func of(state: WorldState, t: int) -> Dictionary:
	return state.tribe_language[t] if t >= 0 and t < state.tribe_language.size() else {}


static func of_tribe(state: WorldState, tribe: String) -> Dictionary:
	return of(state, state.tribe_index(tribe))


static func _clean_list(value: Variant, limit: int, group: String) -> Array:
	var clean: Array = []
	if not value is Array:
		return clean
	for item: Variant in value:
		if not item is String:
			continue
		var cluster := (item as String).strip_edges().to_lower()
		if _is_letters(cluster) and fits(group, cluster) and cluster not in clean:
			clean.append(cluster)
		if clean.size() >= limit:
			break
	return clean


## Whether a cluster can be one of a group's sounds ("onsets", "vowels" or "codas").
static func fits(group: String, cluster: String) -> bool:
	match group:
		"onsets":
			return _is_onset(cluster)
		"vowels":
			return _is_vowel(cluster)
		"codas":
			return _is_coda(cluster)
	return false


static func _whole(value: Variant) -> int:
	return roundi(float(value)) if value is float or value is int else 0


## 1 to 3 plain lowercase letters, a to z.
static func _is_letters(cluster: String) -> bool:
	if cluster.length() < 1 or cluster.length() > 3:
		return false
	for c: String in cluster:
		if c < "a" or c > "z":
			return false
	return true


static func _consonants(cluster: String) -> bool:
	for c: String in cluster:
		if not CONSONANTS.contains(c):
			return false
	return true


## A consonant, or a cluster a mouth can start a syllable with: "th", "kr", "st", "mb", "str", "ndr".
static func _is_onset(cluster: String) -> bool:
	if not _consonants(cluster):
		return false
	if cluster.length() == 1:
		return true
	var first := cluster[0]
	var second := cluster[1]
	var pair := cluster.left(2)
	var pair_ok := (second == "h" and first not in ["h", "w", "y"]) \
		or ("rlwy".contains(second) and not "rlwy".contains(first)) \
		or (first == "s" and "kptmnlw".contains(second)) \
		or ("mn".contains(first) and "bdgkt".contains(second)) \
		or pair in EXTRA_ONSETS
	if cluster.length() == 2 or not pair_ok:
		return pair_ok
	# Three letters: a cluster that glides on (str, thr, ndr, skw).
	var third := cluster[2]
	return "rlwy".contains(third) and (first == "s" or second == "h" or "mn".contains(first)) and not "rlwy".contains(second)


## Vowel letters only, never the same one three times: "a", "ou", "aai" yes, "aaa" no.
static func _is_vowel(cluster: String) -> bool:
	for c: String in cluster:
		if not VOWEL_LETTERS.contains(c):
			return false
	return not (cluster.length() == 3 and cluster[0] == cluster[1] and cluster[1] == cluster[2]) and cluster != "yy"


## A consonant a name can end on, or a cluster like "nd", "sh", "rk", "nth", "rds".
static func _is_coda(cluster: String) -> bool:
	if not _consonants(cluster):
		return false
	if cluster.length() == 1:
		return not "jqwy".contains(cluster)
	if cluster.length() == 2:
		return _coda_pair(cluster)
	var head := cluster.left(2)
	var tail := cluster.right(2)
	return ("lmnr".contains(cluster[0]) and tail in ["sh", "th", "ch", "kh"]) or (_coda_pair(head) and "lmnr".contains(cluster[0]) and cluster[2] == "s")


static func _coda_pair(pair: String) -> bool:
	var first := pair[0]
	var second := pair[1]
	return (second == "h" and "sctkgz".contains(first)) \
		or ("lmnr".contains(first) and first != second and not "hjqwy".contains(second)) \
		or (first == "s" and "kpt".contains(second)) \
		or pair in EXTRA_CODAS


# --- Making tongues -----------------------------------------------------------------

## A new people's tongue, from its own seeded stream: a handful of consonants (sometimes a few
## clusters), plain vowels with perhaps some long ones, and the endings its names like.
static func generate(rng: SimRng) -> Dictionary:
	var onsets: Array = _pick(rng, SINGLE_ONSETS, rng.randi_range(6, 11))
	onsets.append_array(_pick(rng, CLUSTER_ONSETS, rng.randi_range(0, 3)))
	var vowels: Array = _pick(rng, PLAIN_VOWELS, rng.randi_range(3, 5))
	vowels.append_array(_pick(rng, RICH_VOWELS, rng.randi_range(0, 3)))
	var codas: Array = _pick(rng, CODA_POOL, rng.randi_range(0, 6))
	var spec := {
		"onsets": onsets, "vowels": vowels, "codas": codas,
		"closed": rng.randi_range(15, 70), "long": rng.randi_range(30, 80),
	}
	return clamp_spec(spec)


## The tongue a breakaway tribe takes with it: its parents' with a sound or two shifted (k to g,
## a to e), maybe an ending gained or lost, and a slightly different rhythm. Close, not the same.
static func drift(language: Dictionary, rng: SimRng) -> Dictionary:
	var spec: Dictionary = resolved(language).duplicate(true)
	for k: int in rng.randi_range(1, 2):
		var group: String = ["onsets", "vowels", "codas"][rng.pick_index(3)]
		var sounds: Array = spec[group]
		if sounds.is_empty():
			continue
		var i := rng.pick_index(sounds.size())
		var shifted := String(SHIFTS.get(sounds[i], ""))
		if shifted.is_empty() or shifted in sounds:
			if sounds.size() > (MIN_ONSETS if group == "onsets" else MIN_VOWELS if group == "vowels" else 0) + 1:
				sounds.remove_at(i) # two sounds merge into one
		else:
			sounds[i] = shifted
	if rng.chance(0.3):
		var gained := CODA_POOL[rng.pick_index(CODA_POOL.size())]
		if gained not in spec["codas"]:
			(spec["codas"] as Array).append(gained)
	spec["closed"] = int(spec["closed"]) + rng.randi_range(-10, 10)
	spec["long"] = int(spec["long"]) + rng.randi_range(-10, 10)
	var clean := clamp_spec(spec)
	return clean if not clean.is_empty() else resolved(language)


## count different entries of pool, in the order the stream picks them.
static func _pick(rng: SimRng, pool: Array[String], count: int) -> Array:
	var left: Array = pool.duplicate()
	var picked: Array = []
	for k: int in mini(count, left.size()):
		picked.append(left.pop_at(rng.pick_index(left.size())))
	return picked


# --- Names --------------------------------------------------------------------------

## A given name: one or two syllables, sometimes closed by an ending ("Teshu", "Kael", "Mirr").
static func person_name(rng: SimRng, language: Dictionary) -> String:
	var spec := resolved(language)
	var name := _syllable(rng, spec)
	if rng.chance(int(spec["long"]) / 100.0):
		name += _syllable(rng, spec)
	if rng.chance(int(spec["closed"]) / 100.0):
		name += _coda(rng, spec)
	return name.capitalize()


## A family name, passed from parent to child: two syllables and, if the tongue has them, an ending.
static func family_name(rng: SimRng, language: Dictionary) -> String:
	var spec := resolved(language)
	var name := _syllable(rng, spec) + _syllable(rng, spec)
	name += _coda(rng, spec) if not (spec["codas"] as Array).is_empty() else _syllable(rng, spec)
	return name.capitalize()


## A tribe's (or a place's) name: two or three syllables, maybe an ending.
static func tribe_name(rng: SimRng, language: Dictionary) -> String:
	var spec := resolved(language)
	var name := _syllable(rng, spec) + _syllable(rng, spec)
	if rng.chance(int(spec["long"]) / 200.0):
		name += _syllable(rng, spec)
	if rng.chance(int(spec["closed"]) / 100.0):
		name += _coda(rng, spec)
	return name.capitalize()


## A word of the tongue, for the names of laws and places ("Kolu", "Tashen").
static func word(rng: SimRng, language: Dictionary) -> String:
	var spec := resolved(language)
	var name := _syllable(rng, spec)
	if rng.chance(0.7):
		name += _syllable(rng, spec)
	if rng.chance(int(spec["closed"]) / 100.0):
		name += _coda(rng, spec)
	return name.capitalize()


## count different words of the tongue, the same for the same seed.
static func words(language: Dictionary, seed_value: int, count: int) -> Array[String]:
	var rng := SimRng.new(seed_value)
	var found: Array[String] = []
	for attempt: int in count * 4:
		var next := word(rng, language)
		if next not in found:
			found.append(next)
		if found.size() >= count:
			break
	return found


static func _syllable(rng: SimRng, spec: Dictionary) -> String:
	return _sound(rng, spec["onsets"]) + _sound(rng, spec["vowels"])


## One sound of a list, the plain one-letter sounds more often than clusters, so names stay easy
## to say: "Kotu" more often than "Strauhwai".
static func _sound(rng: SimRng, sounds: Array) -> String:
	if rng.chance(PLAIN_SHARE):
		var plain: Array = sounds.filter(func(sound: String) -> bool: return sound.length() == 1)
		if not plain.is_empty():
			return String(plain[rng.pick_index(plain.size())])
	return String(sounds[rng.pick_index(sounds.size())])


static func _coda(rng: SimRng, spec: Dictionary) -> String:
	var codas: Array = spec["codas"]
	return String(codas[rng.pick_index(codas.size())]) if not codas.is_empty() else ""
