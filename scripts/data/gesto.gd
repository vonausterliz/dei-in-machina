class_name Gesto
extends RefCounted

## IL GESTO: cio' che un dio FA quando la sua volonta' passa, in una riga di chat.
##
## Nasce da un difetto della Vista Olimpo: la chat mostrava la battuta del dio e poi una
## riga di servizio, «Nessuno si oppone: la volonta' di Atena passa». Due guai in uno.
## Il primo: non si capiva QUALE fosse la volonta' — il registro (castigo, aiuto, segno,
## trappola) e' cio' che muove davvero i numeri, e non arrivava mai a schermo. Il secondo:
## era un narratore che parlava dentro una chat, e in una chat non c'e' nessun narratore.
##
## Qui la volonta' che passa si legge per quello che e': un gesto di chi l'ha spuntata,
## scritto come si scrive un'azione in chat (*Atena stende la mano su di lui*). Chi perde
## ha parlato e basta. Non serve dire chi ha vinto: si vede chi ha mosso la mano.
##
## Il gesto lo propone il dio stesso (campo "gesto" della sua risposta, in carattere).
## Questa tabella e' il RIPIEGO: quando il modello lo dimentica — e lo dimentichera' —
## resta una frase corretta per quel registro, invece di una riga vuota.

const PERCORSO := "olimpo/gesti"

## Un gesto e' un gesto, non un paragrafo: oltre questo si taglia.
const MASSIMO := 120

## Il gesto di ripiego per un registro a una certa intensita'. "" se non c'e' nulla da
## mostrare: "silenzio" non e' un'azione, e "arbitrato" e' la parola di Zeus, non un atto.
static func ripiego(registro: String, intensita: int) -> String:
	var chiave := "%s/%s/%d" % [PERCORSO, registro, clampi(intensita, 1, 3)]
	return Testi.s(chiave) if Testi.ha(chiave) else ""

## Il gesto da mostrare: quello del dio se l'ha detto, altrimenti il ripiego.
## Ripulito e senza il nome in testa — il nome lo mette gia' la riga della chat, e
## «Atena Atena stende la mano» e' il genere di doppione che nessun test guarda.
static func da_proposta(proposta: Dictionary, nome_dio: String = "") -> String:
	var g := String(proposta.get("gesto", "")).strip_edges()
	if g == "":
		return ripiego(String(proposta.get("registro", "")), int(proposta.get("intensita", 1)))
	return ripulisci(g, nome_dio)

## Toglie il nome iniziale, gli asterischi dell'emote (li mette la vista) e la lunghezza
## di troppo: un gesto e' un gesto, non un paragrafo.
static func ripulisci(testo: String, nome_dio: String = "") -> String:
	# Due giri di sfrondatura: il nome puo' stare DENTRO gli asterischi («*Atena stende…*»)
	# o fuori («Atena *stende…*»). Un giro solo lasciava a schermo un asterisco spaiato.
	var g := _nudo(testo)
	if nome_dio != "" and g.to_lower().begins_with(nome_dio.to_lower()):
		g = _nudo(g.substr(nome_dio.length()).lstrip(" :,;—-"))
	if g.length() > MASSIMO:
		g = g.substr(0, MASSIMO).rstrip(" ,;:") + "…"
	return g

## Senza asterischi ne' spazi ai bordi: il corsivo lo mette la vista, non il modello.
static func _nudo(t: String) -> String:
	return t.strip_edges().lstrip("* ").rstrip("* ")
