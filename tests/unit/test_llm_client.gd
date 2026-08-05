extends GutTest

## IL CLIENT, E LE OPZIONI CHE NON ARRIVAVANO.
##
## `chat()` accetta un dizionario di opzioni e ne usava tre: `temperature`, `seed`,
## `json_mode`. La quarta, `max_tokens`, la buttava — senza errore, senza avviso. La «prova
## del modello» in Impostazioni la passava a 1 (basta un token per sapere se il modello
## genera) e otteneva una risposta intera: spreco a ogni verifica, e su un tier gratuito lo
## spreco e' quota.
##
## Ma il guaio piu' grosso non era li'. **Nessun agente mette un tetto all'uscita**, e con un
## modello che «ragiona» prima di rispondere questo vuol dire decine di secondi e mille token
## pensati che nella battuta non compaiono. Il tetto ora si puo' mettere: prima non si poteva,
## e non c'era modo di scoprirlo se non leggendo il codice riga per riga.
##
## Un'opzione che non arriva al provider e un'opzione che il provider ignora si somigliano
## come due gocce d'acqua e si curano in modi opposti: la prima e' un difetto nostro, la
## seconda un limite loro (e per Anthropic sono limiti reali — il suo layer
## OpenAI-compatibile ignora `response_format` e `seed`). Questi test presidiano la prima.

var _c: LLMClient

func before_each():
	_c = LLMClient.new()
	_c.model = "prova/modello"

func after_each():
	_c.free()

const MSG := [{"role": "user", "content": "ok"}]

func test_il_corpo_porta_sempre_modello_messaggi_e_temperatura():
	var b := _c.corpo_richiesta(MSG, {})
	assert_eq(b["model"], "prova/modello")
	assert_eq(b["messages"], MSG)
	assert_eq(b["temperature"], 0.7, "manca il valore predefinito di temperatura")
	assert_false(b["stream"], "il gioco non legge risposte a flusso: stream dev'essere falso")

## IL TEST CHE MANCAVA. Con il difetto dentro, `max_tokens` non compariva nel corpo.
func test_il_tetto_all_uscita_arriva_al_provider():
	var b := _c.corpo_richiesta(MSG, {"max_tokens": 1})
	assert_true(b.has("max_tokens"), "max_tokens e' stato buttato: la richiesta non ha tetto")
	assert_eq(b["max_tokens"], 1)

func test_ogni_opzione_dichiarata_finisce_nel_corpo():
	var b := _c.corpo_richiesta(MSG, {
		"temperature": 0.2, "seed": 4815, "json_mode": true, "max_tokens": 400})
	assert_eq(b["temperature"], 0.2)
	assert_eq(b["seed"], 4815)
	assert_eq(b["response_format"], {"type": "json_object"}, "json_mode non diventa response_format")
	assert_eq(b["max_tokens"], 400)

## …e nulla di piu': un campo inventato che il provider non conosce puo' valere un 400.
func test_cio_che_non_e_chiesto_non_si_manda():
	var b := _c.corpo_richiesta(MSG, {})
	for campo in ["seed", "response_format", "max_tokens"]:
		assert_false(b.has(campo), "«%s» spedito senza che nessuno l'abbia chiesto" % campo)

# --- le intestazioni ---

## Si asserisce sulla STRINGA, non ciclando sulle righe: con l'elenco vuoto — che è proprio
## il caso atteso — un ciclo non asserisce niente e GUT lo segnala «risky». Un test che passa
## senza aver provato nulla è la versione piccola dello stesso difetto che questo file
## presidia: qualcosa che sembra funzionare e non c'è.
func test_senza_chiave_non_si_manda_un_authorization_vuoto():
	_c.api_key = ""
	assert_false("\n".join(_c.intestazioni()).contains("Authorization:"),
		"manda un Authorization senza chiave: il provider risponde 401 e sembra colpa sua")

## Il segnaposto dei profili (`$CHIAVE`) va sostituito col valore vero — e se la chiave non
## c'e', l'intestazione non si manda affatto invece di mandarla vuota. È il meccanismo che
## tiene Anthropic (`x-api-key`) fuori dai rami «se il provider è…» dentro il client.
func test_il_segnaposto_diventa_la_chiave():
	_c.api_key = "abc123"
	_c.intestazioni_extra = {"x-api-key": LLMClient.SEGNAPOSTO_CHIAVE, "anthropic-version": "2023-06-01"}
	var h := "\n".join(_c.intestazioni())
	assert_true(h.contains("x-api-key: abc123"), "il segnaposto non e' stato sostituito")
	assert_true(h.contains("anthropic-version: 2023-06-01"), "un valore letterale e' andato perso")

func test_senza_chiave_il_segnaposto_non_si_manda():
	_c.api_key = ""
	_c.intestazioni_extra = {"x-api-key": LLMClient.SEGNAPOSTO_CHIAVE}
	assert_false("\n".join(_c.intestazioni()).contains("x-api-key"),
		"manda x-api-key vuota invece di ometterla")

# --- la configurazione ---

## Passando da un provider all'altro i percorsi devono TORNARE ai valori predefiniti: se
## restassero quelli di prima, scegliere Mistral dopo Google lo manderebbe sull'endpoint di
## Google. È il difetto che i default espliciti in `configura()` prevengono.
func test_cambiare_provider_azzera_i_percorsi_del_precedente():
	_c.configura({"base_url": "https://a", "chat_path": "/strano/chat", "tags_path": "/api/tags"})
	assert_eq(_c.chat_path, "/strano/chat")
	_c.configura({"base_url": "https://b"})
	assert_eq(_c.chat_path, "/v1/chat/completions", "il percorso del provider precedente e' rimasto")
	assert_eq(_c.tags_path, "", "tags_path del provider precedente e' rimasto")
