class_name CiconiNarrative
extends RefCounted

## Pure post-commit projections for the Ciconi slice.
##
## This class deliberately accepts plain Dictionaries because the world contracts are
## JSON-portable.  It never calls a model and never returns a state patch: prose is a
## consumer of a committed world, never a producer of facts for it.

const BRIEF_SCHEMA := "narrative_brief/1"
const VIEW_SCHEMA := "audience_view/1"
const MEMORY_SCHEMA := "factual_memory/1"

const _DEFAULT_FORBIDDEN_CLASSES := [
	"ATTACK_STARTED",
	"CITY_SACKED",
	"CHARACTER_KILLED",
	"LOCATION_LEFT",
]


static func brief(world_state: Dictionary, outcome: Dictionary = {},
		event_batch: Variant = [], attempt: Dictionary = {}) -> Dictionary:
	var committed_events := _committed_events(world_state, event_batch)
	var required_claims: Array = []
	var observed_classes := {}
	for raw_event in committed_events:
		if not (raw_event is Dictionary):
			continue
		var event: Dictionary = raw_event
		var event_class := _event_class(event)
		if not event_class.is_empty():
			observed_classes[event_class] = true
		if String(event.get("type", "")) == "CHARACTER_HARMED":
			observed_classes["ATTACK_STARTED"] = true
		for claim in _claims_for_event(event):
			required_claims.append(claim)

	var forbidden: Array = []
	for claim_class in _DEFAULT_FORBIDDEN_CLASSES:
		if not observed_classes.has(claim_class):
			forbidden.append(claim_class)
	var supplied_forbidden: Variant = outcome.get("forbidden_claim_classes", [])
	if supplied_forbidden is Array:
		for claim_class in supplied_forbidden:
			if not forbidden.has(String(claim_class)):
				forbidden.append(String(claim_class))

	var safe_outcome := _copy_dictionary(outcome)
	safe_outcome.erase("state")
	return {
		"schema": BRIEF_SCHEMA,
		"world_version": int(world_state.get("world_version", _max_world_version(committed_events))),
		"turn": int(world_state.get("turn", 0)),
		"player_attempt": _copy_dictionary(attempt),
		"outcome": safe_outcome,
		"committed_events": committed_events.duplicate(true),
		"relevant_world_state": _relevant_world_state(world_state),
		"required_claims": required_claims,
		"forbidden_claim_classes": forbidden,
	}


## Narrows the shared committed brief to one knowledge and visibility projection before an LLM sees it.
static func brief_for_audience(narrative_brief: Dictionary, view: Dictionary) -> Dictionary:
	var out := narrative_brief.duplicate(true)
	out["audience"] = String(view.get("audience", "player"))
	out["committed_events"] = view.get("events", []).duplicate(true)
	out["required_claims"] = view.get("required_claims", []).duplicate(true)
	var relevant: Dictionary = out.get("relevant_world_state", {}).duplicate(true)
	relevant["agreements"] = view.get("agreements", []).duplicate(true)
	relevant["relationships"] = view.get("relationships", []).duplicate(true)
	relevant["knowledge"] = view.get("knowledge", []).duplicate(true)
	relevant["beliefs"] = view.get("beliefs", []).duplicate(true)
	out["relevant_world_state"] = relevant
	return out


static func audience_view(narrative_brief: Dictionary, world_state: Dictionary,
		audience: Variant) -> Dictionary:
	var audience_id := _audience_id(audience)
	var tokens := _audience_tokens(audience, audience_id)
	var visible_events: Array = []
	for raw_event in narrative_brief.get("committed_events", []):
		if raw_event is Dictionary and _is_visible_to(raw_event, tokens):
			visible_events.append((raw_event as Dictionary).duplicate(true))

	var visible_ids := {}
	for event in visible_events:
		visible_ids[String(event.get("event_id", ""))] = true
	var required_claims: Array = []
	for raw_claim in narrative_brief.get("required_claims", []):
		if raw_claim is Dictionary and visible_ids.has(String(raw_claim.get("source_event_id", ""))):
			required_claims.append((raw_claim as Dictionary).duplicate(true))

	return {
		"schema": VIEW_SCHEMA,
		"audience": audience_id,
		"world_version": int(narrative_brief.get("world_version", world_state.get("world_version", 0))),
		"turn": int(narrative_brief.get("turn", world_state.get("turn", 0))),
		"events": visible_events,
		"required_claims": required_claims,
		"knowledge": _records_for_audience(world_state.get("knowledge", []), tokens, visible_ids),
		"beliefs": _records_for_audience(world_state.get("beliefs", []), tokens, visible_ids),
		"agreements": _agreements_for_audience(world_state.get("agreements", []), tokens),
		"relationships": _relationships_for_audience(world_state.get("relationships", []), tokens),
	}


static func factual_memory(world_state: Dictionary, event_batch: Variant = [], audience: Variant = null) -> Dictionary:
	var events := _committed_events(world_state, event_batch)
	if audience != null:
		var tokens := _audience_tokens(audience, _audience_id(audience))
		var filtered: Array = []
		for raw_event in events:
			if raw_event is Dictionary and _is_visible_to(raw_event, tokens):
				filtered.append(raw_event)
		events = filtered
	var entries: Array = []
	for raw_event in events:
		if raw_event is Dictionary:
			entries.append(_render_event(raw_event))
	return {
		"schema": MEMORY_SCHEMA,
		"world_version": int(world_state.get("world_version", _max_world_version(events))),
		"entries": entries,
	}


static func factual_memory_text(world_state: Dictionary, event_batch: Variant = [], audience: Variant = null) -> String:
	return "\n".join(PackedStringArray(factual_memory(world_state, event_batch, audience)["entries"]))


## `candidate` is a bounded presentation contract: {text, claims:[...]}.  Text is
## screened only for explicit forbidden classes; required facts are verified against
## declared claims.  No prose is ever promoted into `world_state`.
static func validate(candidate: Variant, narrative_brief: Dictionary) -> Dictionary:
	var violations: Array = []
	var candidate_claims := _candidate_claims(candidate)
	var forbidden: Array = narrative_brief.get("forbidden_claim_classes", [])
	for raw_claim in candidate_claims:
		if not (raw_claim is Dictionary):
			continue
		var claim: Dictionary = raw_claim
		var claim_class := String(claim.get("class", claim.get("type", "")))
		if forbidden.has(claim_class):
			violations.append({"code": "forbidden_claim", "claim_class": claim_class})

	for raw_required in narrative_brief.get("required_claims", []):
		if not (raw_required is Dictionary):
			continue
		var found := false
		for raw_actual in candidate_claims:
			if raw_actual is Dictionary and _claim_matches(raw_required, raw_actual):
				found = true
				break
		if not found:
			violations.append({"code": "required_claim_missing", "claim": raw_required.duplicate(true)})

	var text := _candidate_text(candidate).to_lower()
	for claim_class in forbidden:
		if _text_asserts_class(text, String(claim_class)):
			violations.append({"code": "forbidden_text", "claim_class": claim_class})
	return {"ok": violations.is_empty(), "violations": violations}


## The caller supplies at most one retry; this keeps the runtime policy bounded and
## makes the final fallback independent from model output.
static func choose(candidate: Variant, retry: Variant, narrative_brief: Dictionary) -> Dictionary:
	var first := validate(candidate, narrative_brief)
	if bool(first["ok"]):
		return {"source": "candidate", "text": _candidate_text(candidate), "validation": first}
	var second := validate(retry, narrative_brief)
	if bool(second["ok"]):
		return {"source": "retry", "text": _candidate_text(retry), "validation": second}
	var safe := fallback(narrative_brief)
	return {"source": "fallback", "text": safe["text"], "validation": validate(safe, narrative_brief)}


static func fallback(narrative_brief: Dictionary) -> Dictionary:
	var claims: Array = []
	for raw_claim in narrative_brief.get("required_claims", []):
		if raw_claim is Dictionary:
			claims.append((raw_claim as Dictionary).duplicate(true))
	var events: Array = narrative_brief.get("committed_events", [])
	var lines: Array[String] = []
	for raw_event in events:
		if raw_event is Dictionary:
			lines.append(_render_event(raw_event))
	var text := "Nessun nuovo fatto committed."
	if not lines.is_empty():
		text = " ".join(PackedStringArray(lines))
	return {"text": text, "claims": claims, "deterministic": true}


static func _committed_events(world_state: Dictionary, event_batch: Variant) -> Array:
	var source: Variant = event_batch
	if source is Array and (source as Array).is_empty():
		source = world_state.get("events", [])
	elif source is Dictionary and (source as Dictionary).is_empty():
		source = world_state.get("events", [])
	if source is Dictionary:
		source = (source as Dictionary).get("events", [])
	var out: Array = []
	if source is Array:
		for raw_event in source:
			if raw_event is Dictionary:
				out.append((raw_event as Dictionary).duplicate(true))
	return out


static func _claims_for_event(event: Dictionary) -> Array:
	var payload: Dictionary = event.get("payload", {}) if event.get("payload", {}) is Dictionary else {}
	var actor := String(event.get("actor_id", event.get("actor", "")))
	var target := String(event.get("target_id", event.get("target", "")))
	var event_type := String(event.get("type", ""))
	var source_event_id := String(event.get("event_id", ""))
	var claims: Array = []
	match event_type:
		"ENTITY_MOVED":
			claims.append(_fact(actor, "at", String(payload.get("to_location_id", payload.get("destination_id", payload.get("location_id", target)))), "LOCATION_LEFT", source_event_id))
		"ITEM_TRANSFERRED":
			claims.append(_fact(actor, "transferred", target, "ITEM_TRANSFERRED", source_event_id, {
				"resource": payload.get("resource", payload.get("resource_id", "")), "quantity": payload.get("quantity", 0)}))
		"ENTITY_TRANSFERRED":
			claims.append(_fact(String(payload.get("entity_id", actor)), "contained_by", String(payload.get("to_id", target)), "ENTITY_TRANSFERRED", source_event_id))
		"RESOURCE_CONSUMED":
			claims.append(_fact(actor, "consumed", String(payload.get("resource", "")), "RESOURCE_CONSUMED", source_event_id, {"quantity": payload.get("quantity", 0)}))
		"CLAIM_UTTERED":
			# An utterance is a fact; its asserted content deliberately is not world truth.
			claims.append(_fact(actor, "uttered_claim_to", target, "CLAIM_UTTERED", source_event_id))
		"BELIEF_CHANGED":
			claims.append(_fact(actor, "belief_changed_about", target, "BELIEF_CHANGED", source_event_id))
		"KNOWLEDGE_LEARNED":
			claims.append(_fact(actor, "learned_about", target, "KNOWLEDGE_LEARNED", source_event_id))
		"RELATIONSHIP_CHANGED":
			claims.append(_fact(actor, String(payload.get("axis", payload.get("relationship", "relationship_changed"))), target,
				"RELATIONSHIP_CHANGED", source_event_id, {"value": payload.get("value", payload.get("delta", 0))}))
		"AGREEMENT_PROPOSED":
			claims.append(_fact(actor, "proposed_agreement_to", target, "AGREEMENT_PROPOSED", source_event_id))
		"AGREEMENT_ACTIVATED":
			var kind := String(payload.get("kind", "AGREEMENT"))
			claims.append(_fact(actor, "allied_with" if kind == "ALLIANCE" else "agreement_active_with", target,
				"AGREEMENT_ACTIVATED", source_event_id, {"kind": kind}))
		"AGREEMENT_BREACHED":
			claims.append(_fact(actor, "agreement_breached_with", target, "AGREEMENT_BREACHED", source_event_id))
		"AGREEMENT_REJECTED":
			claims.append(_fact(target, "rejected_agreement_with", actor, "AGREEMENT_REJECTED", source_event_id))
		"CHARACTER_HARMED":
			claims.append(_fact(actor, "harmed", target, "CHARACTER_HARMED", source_event_id))
		"TURN_WAITED":
			claims.append(_fact(actor, "waited", "", "TURN_WAITED", source_event_id))
		_:
			pass
	return claims


static func _fact(subject: String, predicate: String, object: String, claim_class: String,
		source_event_id: String, extra: Dictionary = {}) -> Dictionary:
	var claim := {"subject": subject, "predicate": predicate, "object": object,
		"class": claim_class, "source_event_id": source_event_id}
	for key in extra:
		claim[key] = extra[key]
	return claim


static func _event_class(event: Dictionary) -> String:
	match String(event.get("type", "")):
		"ENTITY_MOVED": return "LOCATION_LEFT"
		"CHARACTER_HARMED": return "CHARACTER_HARMED"
		"ATTACK_STARTED", "ATTACK_RESOLVED": return "ATTACK_STARTED"
		"CITY_SACKED": return "CITY_SACKED"
		_: return String(event.get("type", ""))


static func _relevant_world_state(world_state: Dictionary) -> Dictionary:
	var out := {}
	for key in ["entities", "resources", "relationships", "agreements"]:
		if world_state.has(key):
			out[key] = world_state[key].duplicate(true) if world_state[key] is Dictionary or world_state[key] is Array else world_state[key]
	return out


static func _audience_id(audience: Variant) -> String:
	if audience is Dictionary:
		return String((audience as Dictionary).get("id", "player"))
	return String(audience) if audience != null else "player"


static func _audience_tokens(audience: Variant, audience_id: String) -> Dictionary:
	var tokens := {audience_id: true}
	match audience_id:
		"player": tokens["odysseus"] = true
		"crew": tokens["crew"] = true
		"olympus": tokens["olympus"] = true
		_: pass
	if audience is Dictionary:
		for token in (audience as Dictionary).get("known_entity_ids", []):
			tokens[String(token)] = true
	return tokens


static func _is_visible_to(event: Dictionary, tokens: Dictionary) -> bool:
	var visibility := String(event.get("visibility", ""))
	if visibility == "public":
		return true
	var observers: Variant = event.get("observers", event.get("visibility", []))
	if observers is String:
		return tokens.has(String(observers))
	if observers is Array:
		for observer in observers:
			if tokens.has(String(observer)):
				return true
	# Actor and target are entitled to their own event if no explicit observer list exists.
	if observers is Array and not observers.is_empty():
		return false
	return tokens.has(String(event.get("actor_id", event.get("actor", "")))) or tokens.has(String(event.get("target_id", event.get("target", ""))))


static func _records_for_audience(records: Variant, tokens: Dictionary, visible_ids: Dictionary) -> Array:
	var out: Array = []
	for record in _as_record_array(records):
		var holder := String(record.get("knower_id", record.get("believer_id", record.get("holder_id", record.get("owner_id", record.get("subject_id", ""))))))
		var source := String(record.get("source_event_id", record.get("source", "")))
		if tokens.has(holder) and (source.is_empty() or visible_ids.has(source)):
			out.append(record.duplicate(true))
	return out


static func _agreements_for_audience(agreements: Variant, tokens: Dictionary) -> Array:
	var out: Array = []
	for agreement in _as_record_array(agreements):
		if _record_mentions_tokens(agreement, tokens):
			out.append(agreement.duplicate(true))
	return out


static func _relationships_for_audience(relationships: Variant, tokens: Dictionary) -> Array:
	var out: Array = []
	# WorldState stores directional relationships as relationships[from_id][to_id].
	if relationships is Dictionary:
		for from_id in (relationships as Dictionary):
			var by_target: Variant = (relationships as Dictionary)[from_id]
			if not (by_target is Dictionary):
				continue
			for to_id in (by_target as Dictionary):
				if tokens.has(String(from_id)) or tokens.has(String(to_id)):
					var values: Variant = (by_target as Dictionary)[to_id]
					out.append({"from_id": String(from_id), "to_id": String(to_id), "values": values.duplicate(true) if values is Dictionary else values})
		return out
	for relationship in _as_record_array(relationships):
		if _record_mentions_tokens(relationship, tokens):
			out.append(relationship.duplicate(true))
	return out


static func _as_record_array(records: Variant) -> Array:
	if records is Array:
		return records
	if records is Dictionary:
		var out: Array = []
		for key in (records as Dictionary):
			var value: Variant = (records as Dictionary)[key]
			if value is Dictionary:
				var copy := (value as Dictionary).duplicate(true)
				if not copy.has("id"):
					copy["id"] = key
				out.append(copy)
			elif value is Array:
				for item in value:
					if item is Dictionary:
						out.append((item as Dictionary).duplicate(true))
		return out
	return []


static func _record_mentions_tokens(record: Dictionary, tokens: Dictionary) -> bool:
	for key in ["actor_id", "target_id", "from_id", "to_id", "subject_id", "object_id", "party_a", "party_b"]:
		if tokens.has(String(record.get(key, ""))):
			return true
	for party in record.get("parties", []):
		if tokens.has(String(party)):
			return true
	return false


static func _candidate_claims(candidate: Variant) -> Array:
	if candidate is Dictionary:
		var raw_claims: Variant = (candidate as Dictionary).get("claims", (candidate as Dictionary).get("factual_claims", []))
		return raw_claims if raw_claims is Array else []
	return []


static func _candidate_text(candidate: Variant) -> String:
	if candidate is Dictionary:
		return String((candidate as Dictionary).get("text", ""))
	return String(candidate)


static func _claim_matches(required: Dictionary, actual: Dictionary) -> bool:
	for key in ["subject", "predicate", "object", "class"]:
		if required.has(key) and String(required[key]) != String(actual.get(key, "")):
			return false
	return true


static func _text_asserts_class(text: String, claim_class: String) -> bool:
	var markers := {
		"ATTACK_STARTED": ["attacco", "attacc", "assalto", "contrattacc"],
		"CITY_SACKED": ["saccheggi", "citta' cadde", "città cadde"],
		"CHARACTER_KILLED": [" uccis", " mori", " morì", " morto", " cadde morto", "ultimo respiro", "esalò", "esalo", "spirò", "spiro", "senza vita", "non respirava"],
		"LOCATION_LEFT": [" salpo", " salpò", " lascio ", " lasciò ", " fugg"],
	}
	for marker in markers.get(claim_class, []):
		if text.contains(String(marker)):
			return true
	return false


static func _render_event(event: Dictionary) -> String:
	var event_id := String(event.get("event_id", "?"))
	var event_type := String(event.get("type", "EVENT"))
	var actor := String(event.get("actor_id", event.get("actor", "?")))
	var target := String(event.get("target_id", event.get("target", "")))
	var suffix := " verso %s" % target if not target.is_empty() else ""
	return "[%s] %s: %s%s." % [event_id, event_type, actor, suffix]


static func _max_world_version(events: Array) -> int:
	var maximum := 0
	for raw_event in events:
		if raw_event is Dictionary:
			maximum = maxi(maximum, int((raw_event as Dictionary).get("world_version", 0)))
	return maximum


static func _copy_dictionary(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}
