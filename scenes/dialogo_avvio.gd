class_name DialogoAvvio
extends AcceptDialog

## LA SOGLIA: cosa si vede fra il sipario e la prima mossa.
##
## Prima non c'era niente. Il gioco cominciava SEMPRE una partita nuova, e chi aveva giocato
## il giorno prima si trovava di nuovo a Troia senza che nessuno gli avesse chiesto niente:
## il salvataggio c'era — `salva_partita()` esiste da sempre — ma per riprenderlo bisognava
## sapere che il menu esisteva. Un lavoro conservato che il gioco non offre di riprendere e'
## indistinguibile da un lavoro perso.
##
## E c'era una seconda cosa che mancava: **sapere con cosa si sta per giocare**. Il motore, il
## modello, l'audio. Sono le tre cose che rendono una partita diversa da un'altra e che, se
## sbagliate, si scoprono al primo turno — dopo aver scritto la prima azione, che e' il
## momento peggiore. Qui si vedono prima, insieme al bottone per sistemarle.
##
## COSA NON E'. Non e' un menu principale con le opzioni, i titoli di coda e le impostazioni
## grafiche: sono tre scelte e un referto. Una schermata che chiede troppo prima di lasciar
## giocare e' un'altra forma dello stesso difetto.

signal scelto(cosa: int)

enum { RIPRENDI, NUOVA, IMPOSTAZIONI }

const C_SEA := Color("0e0b16")
const C_BONE := Color("eadfc7")
const C_BONE_DIM := Color("b4a98d")
const C_GOLD := Color("cba24b")
const C_RUGGINE := Color("b4553c")
const C_VERDIGRIS := Color("4e9a8e")

var _serif: Font
var _serif_bold: Font
var _referto: RichTextLabel

## `stato` porta cio' che il dialogo non puo' sapere da solo, perche' appartiene ad altri:
##   ripresa    : {} oppure {episodio, turno, quando}
##   motore     : String — provider e modello, come li direbbe la barra
##   audio      : String vuota se va, altrimenti il motivo
##   guai       : Array[String] — cio' che va sistemato prima di giocare
func _init(stato: Dictionary, serif: Font, serif_bold: Font) -> void:
	_serif = serif
	_serif_bold = serif_bold
	title = Testi.s("avvio/titolo")
	# NIENTE «OK». Il bottone predefinito di AcceptDialog chiuderebbe la finestra senza che
	# nessuna delle tre scelte sia stata fatta, e il gioco resterebbe fermo su una schermata
	# muta: una via d'uscita che non porta da nessuna parte e' peggio di nessuna via d'uscita.
	get_ok_button().hide()
	exclusive = true
	unresizable = true
	_costruisci(stato)
	_vesti()

## SI VESTE DA SOLO, e non lo fa vestire a chi lo apre.
##
## Gli altri dialoghi ricevono il tema da `Main._veste_dialogo()`, e finche' li apre solo il
## gioco va bene. Questo lo apre anche `tools/foto_avvio.gd`, che il tema non ce l'ha: il
## primo scatto e' uscito col grigio di sistema, cioe' ritraeva una finestra che nessuno
## vedra' mai. Uno strumento che mostra un aspetto diverso da quello vero e' peggio di
## nessuno strumento — e la cura non e' ricopiare il tema nel tool, e' toglierlo di mezzo
## come domanda: il dialogo sa che aspetto deve avere.
func _vesti() -> void:
	var bordo := C_GOLD
	bordo.a = 0.25
	var p := StyleBoxFlat.new()
	p.bg_color = C_SEA
	p.border_color = bordo
	p.set_border_width_all(1)
	p.set_corner_radius_all(4)
	p.set_content_margin_all(18)
	add_theme_stylebox_override("panel", p)
	get_label().add_theme_color_override("font_color", C_BONE)

## Il fondo dei bottoni: appena piu' chiaro del pannello, perche' si veda che sono premibili
## senza che diventino il centro della schermata.
func _fondo_bottone(chiarore: float, contorno: float = 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = C_SEA.lerp(C_BONE, chiarore)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(10)
	if contorno > 0.0:
		var b := C_GOLD
		b.a = contorno
		s.border_color = b
		s.set_border_width_all(1)
	return s

func _costruisci(stato: Dictionary) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	add_child(v)

	var occhiello := Label.new()
	occhiello.text = Testi.s("avvio/sottotitolo")
	occhiello.add_theme_font_override("font", _serif)
	occhiello.add_theme_font_size_override("font_size", 16)
	occhiello.add_theme_color_override("font_color", C_BONE_DIM)
	occhiello.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	occhiello.custom_minimum_size.x = 520
	v.add_child(occhiello)

	# --- le scelte ---
	var ripresa: Dictionary = stato.get("ripresa", {})
	if not ripresa.is_empty():
		# IL PRIMO BOTTONE E' RIPRENDERE, e porta con se' i dettagli. «Riprendi la partita»
		# da solo obbliga a fidarsi: quale partita? di quando? Con capitolo, turno e data la
		# scelta si fa guardando, senza doverla provare per scoprirlo.
		v.add_child(_bottone(Testi.s("avvio/riprendi"), C_GOLD, func(): _scegli(RIPRENDI),
			Testi.s("avvio/riprendi_dett", [ripresa.get("episodio", "?"),
				int(ripresa.get("turno", 0)), ripresa.get("quando", "?")])))
	v.add_child(_bottone(Testi.s("avvio/nuova"), C_BONE, func(): _scegli(NUOVA)))
	v.add_child(_bottone(Testi.s("avvio/impostazioni"), C_BONE_DIM, func(): _scegli(IMPOSTAZIONI)))

	v.add_child(_riga_sottile())

	# --- il referto ---
	_referto = RichTextLabel.new()
	_referto.bbcode_enabled = true
	_referto.fit_content = true
	_referto.custom_minimum_size.x = 520
	_referto.add_theme_font_override("normal_font", _serif)
	_referto.add_theme_font_override("bold_font", _serif_bold)
	_referto.add_theme_font_size_override("normal_font_size", 15)
	_referto.add_theme_font_size_override("bold_font_size", 15)
	_referto.add_theme_color_override("default_color", C_BONE_DIM)
	_referto.text = _testo_referto(stato)
	v.add_child(_referto)

## Il referto: due righe di fatto e una di giudizio.
##
## I nomi dei campi si NEUTRALIZZANO (`Bbcode.neutro`): il modello e l'uscita audio sono
## stringhe che vengono da fuori — un file di configurazione, il sistema operativo — e una
## quadra dentro un nome aprirebbe un marcatore vero, mangiandosi il resto della riga.
func _testo_referto(stato: Dictionary) -> String:
	var righe: Array[String] = []
	righe.append("[b]%s[/b]  %s" % [Testi.s("avvio/motore"),
		Bbcode.neutro(String(stato.get("motore", "?")))])
	var audio := String(stato.get("audio", ""))
	var detto_audio := Testi.s("avvio/audio_ok")
	if audio != "":
		detto_audio = "[color=#%s]%s[/color]" % [C_RUGGINE.to_html(false), Bbcode.neutro(audio)]
	righe.append("[b]%s[/b]  %s" % [Testi.s("avvio/audio"), detto_audio])
	var guai: Array = stato.get("guai", [])
	righe.append("")
	if guai.is_empty():
		righe.append("[color=#%s]%s[/color]" % [C_VERDIGRIS.to_html(false), Testi.s("avvio/pronto")])
	else:
		righe.append("[color=#%s]%s[/color]" % [C_RUGGINE.to_html(false), Testi.s("avvio/da_sistemare")])
		for g in guai:
			righe.append("  · %s" % Bbcode.neutro(String(g)))
	return "\n".join(righe)

## Un bottone alto, con un sottotitolo facoltativo. Non sono voci di menu: sono le tre
## strade, e devono avere il peso visivo di una decisione.
func _bottone(etichetta: String, colore: Color, azione: Callable, sotto: String = "") -> Control:
	var b := Button.new()
	b.add_theme_font_override("font", _serif_bold)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", colore)
	b.add_theme_color_override("font_hover_color", C_BONE)
	b.custom_minimum_size = Vector2(520, 0)
	# Il primo bottone — quello dorato, «Riprendi» — porta anche un contorno: fra tre scelte
	# ce n'è una che è quasi sempre quella giusta, e la schermata può dirlo senza toglierne
	# nessuna. Gli altri due restano leggibili come scelte piene, non come ripieghi.
	var spicca := 0.28 if colore == C_GOLD else 0.0
	b.add_theme_stylebox_override("normal", _fondo_bottone(0.06, spicca))
	b.add_theme_stylebox_override("hover", _fondo_bottone(0.13, maxf(spicca, 0.18)))
	b.add_theme_stylebox_override("pressed", _fondo_bottone(0.03, spicca))
	b.add_theme_stylebox_override("focus", _fondo_bottone(0.10, 0.35))
	b.pressed.connect(azione)
	if sotto == "":
		b.text = etichetta
		return b
	# Il dettaglio va DENTRO il bottone, non accanto: altrimenti si puo' leggere «turno 34»
	# e premere «Comincia da Troia», che e' l'unico errore irreparabile di questa schermata.
	b.text = ""
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE   # i clic passano al bottone sotto
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	var t := Label.new()
	t.text = etichetta
	t.add_theme_font_override("font", _serif_bold)
	t.add_theme_font_size_override("font_size", 18)
	t.add_theme_color_override("font_color", colore)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var d := Label.new()
	d.text = sotto
	d.add_theme_font_override("font", _serif)
	d.add_theme_font_size_override("font_size", 13)
	d.add_theme_color_override("font_color", C_BONE_DIM)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(d)
	b.add_child(v)
	b.custom_minimum_size.y = 58
	return b

func _riga_sottile() -> Control:
	var r := ColorRect.new()
	var c := C_GOLD
	c.a = 0.20
	r.color = c
	r.custom_minimum_size.y = 1
	return r

func _scegli(cosa: int) -> void:
	scelto.emit(cosa)
