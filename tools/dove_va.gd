extends SceneTree

## DOVE VA DAVVERO UNA CHIAMATA? Ricostruisce lo stato d'avvio del gioco leggendo le TUE
## preferenze, e stampa l'indirizzo, il modello e le intestazioni che partirebbero adesso.
##
## Nasce da una domanda che non si poteva rispondere a occhio: «passa dal gateway anche se
## non l'ho acceso?». Il percorso attraversa tre strati — le preferenze salvate, la scelta
## del profilo, il trasporto — e ognuno puo' mentire in modo plausibile.
##
##   tools/godot/godot4 --headless --path . --script res://tools/dove_va.gd

func _init() -> void:
	_guarda.call_deferred()

func _guarda() -> void:
	var llm: Node = root.get_node("LLMManager")

	print("\n=== LE PREFERENZE SALVATE (user://impostazioni.json) ===")
	for chiave in ["provider_nome", "provider_idx", "usa_gateway", "motore"]:
		var v: Variant = Impostazioni.leggi(chiave, null)
		print("  %-16s %s" % [chiave, "(assente)" if v == null else str(v)])

	print("\n=== I PROFILI CARICATI ===")
	for i in llm.profili.size():
		var p: Dictionary = llm.profili[i]
		print("  [%d] %-14s provider=%-12s model=%s" % [
			i, p.get("nome", "?"), p.get("provider", "?"), p.get("model", "?")])
	print("  trasporto (gateway_cfg): %s" % (
		"assente" if llm.gateway_cfg.is_empty() else String(llm.gateway_cfg.get("base_url", "?"))))

	# La stessa sequenza di Main._ripristina_provider(), che e' cio' che decide all'avvio.
	print("\n=== COSA SUCCEDE ALL'AVVIO ===")
	var nome := String(Impostazioni.leggi("provider_nome", ""))
	var idx: int = llm.indice_profilo(nome)
	print("  provider_nome ricordato: «%s»" % nome)
	print("  indice_profilo(«%s») -> %d %s" % [nome, idx,
		"(non trovato: il profilo NON viene impostato)" if idx < 0 else ""])
	if idx >= 0:
		llm.imposta_profilo(idx)
	llm.usa_gateway = bool(Impostazioni.leggi("usa_gateway", false))
	print("  profilo attivo: [%d] %s" % [llm.profilo_idx, llm.nome_profilo_corrente()])
	print("  usa_gateway:    %s" % llm.usa_gateway)

	print("\n=== LA CHIAMATA CHE PARTIREBBE ADESSO ===")
	var cfg: Dictionary = llm._config_attiva()
	for k in ["base_url", "chat_path", "models_path", "model", "api_key_env", "timeout_sec"]:
		print("  %-14s %s" % [k, cfg.get(k, "(non impostato)")])
	var url := String(cfg.get("base_url", "")).trim_suffix("/") + String(cfg.get("chat_path", ""))
	print("\n  --> %s" % url)
	print("      modello: %s" % cfg.get("model", "?"))
	# NON si cerca «localhost»: Ollama gira in casa e ci vive anche lui, sulla 11434. La
	# prima stesura di questo strumento diceva «passa dal GATEWAY» con Ollama selezionato —
	# uno strumento che risponde a una domanda diversa da quella che gli hai fatto.
	# Il confronto giusto e' con l'indirizzo DICHIARATO del trasporto.
	var indirizzo_gw := String(llm.gateway_cfg.get("base_url", "")).trim_suffix("/")
	var passa := indirizzo_gw != "" and url.begins_with(indirizzo_gw)
	print("\n  VERDETTO: %s" % ("passa dal GATEWAY (%s)" % indirizzo_gw if passa
		else "va DIRETTO al provider"))
	if passa != llm.usa_gateway:
		print("  ⚠ INCOERENZA: usa_gateway=%s ma l'indirizzo dice il contrario." % llm.usa_gateway)

	quit(0)
