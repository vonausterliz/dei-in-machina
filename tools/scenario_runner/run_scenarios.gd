extends SceneTree

## Scenario runner per la qualita' LLM (CLAUDE.md, mandato punto 6). Parte NON
## deterministica: colpisce il modello vero e stampa, per ogni scenario-fixture,
## scenario -> prompt -> output -> verdetto, cosi' tu (o l'umano) potete giudicarlo
## contro una rubrica. La qualita' non si auto-promuove: la si rende osservabile.
##
## Uso:
##   tools/godot/godot4 --headless --path . --script res://tools/scenario_runner/run_scenarios.gd
##   ... -- <model> <max_scenari>     (override opzionali; es. "-- llama3.2-vision:latest 3")
##
## Sempre contro l'LLM reale, ignorando il flag mock in config (usa solo base_url/model/chiave).

const CONFIG_PATH := "res://config/llm_config.json"
const SCENARI_PATH := "res://tools/scenario_runner/scenari_interprete.json"
const SEED := 4815162342

func _init() -> void:
	_avvia.call_deferred()

func _avvia() -> void:
	var config := _carica_json(CONFIG_PATH)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		config["model"] = args[0]
	var max_scenari: int = int(args[1]) if args.size() > 1 else 0

	var client := LLMClient.new()
	root.add_child(client)
	client.configura(config, _leggi_chiave(config))

	print("=== Scenario runner — Interprete ===")
	print("Provider: %s | modello: %s | seed: %d\n" % [client.base_url, client.model, SEED])

	if not await client.disponibile():
		printerr("Provider non raggiungibile a %s. Ollama e' attivo? (`ollama serve`)" % client.base_url)
		quit(1)
		return

	var pantheon := Pantheon.carica("res://data/pantheon.json")
	var interprete := Interprete.new(pantheon.tutti_gli_id())

	var dati := _carica_json(SCENARI_PATH)
	var scenari: Array = dati.get("scenari", [])
	if max_scenari > 0:
		scenari = scenari.slice(0, max_scenari)

	var validi := 0
	var rubrica_ok := 0
	for scenario in scenari:
		var esito := await _esegui_scenario(interprete, client, scenario)
		if esito["valido"]:
			validi += 1
		if esito["rubrica_ok"]:
			rubrica_ok += 1

	print("\n=== Riepilogo ===")
	print("Scenari:            %d" % scenari.size())
	print("Envelope validi:    %d/%d" % [validi, scenari.size()])
	print("Rubrica soddisfatta: %d/%d  (plausibilita attesa + tag attesi presenti)" % [rubrica_ok, scenari.size()])
	print("\nNota: la rubrica e' una guida per l'occhio umano, non un test automatico.")
	print("Allo stadio 1 (Ollama) si collauda l'impianto, non si giudica la scrittura.")
	quit(0)

func _esegui_scenario(interprete: Interprete, client: LLMClient, scenario: Dictionary) -> Dictionary:
	var nome: String = scenario.get("nome", "?")
	var input: String = scenario.get("input", "")
	print("────────────────────────────────────────────────────────")
	print("[%s]" % nome)
	print("Input:  %s" % input)

	var t := await interprete.interpreta_tracciato(input, client.chat, SEED)
	var env: Dictionary = t["envelope"]

	# Output grezzo del modello (primo tentativo), per vedere cosa ha davvero prodotto.
	if t["tentativi"].size() > 0:
		var grezzo: String = t["tentativi"][0]["content"]
		if grezzo.length() > 400:
			grezzo = grezzo.substr(0, 400) + "…"
		print("Grezzo: %s" % grezzo.replace("\n", " "))

	print("Envelope: plausibilita=%s tipo=%s tag=%s dio_invocato=%s tono=%s intensita=%s" % [
		env.get("plausibilita"), env.get("tipo"), env.get("tag"),
		str(env.get("dio_invocato")), env.get("tono"), env.get("intensita"),
	])
	print("Sintesi: %s" % env.get("sintesi", ""))

	var stato := "VALIDO" if t["valido"] else "FALLBACK (parse/validazione fallita)"
	if t["tentativi"].size() > 1:
		stato += " dopo %d tentativi" % t["tentativi"].size()
	print("Stato:  %s" % stato)

	# Rubrica (guida, non assert)
	var plaus_ok: bool = env.get("plausibilita") == scenario.get("plausibilita_attesa")
	var tag_attesi: Array = scenario.get("tag_attesi", [])
	var tag_env: Array = env.get("tag", [])
	var presenti := 0
	for tag in tag_attesi:
		if tag_env.has(tag):
			presenti += 1
	var tag_ok: bool = presenti == tag_attesi.size()
	print("Rubrica: plausibilita attesa=%s [%s] | tag attesi=%s presenti=%d/%d [%s]" % [
		scenario.get("plausibilita_attesa"), "OK" if plaus_ok else "NO",
		tag_attesi, presenti, tag_attesi.size(), "OK" if tag_ok else "PARZIALE",
	])

	return {"valido": t["valido"], "rubrica_ok": plaus_ok and tag_ok}

func _carica_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		printerr("File mancante: %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _leggi_chiave(cfg: Dictionary) -> String:
	var nome_env: String = cfg.get("api_key_env", "")
	if nome_env == "" or not OS.has_environment(nome_env):
		return ""
	return OS.get_environment(nome_env)
