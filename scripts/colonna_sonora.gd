class_name ColonnaSonora
extends Node

## LA MUSICA DEL GIOCO, un brano per momento, decisa in `data/musica.json`.
##
## Un «momento» e' la schermata d'apertura, uno dei quindici capitoli, la traversata fra
## due capitoli, o un finale. La tabella sta nei dati e non nel codice perche' i brani
## arriveranno uno alla volta, e aggiungerne uno non deve essere un lavoro da
## programmatore: si posa il file in `music/` e se ne scrive il nome accanto al momento.
##
## I FILE NON PASSANO DALL'IMPORTATORE DI GODOT. Un .mp3 messo in un progetto Godot non
## esiste finche' l'editor non lo importa e non genera il suo `.import`: chi aggiungesse un
## brano si troverebbe il silenzio, senza un errore che glielo dica. Qui si carica dal
## disco a runtime (`AudioStreamMP3.load_from_file`), cosi' la cartella `music/` e'
## davvero una cartella e non un pezzo di progetto. Il prezzo — un brano non compresso
## nell'esportazione — non si paga finche' il gioco si avvia dai sorgenti, che e' come si
## gioca oggi.
##
## Un momento senza file e' SILENZIO, e non e' un errore: la musica e' un ornamento. Il
## gioco non deve mai dipendere da un asset per esistere — vale gia' per la schermata
## d'apertura, che senza brano si regge sul tempo.

const CONFIG := "res://data/musica.json"

## Il brano e' finito da solo (non fermato da noi). Lo splash ci si appoggia per sapere
## quando congedarsi.
signal brano_finito(momento: String)

var _dati: Dictionary = {}
var _suono: AudioStreamPlayer
var _momento := ""
## Sfumatura in corso: secondi rimasti, e cosa fare alla fine.
var _sfuma_per := 0.0
var _sfuma_tot := 0.0
var _volume_pieno := 0.0

func _init() -> void:
	_dati = _leggi()

func _ready() -> void:
	_suono = AudioStreamPlayer.new()
	_suono.bus = "Master"
	_suono.finished.connect(_su_fine)
	add_child(_suono)
	set_process(false)

## LO STATO DELL'IMPIANTO AUDIO, in una riga leggibile.
##
## Serve perche' esiste un modo di fallire che non produce nessun sintomo dentro il gioco: il
## driver di sistema non parte, e tutto il resto continua a funzionare come se suonasse. Su
## macOS si manifesta cosi', prima ancora che il nostro codice giri:
##
##     ERROR: AudioOutputUnitStart failed, code: 2003329396
##
## `2003329396` e' `0x77686174`, cioe' i quattro caratteri **'what'**: e'
## `kAudioHardwareUnspecifiedError`, il modo di CoreAudio di dire «non ha funzionato e non so
## dirti perche'». Capita quando il dispositivo d'uscita cambia sotto i piedi (cuffie,
## Bluetooth, un monitor con altoparlanti) o quando un processo precedente non ha rilasciato
## il suo client audio — per esempio perche' e' stato ucciso invece che chiuso.
##
## Non possiamo intercettarlo: lo stampa il driver di Godot prima che esista una nostra
## riga di codice. Possiamo pero' ACCORGERCENE e dirlo, invece di lasciare che il silenzio
## sembri una scelta.
func stato_audio() -> String:
	var driver := AudioServer.get_driver_name() if AudioServer.has_method("get_driver_name") else "?"
	var uscita := AudioServer.get_output_device()
	return "driver=%s  uscita=%s  mix=%d Hz  canali=%d" % [
		driver, uscita, int(AudioServer.get_mix_rate()), AudioServer.get_bus_channels(0)]

## L'AUDIO SUONA DAVVERO? Non «crediamo di suonare»: la testa di lettura avanza?
##
## E' l'unica prova che distingue «il driver e' partito» da «il driver e' morto e noi non lo
## sappiamo». Chi chiama deve aspettare qualche fotogramma fra `suona()` e questa domanda,
## altrimenti misura zero perche' non e' passato tempo, non perche' l'audio sia fermo.
func avanza() -> bool:
	return _suono != null and _suono.playing and _suono.get_playback_position() > 0.0

## CHIUDERE RILASCIANDO IL DISPOSITIVO. Il gioco che esce senza fermare la riproduzione
## lascia a CoreAudio un client da ripulire, ed e' una delle strade per cui l'avvio
## successivo trova l'uscita occupata. Non e' una cura garantita — un processo ucciso non
## esegue niente, nemmeno questo — ma toglie di mezzo il caso in cui siamo noi la causa.
func congeda() -> void:
	set_process(false)
	if _suono != null and _suono.playing:
		_suono.stop()
	_momento = ""

static func _leggi() -> Dictionary:
	if not FileAccess.file_exists(CONFIG):
		push_warning("ColonnaSonora: manca %s" % CONFIG)
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if typeof(d) != TYPE_DICTIONARY:
		push_error("ColonnaSonora: JSON non valido in %s" % CONFIG)
		return {}
	return d

# --- La tabella ---

## I momenti dichiarati, in ordine di file. Le chiavi che cominciano per "_" sono note.
func momenti() -> Array:
	var out: Array = []
	for k in _dati.get("momenti", {}):
		if not String(k).begins_with("_"):
			out.append(String(k))
	return out

## Cosa suona a un momento: {file, ciclo, volume_db}. `file` e' un percorso ASSOLUTO gia'
## risolto, oppure "" se quel momento e' muto o non esiste.
##
## DUE MODI DI DIRE QUALE BRANO. Il primo e' scriverne il nome nella tabella. Il secondo e'
## non scrivere niente e chiamare il file come il momento — `troia.mp3` per il capitolo
## `troia` — perche' la domanda naturale di chi aggiunge una musica e' «basta metterla
## nella cartella?», e la risposta giusta a quella domanda e' si'. La tabella resta, e
## vince: serve quando il file ha un nome suo (l'apertura e' `Intro.mp3`) o quando si
## vogliono cambiare ciclo e volume.
func brano(momento: String) -> Dictionary:
	var voce: Variant = _dati.get("momenti", {}).get(momento, null)
	if typeof(voce) != TYPE_DICTIONARY:
		return {"file": "", "ciclo": false, "volume_db": 0.0}
	var nome := String(voce.get("file", "")).strip_edges()
	return {
		"file": _percorso(nome) if nome != "" else _per_convenzione(momento),
		"ciclo": bool(voce.get("ciclo", true)),
		# Il volume del momento si SOMMA a quello generale: la manopola grossa resta una.
		"volume_db": float(voce.get("volume_db", 0.0)) + float(_dati.get("volume_db", 0.0)),
	}

## Da nome di file a percorso assoluto sul disco. Un nome nudo si cerca nella cartella
## dichiarata; un percorso `res://` o assoluto si rispetta com'e'.
func _percorso(nome: String) -> String:
	if nome == "":
		return ""
	var p := nome
	if not nome.begins_with("res://") and not nome.begins_with("/"):
		p = "%s/%s" % [String(_dati.get("cartella", "res://music")), nome]
	var vero := ProjectSettings.globalize_path(p) if p.begins_with("res://") else p
	return vero if FileAccess.file_exists(vero) else ""

## Il file che si chiama come il momento, se c'e'. Si scandaglia la cartella invece di
## provare i percorsi a uno a uno perche' il confronto dev'essere INSENSIBILE ALLE
## MAIUSCOLE: su macOS `Troia.mp3` risponde a `troia.mp3`, su Linux no, e un brano che
## suona su una macchina e tace sull'altra e' il genere di differenza che fa perdere un
## pomeriggio.
func _per_convenzione(momento: String) -> String:
	var cartella := String(_dati.get("cartella", "res://music"))
	var vera := ProjectSettings.globalize_path(cartella) if cartella.begins_with("res://") else cartella
	var dir := DirAccess.open(vera)
	if dir == null:
		return ""
	var cercato := momento.to_lower()
	# Ordine di preferenza fisso: con `troia.mp3` e `troia.ogg` nella stessa cartella la
	# scelta non puo' dipendere da come il sistema elenca i file.
	for est in ["mp3", "ogg", "wav"]:
		for nome in dir.get_files():
			if nome.to_lower() == "%s.%s" % [cercato, est]:
				return vera.path_join(nome)
	return ""

func dissolvenza() -> float:
	return float(_dati.get("dissolvenza", 1.5))

# --- Suonare ---

## Attacca il brano di quel momento. Ritorna false se non c'e' nulla da suonare — e non e'
## un guasto: la maggior parte dei momenti nasce muta, e si riempira' col tempo.
func suona(momento: String) -> bool:
	var b := brano(momento)
	if String(b["file"]) == "":
		return false
	if _momento == momento and _suono != null and _suono.playing:
		return true   # gia' in onda: non si ricomincia da capo a ogni turno
	var flusso := _carica(String(b["file"]))
	if flusso == null:
		return false
	if flusso is AudioStreamMP3 or flusso is AudioStreamOggVorbis:
		flusso.loop = bool(b["ciclo"])
	_momento = momento
	_volume_pieno = float(b["volume_db"])
	_sfuma_per = 0.0
	set_process(false)
	_suono.stream = flusso
	_suono.volume_db = _volume_pieno
	_suono.play()
	return true

## Dal disco, senza importatore. Il formato si riconosce dall'estensione: sono i tre che
## Godot sa leggere a runtime.
static func _carica(percorso: String) -> AudioStream:
	match percorso.get_extension().to_lower():
		"mp3":
			return AudioStreamMP3.load_from_file(percorso)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(percorso)
		"wav":
			return AudioStreamWAV.load_from_file(percorso)
	push_warning("ColonnaSonora: formato non gestito: %s" % percorso)
	return null

## Sfuma e si ferma. Con `secondi <= 0` taglia netto.
func ferma(secondi: float = -1.0) -> void:
	if _suono == null or not _suono.playing:
		return
	var s := dissolvenza() if secondi < 0.0 else secondi
	if s <= 0.0:
		_suono.stop()
		_momento = ""
		return
	_sfuma_tot = s
	_sfuma_per = s
	set_process(true)

func _process(delta: float) -> void:
	if _sfuma_per <= 0.0:
		set_process(false)
		return
	_sfuma_per -= delta
	var quota := clampf(_sfuma_per / _sfuma_tot, 0.0, 1.0)
	# In decibel: a volume pieno si parte dal valore del brano, non da 0 dB.
	_suono.volume_db = _volume_pieno + linear_to_db(maxf(0.0001, quota))
	if _sfuma_per <= 0.0:
		_suono.stop()
		_momento = ""
		set_process(false)

func sta_suonando() -> bool:
	return _suono != null and _suono.playing

func momento_in_onda() -> String:
	return _momento if sta_suonando() else ""

func _su_fine() -> void:
	var finito := _momento
	_momento = ""
	brano_finito.emit(finito)
