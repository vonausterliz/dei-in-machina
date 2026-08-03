class_name Dio
extends RefCounted

## Rappresentazione tipizzata di una voce di data/pantheon.json (schema 0.3).

var id: String = ""
var nome: String = ""
## Distintivo accanto al nome nella Vista Olimpo. Lettere GRECHE, non emoji: il font
## dell'interfaccia non ha glifi emoji e le disegnerebbe come quadratini vuoti.
var simbolo: String = ""
var epiteti: Array[String] = []
var natura: String = ""
var fascia: String = ""
var attivo: bool = false
var episodio: Variant = null
var fazione: String = ""
var dominio: String = ""
var agenda: String = ""
## Cio' che il dio ricorda di PRIMA della storia: la guerra di Troia, i conti gia' aperti
## con Ulisse, la propria vicenda. Senza, non e' il dio dell'Odissea ma un dio generico.
var antefatto: String = ""
var trigger_azione: Array[String] = []
var trigger_evento: Array[String] = []
## Finche' questo evento non e' accaduto, il dio NON e' eleggibile: dorme. Poseidone lo
## dichiarava a parole ("all'inizio dorme") senza che niente lo facesse, e si destava fra
## i Ciconi a punire un saccheggio con cui non c'entra nulla.
var dorme_finche: String = ""
var impronta: String = ""
var registri: Array[String] = []
var dono_avvelenato: bool = false
var voce: String = ""
var temperamento: String = ""
var favore_iniziale: int = 0
var ira_iniziale: int = 0
var nota: String = ""
var esempi_voce: Array[String] = []
var anti_pattern: String = ""

static func from_dict(d: Dictionary) -> Dio:
	var dio := Dio.new()
	dio.id = d.get("id", "")
	dio.nome = d.get("nome", "")
	dio.simbolo = d.get("simbolo", "")
	dio.epiteti = _stringhe(d.get("epiteti", []))
	dio.natura = d.get("natura", "")
	dio.fascia = d.get("fascia", "")
	dio.attivo = d.get("attivo", false)
	dio.episodio = d.get("episodio", null)
	dio.fazione = d.get("fazione", "")
	dio.dominio = d.get("dominio", "")
	dio.agenda = d.get("agenda", "")
	dio.antefatto = d.get("antefatto", "")
	dio.trigger_azione = _stringhe(d.get("trigger_azione", []))
	dio.trigger_evento = _stringhe(d.get("trigger_evento", []))
	dio.dorme_finche = d.get("dorme_finche", "")
	dio.impronta = d.get("impronta", "")
	dio.registri = _stringhe(d.get("registri", []))
	dio.dono_avvelenato = d.get("dono_avvelenato", false)
	dio.voce = d.get("voce", "")
	dio.temperamento = d.get("temperamento", "")
	var disposizione: Dictionary = d.get("disposizione_iniziale", {})
	dio.favore_iniziale = disposizione.get("favore", 0)
	dio.ira_iniziale = disposizione.get("ira", 0)
	dio.nota = d.get("nota", "")
	dio.esempi_voce = _stringhe(d.get("esempi_voce", []))
	dio.anti_pattern = d.get("anti_pattern", "")
	return dio

static func _stringhe(sorgente: Array) -> Array[String]:
	var out: Array[String] = []
	for v in sorgente:
		out.append(String(v))
	return out
