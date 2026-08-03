extends GutTest

## LA TERRA DEVE ESSERE TUTTA GIALLA.
##
## Sulla carta si vedevano colorate solo Sicilia e Sardegna: tutto il resto — Italia,
## Grecia, Anatolia, Africa — restava del colore del mare, con solo il profilo di costa a
## suggerirlo. Il difetto non era nel colore ne' nei dati: era che
## `Geometry2D.triangulate_polygon` **falliva in silenzio** sull'unico poligono che conta,
## la terraferma, restituendo zero indici. Nessun errore, nessun avviso: semplicemente
## quella terra non veniva disegnata.
##
## La causa e' a monte: il ritaglio Sutherland-Hodgman del convertitore, su un anello
## concavo che esce e rientra dal riquadro molte volte, produce "ponti" degeneri lungo il
## bordo — un poligono auto-intersecante che nessun algoritmo di ear clipping puo' digerire.
##
## L'invariante che questo test difende: **nessuna terra resta senza riempimento.**

const PERCORSO := "res://data/coste_mediterraneo.json"

func _terre() -> Array:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERCORSO))
	assert_eq(typeof(d), TYPE_DICTIONARY, "i dati delle coste devono esserci")
	return d.get("terre", [])

func _anello(terra: Array) -> PackedVector2Array:
	var pv := PackedVector2Array()
	for p in terra:
		pv.append(Vector2(p[0], p[1]))
	return pv

func test_i_dati_delle_coste_ci_sono():
	assert_gt(_terre().size(), 10, "le terre del Mediterraneo vengono dal file dati")

## Il cuore: OGNI poligono di terra deve produrre triangoli. Prima 58 su 59 funzionavano —
## e il 59esimo era la terraferma, con un'area dodici volte tutte le isole messe insieme.
## Contare i poligoni "riusciti" avrebbe detto 98%: e' l'AREA che conta.
func test_ogni_terra_viene_riempita():
	var senza: Array = []
	for i in _terre().size():
		if MappaViaggio.triangola(_anello(_terre()[i])).is_empty():
			senza.append(i)
	assert_eq(senza, [], "queste terre resterebbero del colore del mare: %s" % str(senza))

## Il poligono grande — la terraferma — e' quello che falliva. Merita una guardia sua:
## e' il 92% della terra sulla carta.
func test_la_terraferma_e_riempita():
	var piu_grande: PackedVector2Array
	var max_punti := 0
	for terra in _terre():
		if terra.size() > max_punti:
			max_punti = terra.size()
			piu_grande = _anello(terra)
	assert_gt(max_punti, 300, "la terraferma e' il poligono con piu' vertici")
	assert_gt(MappaViaggio.triangola(piu_grande).size(), 100,
		"la terraferma non puo' restare vuota: e' quasi tutta la terra della carta")

## Un poligono spazzatura non deve far esplodere niente: la carta e' decorazione, e un
## dato storto non puo' impedire di giocare.
func test_un_anello_degenere_non_rompe_niente():
	assert_eq(MappaViaggio.triangola(PackedVector2Array()), [])
	assert_eq(MappaViaggio.triangola(PackedVector2Array([Vector2.ZERO, Vector2.ONE])), [])

## Le tappe stanno dentro il riquadro della carta: se una finisse fuori, il segnaposto di
## Ulisse uscirebbe dal pannello.
func test_le_tappe_stanno_nella_carta():
	for id in GameManager.episodi.ordine():
		var ep := GameManager.episodi.get_episodio(id)
		assert_between(ep.mappa.x, 0.0, 1.0, "%s: x fuori dalla carta" % id)
		assert_between(ep.mappa.y, 0.0, 1.0, "%s: y fuori dalla carta" % id)
