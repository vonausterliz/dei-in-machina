extends GutTest

## UN DIO PUO' DORMIRE FINCHE' NON HA UN MOTIVO.
##
## Poseidone si e' destato a Ismaro, fra i Ciconi, e ha punito Ulisse per un saccheggio —
## ma col saccheggio non c'entra nulla: il suo rancore nasce con l'accecamento di
## Polifemo. Il suo stesso profilo lo diceva («Ostile davvero solo dopo l'accecamento del
## figlio. All'inizio dorme») e il suo antefatto pure. Nessuna riga di codice lo faceva.
##
## Cosi' il modello si trovava a dover inventare un motivo che non c'era, e usciva una
## battuta senza senso: «Quel villaggio bruciava meglio spento a Troia.»

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(88)

func test_poseidone_dichiara_di_dormire():
	assert_eq(PantheonManager.get_dio("poseidone").dorme_finche, "maledizione_di_polifemo")

func test_poseidone_non_si_desta_prima_del_ciclope():
	GameManager.vai_a_tappa("ciconi")
	var esito: Dictionary = await GameManager.esegui_turno(
		"Porto via le giare di vino e i sacchi di grano ai Ciconi.")
	assert_does_not_have(esito["svegli"], "poseidone",
		"col saccheggio dei Ciconi non ha nulla da spartire: dorme")

## Ma Atena si', e gli altri: non e' che dorma tutto l'Olimpo.
func test_gli_altri_dei_restano_desti():
	GameManager.vai_a_tappa("ciconi")
	assert_true(PantheonManager.pantheon.eleggibili("ciconi", []).has("atena"))
	assert_false(PantheonManager.pantheon.eleggibili("ciconi", []).has("poseidone"))

## L'accecamento lo sveglia, e da quel momento non torna a dormire.
func test_dopo_la_maledizione_poseidone_si_desta():
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	assert_has(GameManager.stato.eventi_accaduti, "maledizione_di_polifemo",
		"il vanto nell'antro chiama su di se' la vendetta paterna")
	assert_true(PantheonManager.pantheon.eleggibili("ciconi",
		GameManager.stato.eventi_accaduti).has("poseidone"), "ormai e' sveglio per sempre")

## Gli eventi accaduti sopravvivono al salvataggio: un dio non torna a dormire perche' si
## e' chiuso il gioco.
func test_gli_eventi_accaduti_si_salvano():
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var percorso := "user://prova_eventi.json"
	GameManager.stato.salva(percorso)
	var riletto := StatoPartita.carica(percorso)
	assert_has(riletto.eventi_accaduti, "maledizione_di_polifemo")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(percorso))
