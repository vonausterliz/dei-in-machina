extends GutTest

## «SALVA E APPLICA», E TRE MODI DI MENTIRE.
##
## Segnalazione: «settings quando faccio salva mi dice che ha salvato in realtà non è così».
## Aveva ragione tre volte, e tutte e tre finivano con lo stesso messaggio verde «salvato».
## Un bottone che mente su cio' che ha fatto e' peggio di uno che fallisce: il fallimento si
## vede, la bugia si scopre a partita iniziata con gli dei muti.
##
##  1. La chiave NUOVA non veniva applicata se una vecchia era gia' nell'ambiente. La guardia
##     era nata per non scavalcare una chiave esportata dalla shell; in pratica rendeva
##     impossibile CORREGGERE una chiave sbagliata dalla finestra fatta per correggerla.
##     Accanto al campo c'era pure scritto «gia' nell'ambiente», che sembrava una
##     rassicurazione ed era la spiegazione del guasto.
##  2. Salvare a campi vuoti CANCELLAVA le chiavi gia' salvate: il dizionario partiva vuoto e
##     veniva scritto sopra il vecchio. Bastava aprire le Impostazioni per un'altra ragione —
##     la scala, il modello — e premere «Salva».
##  3. Diceva «salvato» anche quando la scrittura falliva.
##
## Questi test non passano dalla finestra (che vuole uno schermo): provano la sostanza, cioe'
## che le preferenze contengano quello che devono dopo ogni combinazione di gesti.

const ENV_A := "PROVA_CHIAVE_A"
const ENV_B := "PROVA_CHIAVE_B"

var _chiavi_prima: Dictionary = {}

func before_each():
	_chiavi_prima = Impostazioni.chiavi().duplicate()

func after_each():
	Impostazioni.scrivi("chiavi", _chiavi_prima)
	for e in [ENV_A, ENV_B]:
		OS.set_environment(e, "")

## Il gesto che la finestra compie quando si preme «Salva e applica»: campi -> preferenze.
## Riprodotto qui perche' `_salva()` vive su una Window, e una Window vuole uno schermo.
## Se cambia di la' e non di qua, il test smette di provare quello che crede: per questo
## `test_la_finestra_fa_davvero_cosi()`, in fondo, controlla che le due cose coincidano.
func _premi_salva(campi: Dictionary) -> void:
	var chiavi: Dictionary = Impostazioni.chiavi().duplicate()
	for env in campi:
		var v: String = String(campi[env]).strip_edges()
		if v == "":
			continue
		chiavi[env] = v
		OS.set_environment(env, v)
	Impostazioni.scrivi("chiavi", chiavi)

# --- 1. la chiave nuova vince su quella d'ambiente ---

func test_una_chiave_incollata_scavalca_quella_gia_nell_ambiente():
	OS.set_environment(ENV_A, "vecchia-e-sbagliata")
	_premi_salva({ENV_A: "nuova-e-giusta"})
	assert_eq(OS.get_environment(ENV_A), "nuova-e-giusta",
		"la chiave incollata non e' stata applicata: il gioco continua con quella vecchia")
	assert_eq(String(Impostazioni.chiavi().get(ENV_A, "")), "nuova-e-giusta",
		"e non e' nemmeno stata salvata")

# --- 2. un campo vuoto non cancella niente ---

func test_salvare_a_campi_vuoti_non_cancella_le_chiavi_gia_salvate():
	_premi_salva({ENV_A: "tenuta-da-conto"})
	# Secondo salvataggio con TUTTI i campi vuoti: è il caso di chi apre le Impostazioni per
	# cambiare la scala e preme «Salva» per abitudine.
	_premi_salva({ENV_A: "", ENV_B: ""})
	assert_eq(String(Impostazioni.chiavi().get(ENV_A, "")), "tenuta-da-conto",
		"un campo vuoto ha cancellato una chiave salvata")

func test_una_chiave_nuova_non_cancella_le_altre():
	_premi_salva({ENV_A: "prima"})
	_premi_salva({ENV_B: "seconda"})
	var c := Impostazioni.chiavi()
	assert_eq(String(c.get(ENV_A, "")), "prima", "salvare la seconda ha perso la prima")
	assert_eq(String(c.get(ENV_B, "")), "seconda")

# --- 3. «salvato» dev'essere verificabile ---

## Il messaggio verde si puo' dire solo dopo aver RILETTO. È l'unico modo di sapere che è
## vero: `Impostazioni.scrivi()` non torna niente, e un disco pieno non avvisa.
func test_cio_che_si_scrive_si_rilegge_uguale():
	_premi_salva({ENV_A: "valore-da-rileggere"})
	assert_eq(String(Impostazioni.chiavi().get(ENV_A, "")), "valore-da-rileggere")

## LA GUARDIA CONTRO LA DERIVA. `_premi_salva()` qui sopra è una copia della logica di
## `FinestraImpostazioni._salva()`: se quella cambia e questa no, i test continuano a
## passare provando codice che non gira più. Qui si legge il sorgente vero e si pretende
## che le tre decisioni ci siano ancora — non è una prova di comportamento, è un allarme.
func test_la_finestra_fa_davvero_cosi():
	var sorgente := FileAccess.get_file_as_string("res://scenes/finestra_impostazioni.gd")
	var inizio := sorgente.find("func _salva()")
	assert_gt(inizio, 0, "«_salva()» non esiste più: questo test va riscritto")
	var corpo := sorgente.substr(inizio, 1800)
	assert_true(corpo.contains("Impostazioni.chiavi().duplicate()"),
		"_salva() non parte più dalle chiavi già salvate: può cancellarle")
	assert_true(corpo.contains("continue"),
		"_salva() non salta più i campi vuoti: un campo vuoto cancellerebbe")
	assert_true(corpo.contains("OS.set_environment(env, v)"),
		"_salva() non applica più la chiave all'ambiente")
	assert_false(corpo.contains("if not (OS.has_environment(env)"),
		"è tornata la guardia che impediva di correggere una chiave già nell'ambiente")
