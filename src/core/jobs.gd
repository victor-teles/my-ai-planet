class_name Jobs
extends RefCounted
## The work people do. A job needs a tech (and sometimes a building) before anyone can take it,
## so new jobs appear as the tribe learns. Each job trains one skill; skill and the genes that
## suit the work decide how much a worker gets done.

const SKILLS: Array[String] = ["gathering", "hunting", "fishing", "farming", "labor", "building", "crafting", "healing", "lore", "trade", "arms"]
## job -> {"name", "plural", "tech", "skill", "gene" (the gene that helps), "makes" (what it adds
##   to the tribe each day per unit of work), "rate", "danger" (monthly accident chance),
##   "building" (needs one of these finished)}
const DEFINITIONS := {
	"forager": {"name": "forager", "plural": "foragers", "tech": "foraging", "skill": "gathering", "gene": "vitality", "makes": "food", "rate": 1.45, "danger": 0.0002},
	"hunter": {"name": "hunter", "plural": "hunters", "tech": "hunting", "skill": "hunting", "gene": "strength", "makes": "food", "rate": 1.75, "danger": 0.0008},
	"fisher": {"name": "fisher", "plural": "fishers", "tech": "fishing", "skill": "fishing", "gene": "vitality", "makes": "food", "rate": 1.7, "danger": 0.0004},
	"farmer": {"name": "farmer", "plural": "farmers", "tech": "agriculture", "skill": "farming", "gene": "strength", "makes": "food", "rate": 2.6, "danger": 0.0001, "building": "field"},
	"woodcutter": {"name": "woodcutter", "plural": "woodcutters", "tech": "shelter", "skill": "labor", "gene": "strength", "makes": "wood", "rate": 1.3, "danger": 0.0007},
	"quarrier": {"name": "quarrier", "plural": "quarriers", "tech": "stone_tools", "skill": "labor", "gene": "strength", "makes": "stone", "rate": 0.9, "danger": 0.0008},
	"builder": {"name": "builder", "plural": "builders", "tech": "shelter", "skill": "building", "gene": "strength", "makes": "building", "rate": 1.0, "danger": 0.0005},
	"toolmaker": {"name": "toolmaker", "plural": "toolmakers", "tech": "stone_tools", "skill": "crafting", "gene": "intellect", "makes": "tools", "rate": 1.0, "danger": 0.0001},
	"healer": {"name": "healer", "plural": "healers", "tech": "herbal_lore", "skill": "healing", "gene": "intellect", "makes": "care", "rate": 1.0, "danger": 0.0001},
	"potter": {"name": "potter", "plural": "potters", "tech": "pottery", "skill": "crafting", "gene": "intellect", "makes": "pots", "rate": 1.0, "danger": 0.0001},
	"weaver": {"name": "weaver", "plural": "weavers", "tech": "weaving", "skill": "crafting", "gene": "intellect", "makes": "cloth", "rate": 1.0, "danger": 0.0001},
	"shaman": {"name": "shaman", "plural": "shamans", "tech": "rites", "skill": "lore", "gene": "intellect", "makes": "faith", "rate": 1.0, "danger": 0.0001},
	# Later ages
	"miner": {"name": "miner", "plural": "miners", "tech": "copper_working", "skill": "labor", "gene": "strength", "makes": "metal", "rate": 0.6, "danger": 0.0012, "building": "mine"},
	"smith": {"name": "smith", "plural": "smiths", "tech": "copper_working", "skill": "crafting", "gene": "strength", "makes": "tools", "rate": 1.0, "danger": 0.0003, "building": "smithy"},
	"scholar": {"name": "scholar", "plural": "scholars", "tech": "writing", "skill": "lore", "gene": "intellect", "makes": "research", "rate": 1.0, "danger": 0.0001, "building": "school"},
	"merchant": {"name": "merchant", "plural": "merchants", "tech": "coinage", "skill": "trade", "gene": "sociability", "makes": "wealth", "rate": 1.0, "danger": 0.0002, "building": "market"},
	"guard": {"name": "guard", "plural": "guards", "tech": "bronze", "skill": "arms", "gene": "strength", "makes": "order", "rate": 1.0, "danger": 0.0006},
	"official": {"name": "official", "plural": "officials", "tech": "writing", "skill": "lore", "gene": "intellect", "makes": "order", "rate": 1.0, "danger": 0.0001},
	"factory_worker": {"name": "factory worker", "plural": "factory workers", "tech": "steam_power", "skill": "crafting", "gene": "strength", "makes": "goods", "rate": 1.0, "danger": 0.0010, "building": "factory"},
}
const ORDER: Array[String] = [
	"forager", "hunter", "fisher", "farmer", "woodcutter", "quarrier", "builder",
	"toolmaker", "healer", "potter", "weaver", "shaman",
	"miner", "smith", "scholar", "merchant", "guard", "official", "factory_worker",
]
const FOOD_JOBS: Array[String] = ["farmer", "fisher", "hunter", "forager"]
## Not jobs, but what people who don't work are doing: shown in place of a job.
const NONE := ""


static func name_of(job: String) -> String:
	return String(DEFINITIONS[job]["name"]) if DEFINITIONS.has(job) else "no work"


static func skill_index(job: String) -> int:
	return SKILLS.find(String(DEFINITIONS[job]["skill"])) if DEFINITIONS.has(job) else -1


## True if the tribe knows how to do this job (buildings are checked by the work system).
static func is_known(job: String, known: PackedStringArray) -> bool:
	return String(DEFINITIONS[job]["tech"]) in known
