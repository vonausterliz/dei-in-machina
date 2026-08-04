extends SceneTree

## I MODELLI DICHIARATI ESISTONO DAVVERO?
##
## Nasce da un errore preciso. In config/providers/6_openrouter.json il modello predefinito
## era «mistralai/mistral-small-3.2-24b-instruct:free»: dedotto dal fatto che OpenRouter ha
## modelli col suffisso «:free», e mai verificato sul catalogo. Non esiste. Ogni chiamata
## rispondeva 404, e nessun test poteva accorgersene — tutti guardavano la FORMA del nome,
## nessuno la sua esistenza. Un test offline non puo' fare di meglio: il catalogo ce l'ha
## solo il provider.
##
## Questo strumento glielo chiede. Per ogni profilo in config/providers/ scarica l'elenco
## vero e confronta `model` e `modelli_noti`. I provider che vogliono una chiave si saltano
## se la chiave non c'e' — e lo dicono, invece di far finta di aver controllato.
##
## Uso:  tools/godot/godot4 --headless --path . --script res://tools/verifica_modelli/verifica_modelli.gd
##       (esce 1 se qualche nome dichiarato non esiste: si puo' mettere in CI)

const SECONDI_MASSIMI := 120.0

var _t0 := 0.0
var _mancanti := 0
var _saltati: Array = []

func _init() -> void:
	_verifica.call_deferred()

func _process(_d: float) -> bool:
	if _t0 > 0.0 and (Time.get_ticks_msec() / 1000.0) - _t0 > SECONDI_MASSIMI:
		printerr("[!] tempo scaduto")
		quit(2)
	return false

func _verifica() -> void:
	_t0 = Time.get_ticks_msec() / 1000.0
	Impostazioni.applica_chiavi_all_ambiente()
	var llm := root.get_node("LLMManager")

	print("\n=== I modelli dichiarati esistono presso il provider? ===\n")
	for profilo in llm.profili:
		await _un_provider(profilo, llm)

	print("")
	if not _saltati.is_empty():
		print("Non verificati (manca la chiave o il server): %s" % ", ".join(_saltati))
		print("  Le chiavi si mettono in Settings, o nell'ambiente prima di lanciare.")
	if _mancanti > 0:
		printerr("\n[!] %d nomi dichiarati NON esistono presso il loro provider." % _mancanti)
		printerr("    Sono 404 a ogni chiamata, e nessun test offline puo' vederli.")
		quit(1)
		return
	print("\nTutti i nomi dichiarati esistono.")
	quit(0)

func _un_provider(profilo: Dictionary, llm: Node) -> void:
	var nome := String(profilo.get("nome", "?"))
	var cliente := LLMClient.new()
	root.add_child(cliente)
	cliente.configura(profilo, _chiave(profilo))
	var r: Dictionary = await cliente.elenca_modelli()
	cliente.queue_free()

	if not r["ok"]:
		# Distinguere «non ho la chiave» da «il provider e' rotto»: la prima e' una cosa che
		# manca a me, la seconda una notizia.
		var perche := String(r.get("errore", "?"))
		print("· %-14s  non verificato — %s" % [nome, perche])
		_saltati.append(nome)
		return

	var catalogo: Array = r["modelli"]
	var pieno := bool(profilo.get("nome_pieno", false))
	# Il catalogo puo' usare prefissi suoi («models/gemini-…» di Google): si confronta nudo.
	# Passa dal nodo, non dall'identificatore: in modalita' --script gli autoload non
	# esistono ancora quando Godot compila lo script, e nominarne uno lo fa fallire.
	var nudi: Dictionary = {}
	for m in catalogo:
		nudi[llm.nome_nudo(String(m), pieno)] = true

	var dichiarati: Array = [String(profilo.get("model", ""))]
	for m in Array(profilo.get("modelli_noti", [])):
		if not dichiarati.has(String(m)):
			dichiarati.append(String(m))

	var assenti: Array = []
	for m in dichiarati:
		if not nudi.has(m):
			assenti.append(m)

	if assenti.is_empty():
		print("· %-14s  %d nel catalogo · tutti i %d dichiarati esistono" % [
			nome, catalogo.size(), dichiarati.size()])
		return

	# SU UN PROVIDER LOCALE «assente» vuol dire un'altra cosa. Il catalogo di Ollama e' cio'
	# che TU hai installato, non cio' che esiste al mondo: un nome che manca si scarica con
	# «ollama pull», non e' un errore nei dati. L'unico che deve esserci davvero e' il
	# predefinito — senza quello il gioco parte gia' rotto.
	var locale := bool(profilo.get("locale", false))
	var predefinito := String(profilo.get("model", ""))
	print("· %-14s  %d nel catalogo · %d dichiarati non ci sono:" % [
		nome, catalogo.size(), assenti.size()])
	for m in assenti:
		var grave: bool = not locale or m == predefinito
		print("      %s %s%s" % [
			"✗" if grave else "·", m,
			"" if not locale else ("   (scaricalo con «ollama pull %s»)" % m)])
		if m == predefinito:
			print("        ED E' IL PREDEFINITO: il gioco parte gia' rotto.")
		if grave:
			_mancanti += 1
	if locale and _mancanti == 0:
		print("      (un provider locale elenca cio' che hai installato tu: non e' un errore)")
	# Un aiuto concreto: i nomi vicini a quello dichiarato, per capire com'e' cambiato.
	_suggerisci(assenti, nudi.keys())

func _suggerisci(assenti: Array, catalogo: Array) -> void:
	for m in assenti:
		var radice := String(m).get_slice(":", 0)
		var vicini: Array = []
		for c in catalogo:
			if String(c).begins_with(radice) or radice.begins_with(String(c)):
				vicini.append(String(c))
		if not vicini.is_empty():
			vicini.sort()
			print("        forse: %s" % ", ".join(vicini.slice(0, 4)))

func _chiave(profilo: Dictionary) -> String:
	var env := String(profilo.get("api_key_env", ""))
	return OS.get_environment(env) if env != "" and OS.has_environment(env) else ""
