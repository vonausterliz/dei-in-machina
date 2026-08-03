extends GutTest

## OPENROUTER, e la barra che non e' un prefisso.
##
## Un solo endpoint per centinaia di modelli di provider diversi, in formato
## chat-completions: per il gioco e' un provider come gli altri — tranne per una cosa.
##
## I suoi nomi hanno SEMPRE la forma «autore/modello»
## (`mistralai/mistral-small-3.2-24b-instruct:free`), e il gioco tratta la barra come il
## prefisso d'instradamento del Gateway: la toglie, ovunque. Con OpenRouter significa
## mandare `mistral-small-3.2-24b-instruct:free` a un endpoint che quel nome non lo
## conosce — un 404 a ogni chiamata, e nessun indizio sul perche'.
##
## Il profilo dichiara `nome_pieno: true`: la barra fa parte del nome, non toccarla.

const PIENO := "mistralai/mistral-small-3.2-24b-instruct:free"

func before_each():
	LLMManager.mock_mode = true

func _idx_openrouter() -> int:
	return LLMManager.indice_profilo("OpenRouter")

func test_il_profilo_esiste_ed_e_un_provider_vero():
	assert_gte(_idx_openrouter(), 0, "config/providers/ deve contenere OpenRouter")
	var p: Dictionary = LLMManager.profili_esterni[_idx_openrouter()]
	assert_false(bool(p.get("trasporto", false)), "e' un provider, non un trasporto")
	assert_true(bool(p.get("nome_pieno", false)), "deve dichiarare che la barra e' del nome")
	assert_string_contains(String(p.get("base_url", "")), "openrouter.ai")

## Il cuore: senza il flag la barra viene mangiata.
func test_il_nome_col_flag_resta_intero():
	assert_eq(LLMManager.nome_nudo(PIENO, true), PIENO, "la barra e' parte del nome")
	assert_eq(LLMManager.nome_nudo("google/gemini-3.5-flash", false), "gemini-3.5-flash",
		"senza il flag la barra resta l'instradamento del Gateway, e si toglie")
	assert_eq(LLMManager.nome_nudo("models/gemini-3.5-flash", false), "gemini-3.5-flash",
		"e il prefisso dell'elenco di Google va tolto comunque")

## Scegliere un modello di OpenRouter e ritrovarlo intero: e' il giro che si fa davvero,
## ed e' dove il difetto si sarebbe visto — un 404 a partita gia' iniziata.
func test_scegliere_un_modello_openrouter_non_lo_mutila():
	var prima := LLMManager.provider_esterno_idx
	var prima_esterno := LLMManager.provider_esterno
	LLMManager.provider_esterno = true
	LLMManager.imposta_profilo_esterno(_idx_openrouter())
	LLMManager.imposta_modello(PIENO)
	assert_eq(LLMManager.modello_del_profilo(), PIENO)
	LLMManager.provider_esterno = prima_esterno
	LLMManager.imposta_profilo_esterno(prima)

## Il filtro dei modelli testuali guarda il nome: con la barra non deve scartare tutto,
## ne' confondere l'autore col modello.
func test_il_filtro_dei_modelli_regge_i_nomi_con_la_barra():
	var elenco := [
		PIENO,
		"openai/gpt-4o-mini",
		"openai/text-embedding-3-small",
		"stabilityai/stable-image-core",
	]
	var buoni := LLMManager.solo_modelli_testuali(elenco, ["embedding", "image"], true)
	assert_has(buoni, PIENO)
	assert_has(buoni, "openai/gpt-4o-mini")
	assert_does_not_have(buoni, "openai/text-embedding-3-small")
	assert_does_not_have(buoni, "stabilityai/stable-image-core")

## Col Gateway acceso il nome prende SI' un prefisso d'instradamento, ma davanti a quello
## che c'e' gia': «openrouter/mistralai/...». Il gateway divide sulla PRIMA barra, quindi
## legge provider=openrouter e modello=mistralai/... — cioe' esattamente cio' che serve.
func test_col_gateway_il_prefisso_si_aggiunge_senza_mangiare_il_nome():
	var cfg := LLMManager.attraverso_il_gateway_per_test(
		{"provider": "openrouter", "model": PIENO, "nome_pieno": true})
	assert_eq(String(cfg.get("model", "")), "openrouter/" + PIENO)
