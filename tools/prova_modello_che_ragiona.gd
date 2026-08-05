extends SceneTree

## LA PROVA DEL MODELLO CONTRO UN MODELLO CHE RAGIONA — la cosa che si e' rotta.
##
## Storia in tre atti, perche' e' istruttiva.
##
## 1. `chat()` accettava `max_tokens` e lo BUTTAVA. La «prova del modello» lo passava a 1 e
##    otteneva una generazione intera: sbagliato, ma funzionante.
## 2. Il tetto ha cominciato ad arrivare davvero (v2.38). Su un modello a ragionamento
##    obbligatorio — DeepSeek V4 Flash, e nel 2026 sono la norma — l'unico token concesso se
##    ne va nel pensiero: torna `content: null`, `finish_reason: length`. Il gioco leggeva
##    «nessun contenuto» e concludeva «il modello non risponde», rifiutando un modello sano.
## 3. Ora il tetto e' 64 e — soprattutto — la prova NON giudica sul contenuto: giudica sul
##    fatto che il modello abbia prodotto token. E' la domanda che la prova voleva fare.
##
## Qui si verifica il percorso INTERO, con HTTP vero, contro `tools/finto_provider.py`, che
## sa riprodurre quella risposta esatta (`max_tokens <= 4` -> ragiona e tace).
##
##     python3 tools/finto_provider.py
##     tools/godot/godot4 --headless --path . --script res://tools/prova_modello_che_ragiona.gd

const DOVE := "http://127.0.0.1:8899"

## Il tetto della prova del modello. RIPETUTO QUI, e non letto da `LLMManager.TOKEN_PROVA`.
##
## Nominare `LLMManager` sarebbe una dipendenza di COMPILAZIONE: obbliga `llm_manager.gd` a
## compilare quando questo file viene caricato, e in modalita' `--script` gli autoload non
## sono identificatori globali — `PantheonManager` non esiste, la compilazione fallisce, e lo
## strumento gira su un client mai configurato accusando la rete. E' la stessa trappola gia'
## scritta in `tools/foto_gioco.gd`, e ci sono cascato lo stesso: il richiamo di leggere il
## valore «dalla fonte» e' forte, e qui la fonte non e' raggiungibile.
##
## Se cambia di la', va cambiato qui: il disallineamento si vede subito, perche' il test
## pretende che con QUESTO tetto il modello risponda.
const TOKEN_PROVA := 64

func _init() -> void:
	_prova.call_deferred()

func _prova() -> void:
	var c := LLMClient.new()
	root.add_child(c)
	c.configura({"base_url": DOVE, "model": "deepseek/deepseek-v4-flash", "timeout_sec": 30})

	var guai: Array[String] = []

	# PRIMA DI TUTTO: C'E' QUALCUNO IN ASCOLTO?
	#
	# Senza questo controllo, con il finto provider spento lo strumento riportava tre
	# fallimenti circostanziati — «il messaggio non spiega…», «il corpo grezzo non e' stato
	# consegnato…» — che accusavano codice perfettamente sano. E' successo davvero, e ci si
	# perde tempo prima di guardare la riga che diceva «result=2».
	#
	# Una condizione dell'esperimento che non regge non e' un esito dell'esperimento: si
	# distingue «non ho potuto misurare» da «ho misurato e va male», e ci si ferma.
	if not await c.disponibile():
		printerr("[!] nessuno risponde su %s." % DOVE)
		printerr("    Avvia il banco di prova:  python3 tools/finto_provider.py")
		quit(2)
		return

	# --- 1. col tetto stretto il modello ragiona e tace ---
	var r: Dictionary = await c.chat([{"role": "user", "content": "ok"}], {"max_tokens": 1})
	print("tetto 1  → ok=%s\n         errore: %s" % [r["ok"], r["error"]])
	if bool(r["ok"]):
		guai.append("con un token solo il modello NON dovrebbe produrre contenuto: il finto e' rotto")
	if not String(r["error"]).contains("ragion"):
		guai.append("il messaggio non spiega che il modello ha speso i token a ragionare: «%s»" % r["error"])
	# Il corpo grezzo dev'essere consegnato anche quando si fallisce: e' cio' che permette a
	# chi chiama di distinguere «ha risposto senza contenuto» da «non ha risposto».
	if typeof(r.get("grezzo")) != TYPE_DICTIONARY or Dictionary(r["grezzo"]).is_empty():
		guai.append("il corpo grezzo non e' stato consegnato: chi chiama non puo' distinguere i due casi")
	else:
		var uso: Dictionary = r["grezzo"].get("usage", {})
		# int(): il JSON di Godot torna float, e «out=1.0 token» si legge male anche qui.
		print("         token dichiarati: out=%d  ragionamento=%d" % [
			int(uso.get("completion_tokens", 0)),
			int(uso.get("completion_tokens_details", {}).get("reasoning_tokens", 0))])
		if int(uso.get("completion_tokens", 0)) <= 0:
			guai.append("nessun token in uscita dichiarato: la prova non potrebbe assolverlo")

	# --- 2. col tetto della prova vera il modello risponde ---
	var r2: Dictionary = await c.chat([{"role": "user", "content": "ok"}],
		{"max_tokens": TOKEN_PROVA})
	print("tetto %d → ok=%s" % [TOKEN_PROVA, r2["ok"]])
	if not bool(r2["ok"]):
		guai.append("col tetto della prova (%d) il modello dovrebbe rispondere: %s" % [
			TOKEN_PROVA, r2["error"]])

	if guai.is_empty():
		print("\n✓ la prova del modello non boccia piu' un modello che ragiona.")
		quit(0)
		return
	for g in guai:
		printerr("[!] %s" % g)
	quit(1)
