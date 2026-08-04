extends GutTest

## LA SCELTA DEL MODELLO DEVE SOPRAVVIVERE ALLA CHIUSURA.
##
## Non lo faceva, e in un modo che non lasciava tracce: la preferenza era UNA sola per
## tutto il gioco («modello»), mentre i modelli appartengono al provider —
## «gemini-3.5-flash» non vuol dire niente per Mistral. E al riavvio veniva applicata
## quando il percorso esterno non era ancora acceso, quindi finiva nel profilo di Ollama.
## Sceglievi Gemini, riaprivi, e ti ritrovavi il modello di prima senza un errore.

var _idx_prima := 0
var _modelli_prima: Array = []
var _preferenze_prima: Array = []

## Questi test scrivono nelle preferenze VERE dell'utente (user://impostazioni.json) e nei
## profili in memoria. Senza ripulire, i valori finti restavano: un altro test ci e' gia'
## inciampato, e sarebbero finiti anche nel gioco dell'utente. Un test che lascia tracce
## fuori da se' non e' un test, e' un effetto collaterale.
func before_each():
	_idx_prima = LLMManager.profilo_idx
	LLMManager.usa_gateway = false
	_modelli_prima = []
	_preferenze_prima = []
	for i in LLMManager.profili.size():
		_modelli_prima.append(String(LLMManager.profili[i].get("model", "")))
		_preferenze_prima.append(LLMManager.modello_ricordato(i))

func after_each():
	for i in LLMManager.profili.size():
		LLMManager.profili[i]["model"] = _modelli_prima[i]
		LLMManager.profilo_idx = i
		if String(_preferenze_prima[i]) == "":
			Impostazioni.dimentica(LLMManager._chiave_modello(i))
		else:
			Impostazioni.scrivi(LLMManager._chiave_modello(i), _preferenze_prima[i])
	LLMManager.profilo_idx = _idx_prima
	LLMManager.usa_gateway = false

func test_il_modello_si_ricorda_per_ogni_provider():
	if LLMManager.profili.size() < 2:
		pending("servono almeno due profili"); return
	LLMManager.profilo_idx = 0
	LLMManager.ricorda_modello("modello-del-primo")
	LLMManager.profilo_idx = 1
	LLMManager.ricorda_modello("modello-del-secondo")
	assert_eq(LLMManager.modello_ricordato(0), "modello-del-primo")
	assert_eq(LLMManager.modello_ricordato(1), "modello-del-secondo",
		"i modelli appartengono al provider: una preferenza sola non basta")

## Il caso che rompeva tutto: al riavvio il percorso esterno NON e' ancora acceso.
func test_il_modello_torna_nel_profilo_anche_a_motore_spento():
	if LLMManager.profili.is_empty():
		pending("nessun profilo esterno"); return
	LLMManager.profilo_idx = 0
	LLMManager.ricorda_modello("un-modello-scelto")
	LLMManager.applica_modelli_ricordati()
	assert_eq(String(LLMManager.profili[0]["model"]), "un-modello-scelto",
		"la scelta deve arrivare al profilo, non al provider locale")

func test_il_prefisso_dell_elenco_non_si_salva():
	if LLMManager.profili.is_empty():
		pending("nessun profilo esterno"); return
	LLMManager.profilo_idx = 0
	LLMManager.ricorda_modello("models/gemini-3.5-flash")
	assert_eq(LLMManager.modello_ricordato(0), "gemini-3.5-flash",
		"«models/» e' di Google, non fa parte del nome")

# --- Filtro dell'elenco: solo modelli che scrivono testo ---

## L'elenco di Google contiene sintesi vocale, immagini, video ed embedding. Metterli nel
## menu è offrire scelte che non possono funzionare: il gioco sa solo scrivere.
func test_l_elenco_tiene_solo_i_modelli_testuali():
	var grezzo := ["gemini-3.5-flash", "text-embedding-004", "imagen-4.0-generate",
		"veo-3.0-generate", "gemini-2.5-flash-tts", "gemini-3.5-flash-lite",
		"gemini-live-2.5-flash-audio", "aqa"]
	var escludi := ["embedding", "imagen", "veo", "tts", "audio", "aqa", "image"]
	var puliti := LLMManager.solo_modelli_testuali(grezzo, escludi)
	assert_eq(puliti, ["gemini-3.5-flash", "gemini-3.5-flash-lite"])

func test_senza_filtro_dichiarato_non_si_scarta_niente():
	var grezzo := ["uno", "due"]
	assert_eq(LLMManager.solo_modelli_testuali(grezzo, []), grezzo,
		"un provider che non dichiara nulla non deve perdere modelli")

func test_il_profilo_gemini_dichiara_il_filtro():
	for p in LLMManager.profili:
		if String(p.get("provider", "")) == "google":
			assert_false(Array(p.get("escludi_modelli", [])).is_empty(),
				"il filtro sta nei dati del provider, non nel codice")
			return
	pending("nessun profilo Google configurato")
