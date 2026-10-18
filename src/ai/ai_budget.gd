class_name AIBudget
extends RefCounted
## Cost guardrails for one session: a spending cap, a call cap, and model-tier routing that gets
## cheaper as the money runs out. Once a cap is hit the Oracle stays offline for the rest of the
## session. Free providers (local models, the offline templates) never count against either cap.

const DEFAULT_CAP_USD := 0.10
const DEFAULT_MAX_CALLS := 200
const DOWNGRADE_AT := 0.75 ## share of a cap used before every task drops one tier

var cap_usd: float = DEFAULT_CAP_USD ## 0 = unlimited
var max_calls: int = DEFAULT_MAX_CALLS ## 0 = unlimited
var spent_usd := 0.0
var paid_calls := 0
## task -> {"usd": float, "calls": int}: what each task has spent, so the AssetDirector can keep
## asset calls to their share.
var by_task := {}
## task -> AIRequest.Tier, overriding the manifest's tier (see AIPrompts) for this session.
var routes := {}


## MYAIPLANET_AI_BUDGET sets the cap in USD (0 = unlimited).
static func from_environment() -> AIBudget:
	var budget := AIBudget.new()
	var cap := OS.get_environment("MYAIPLANET_AI_BUDGET")
	if cap.is_valid_float():
		budget.cap_usd = maxf(cap.to_float(), 0.0)
	return budget


## The tier a task should use now: its route, one tier cheaper once most of the budget is spent.
func route(task: String) -> AIRequest.Tier:
	var tier: AIRequest.Tier = routes.get(task, AIPrompts.tier(task))
	if used_share() >= DOWNGRADE_AT and tier > AIRequest.Tier.SMALL:
		tier = (tier - 1) as AIRequest.Tier
	return tier


## Counts a finished call against the caps (free providers cost nothing).
func charge(response: AIResponse, free: bool, task: String = "") -> void:
	if free:
		return
	paid_calls += 1
	spent_usd += maxf(response.cost_usd, 0.0)
	var spent: Dictionary = by_task.get_or_add(task, {"usd": 0.0, "calls": 0})
	spent["usd"] = float(spent["usd"]) + maxf(response.cost_usd, 0.0)
	spent["calls"] = int(spent["calls"]) + 1


## How much of the tighter cap these tasks have used together, 0 to 1 (and beyond once over).
func share_of(tasks: Array[String]) -> float:
	var usd := 0.0
	var calls := 0
	for task: String in tasks:
		var spent: Dictionary = by_task.get(task, {})
		usd += float(spent.get("usd", 0.0))
		calls += int(spent.get("calls", 0))
	var share := 0.0
	if cap_usd > 0.0:
		share = usd / cap_usd
	if max_calls > 0:
		share = maxf(share, float(calls) / max_calls)
	return share


## How much of the tighter cap is used, 0 to 1 (and beyond once over).
func used_share() -> float:
	var share := 0.0
	if cap_usd > 0.0:
		share = spent_usd / cap_usd
	if max_calls > 0:
		share = maxf(share, float(paid_calls) / max_calls)
	return share


func exhausted() -> bool:
	return used_share() >= 1.0


## Why the budget is spent, or "" if it isn't.
func why_exhausted() -> String:
	if cap_usd > 0.0 and spent_usd >= cap_usd:
		return "spent $%.4f of the $%.2f session budget" % [spent_usd, cap_usd]
	if max_calls > 0 and paid_calls >= max_calls:
		return "made %d of %d paid calls this session" % [paid_calls, max_calls]
	return ""


func report() -> Dictionary:
	return {"spent_usd": spent_usd, "cap_usd": cap_usd, "paid_calls": paid_calls, "max_calls": max_calls, "used_share": used_share()}
