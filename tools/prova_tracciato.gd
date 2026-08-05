extends SceneTree

## GUARDA IL TRACCIATO CON GLI OCCHI, invece di fidarsi che sia giusto.
##
## I test dicono che i pezzi funzionano. Non dicono se il file che ne esce SI LEGGE — se le
## colonne stanno in riga, se il consuntivo indica il colpevole giusto, se una chiave si
## intravede. Sono giudizi che si danno guardando, e questo strumento produce la cosa da
## guardare: un tracciato vero, con HTTP vero, senza spendere un token.
##
## Serve un provider in ascolto. Ce n'e' uno finto accanto — `tools/finto_provider.py`, sola
## libreria standard — che risponde in formato OpenRouter con l'`usage` completo
## (`cached_tokens`, `reasoning_tokens`, `cost`), il campo `provider` di chi ha servito a
## monte, e latenze diverse per agente, perche' nel consuntivo si veda un colpevole.
##
## Uso, in due terminali:
##
##     python3 tools/finto_provider.py
##     DEI_TRACE_LLM=1 tools/godot/godot4 --headless --path . \
##       --script res://tools/prova_tracciato.gd -- http://127.0.0.1:8899
##
## Con DEI_LOG puntato a una cartella usa-e-getta non tocca i tracciati veri.

const CHIAVE_FINTA := "sk-or-v1-0123456789abcdef0123456789abcdef"

func _init() -> void:
	_prova.call_deferred()

func _prova() -> void:
	var dove := "http://127.0.0.1:8899"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("http"):
			dove = a

	var t := Tracciato.new()
	t.dettaglio = OS.get_environment("DEI_TRACE_LLM") != ""
	t.apri("prova del tracciato")
	print("tracciato → %s\n" % t.percorso())

	var c := LLMClient.new()
	root.add_child(c)
	c.configura({"base_url": dove, "model": "deepseek/deepseek-chat-v3.1:free",
		"timeout_sec": 30}, CHIAVE_FINTA)
	c.tracciato = t

	t.connessione({"provider": "OpenRouter (finto)", "modello": c.model,
		"endpoint": dove + c.chat_path, "gateway": "",
		"chiave_env": "OPENROUTER_API_KEY", "chiave_presente": true, "timeout_s": 30})

	# Una GET, come all'avvio: e' meta' del traffico del gioco e finora non era tracciata.
	c.agente = "elenco modelli"
	var elenco: Dictionary = await c.elenca_modelli()
	print("modelli: %s" % str(elenco.get("modelli", [])))

	# UN TURNO, con gli agenti che il gioco chiama davvero e le loro opzioni vere.
	t.apre_turno(12, "Grido al ciclope il mio vero nome: sono io, Odisseo!")
	t.entra("azione del giocatore", "Grido al ciclope il mio vero nome: sono io, Odisseo!")
	t.entra("scena", "ciclope · turno 12 · stat {ciurma: 41, provviste: 3}")
	for chi in ["Interprete", "Poseidone", "Atena", "Poseidone (replica)", "Zeus (arbitro)", "Omero"]:
		c.agente = chi
		var opz := {"temperature": 0.8, "json_mode": true}
		if chi == "Omero":
			opz = {"temperature": 0.9, "max_tokens": 400}
		await c.chat([
			{"role": "system", "content": "Sei %s. " % chi + "…".repeat(40)},
			{"role": "user", "content": "Ulisse ha appena gridato il suo nome."},
		], opz)
	t.esce("narrazione", "612 caratteri")
	t.esce("spunti", "3")
	t.esce("dei svegliati", "poseidone, atena")
	t.esce("delta", "{poseidone: {ira: +2}}")
	t.chiude_turno()
	t.chiudi()

	# LA PROVA CHE CONTA SU UN LOG: la chiave non c'e'. Si verifica sul file, non
	# sull'intenzione — e si urla, perche' un log che perde un segreto non e' un difetto
	# estetico ed e' esattamente la modalita' --tracellm a poterlo fare.
	var testo := FileAccess.get_file_as_string(t.percorso())
	if testo.contains(CHIAVE_FINTA) or testo.contains("0123456789ab"):
		printerr("\n[!!] LA CHIAVE E' FINITA NEL TRACCIATO. Non pubblicare questo file.")
		quit(1)
		return
	print("\n✓ nessuna traccia della chiave nel file (%d righe)" % testo.split("\n").size())
	print("\n%s" % testo)
	quit(0)
