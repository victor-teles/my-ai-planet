class_name ContentGuard
extends RefCounted
## The hard content ceiling, the same at every tone level: every string in an AI reply is checked,
## and a reply that crosses it is rejected like one that breaks its schema. Tragedy is allowed
## (war, plague, death); graphic detail, sexual content, slurs, the real world and an AI talking
## about itself are not. Gentle Mode adds a stricter list that also keeps killing and cruelty out.

## category -> words and phrases (regular expressions), matched whole and case-insensitively.
const CEILING := {
	"graphic violence": [
		"gore", "gory", "gruesome", "disembowel\\w*", "entrails", "eviscerat\\w*", "decapitat\\w*",
		"dismember\\w*", "mutilat\\w*", "flay(ed|ing)?", "impal(ed|ing)", "severed (head|limb|hand|arm|leg)s?",
		"guts (spill|spilled|spilling)", "brains? (splatter\\w*|spill\\w*)", "blood[- ](soaked|spattered|splattered|drenched)",
		"pools? of blood", "torn limb from limb", "ripped (open|apart)", "skulls? (crushed|shattered|split)",
		"burn(ed|t) alive", "flesh (tore|torn|ripped|melted)",
	],
	"sexual content": [
		"sexual(ly)? (act|acts|intercourse|assault\\w*|abuse)", "(having|had|have) sex", "sex with", "sexy",
		"nude", "nudity", "naked bod(y|ies)", "orgasm\\w*", "erotic\\w*", "porn\\w*", "rap(e|ed|es|ing|ist)",
		"molest\\w*", "genital\\w*", "penis", "vagina", "intercourse",
	],
	"slur": [
		"n[i1]gg(er|a|ah)s?", "f[a@]gg?[o0]ts?", "k[i1]kes?", "sp[i1]cs?", "tr[a@]nn(y|ies)",
		"retard(s|ed)?", "wetbacks?", "g[o0]oks?",
	],
	"real world": [
		"coca-cola", "pepsi", "mcdonald'?s", "google", "microsoft", "facebook", "twitter", "instagram",
		"tiktok", "youtube", "starbucks", "walmart", "disney", "netflix", "iphone", "tesla", "amazon\\.com",
		"trump", "biden", "obama", "putin", "hitler", "stalin", "mussolini", "xi jinping", "zelensky\\w*",
		"netanyahu", "elon musk", "bezos", "zuckerberg", "lenin", "mao zedong", "nazis?",
	],
	"prompt injection": [
		"as an ai", "as a language model", "(large )?language model", "(i am|i'm) (an ai|an ai assistant|a chatbot)",
		"i (cannot|can't|won't) (help|assist|comply|write|do that)", "i'm sorry,? but",
		"ignore (all |the )?(previous|prior|above) instructions", "system prompt", "openai", "chatgpt", "anthropic",
		"claude",
	],
}
## Junk that is never part of a story, matched anywhere (not as whole words).
const JUNK: Array[String] = ["```", "<|", "|>", "[inst]", "http://", "https://", "www."]
## Gentle Mode's extra list: tragedy may happen, but killing and cruelty stay off the page.
const GENTLE := {
	"too dark for Gentle Mode": [
		"tortur\\w*", "massacr\\w*", "slaughter\\w*", "butcher(ed|ing|s)?", "corpses?", "bodies",
		"bloody", "bloodshed", "bleed\\w*", "bled", "execut(e|ed|es|ing|ion|ions|ioner)", "hanged",
		"behead\\w*", "murder\\w*", "suicide", "starv(ed|ing) to death", "slain", "slay\\w*", "stab(s|bed|bing)?",
		"strangl\\w*", "drown(ed|ing) (them|him|her)", "kill(ed|ing|s)? (them|him|her|everyone|the children)",
	],
}

static var _patterns: Dictionary = {}


## Problems with every string in a reply (keys aren't checked: they come from our schema).
## Empty means the reply is within the ceiling.
static func check(reply: Variant, gentle: bool = false, path: String = "$") -> PackedStringArray:
	var problems := PackedStringArray()
	if reply is String:
		for problem: String in check_text(reply, gentle):
			problems.append("%s at %s" % [problem, path])
	elif reply is Dictionary:
		for key: Variant in reply:
			problems.append_array(check(reply[key], gentle, "%s.%s" % [path, key]))
	elif reply is Array:
		for i: int in (reply as Array).size():
			problems.append_array(check(reply[i], gentle, "%s[%d]" % [path, i]))
	return problems


## Problems with one piece of text, as "category: 'what matched'".
static func check_text(text: String, gentle: bool = false) -> PackedStringArray:
	var problems := PackedStringArray()
	var lower := text.to_lower()
	for junk: String in JUNK:
		if lower.contains(junk):
			problems.append("prompt injection: '%s'" % junk)
	var lists: Array[Dictionary] = [CEILING]
	if gentle:
		lists.append(GENTLE)
	for list: Dictionary in lists:
		for category: String in list:
			var found := _pattern(list, category).search(text)
			if found:
				problems.append("%s: '%s'" % [category, found.get_string()])
	return problems


static func is_clean(reply: Variant, gentle: bool = false) -> bool:
	return check(reply, gentle).is_empty()


## One compiled, case-insensitive, whole-word pattern per category.
static func _pattern(list: Dictionary, category: String) -> RegEx:
	if not _patterns.has(category):
		var words: Array = list[category]
		_patterns[category] = RegEx.create_from_string("(?i)\\b(?:%s)\\b" % "|".join(words))
	return _patterns[category]
