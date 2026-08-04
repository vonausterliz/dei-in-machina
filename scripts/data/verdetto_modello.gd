class_name VerdettoModello
extends RefCounted

## QUESTO MODELLO GIRA SU QUESTA MACCHINA?
##
## Il verdetto che compare accanto a ogni modello di Ollama nel menu: spunta verde, punto
## interrogativo arancione, croce rossa. Risponde a «parte?», non a «ci sta in memoria?» —
## sono due domande diverse, e la differenza l'ha insegnata questa macchina: `mistral-small3.2`
## e' 15 GB su 60 di RAM, quindi in memoria ci starebbe benissimo, ma NON parte, perche'
## Ollama 0.5.11 non lo conosce. Una spunta verde su un modello che non si avvia e' peggio
## di nessuna spunta.
##
## Percio' due sorgenti, con precedenza al fatto sulla previsione:
##  1. Un fallimento GIA' MISURATO (il modello e' stato provato e non ha generato) vince
##     sempre: e' un dato, non una stima.
##  2. Altrimenti si stima dalla dimensione del file contro VRAM e RAM.
##
## Funzioni pure: si provano senza avere quell'hardware davanti.

## Segni possibili. `IGNOTO` non e' un giudizio: e' l'assenza di uno.
const OK := "ok"          # ci sta nella memoria della scheda: va alla sua velocita'
const LIMITE := "limite"  # ci sta in RAM ma non in VRAM: parte, ma lento
const NO := "no"          # non ci sta, o e' stato provato e non parte
const IGNOTO := "ignoto"  # non installato, o dimensione sconosciuta

## Un modello in memoria occupa piu' del suo file: ci vanno il contesto (KV cache), i buffer
## di calcolo e il runtime. Un quarto in piu' e' la regola pratica di Ollama a contesti
## ordinari; con contesti molto lunghi servirebbe di piu', ma allora il collo di bottiglia
## non e' piu' la scelta del modello.
const MARGINE := 1.25
## Non si riempie la VRAM fino all'orlo: ci sta anche il desktop.
const QUOTA_VRAM := 0.92
## Ne' la RAM: al sistema serve respirare, o si finisce nello swap e la lentezza e' un'altra.
const QUOTA_RAM := 0.85

## Il verdetto per un modello. `byte` = dimensione sul disco (0 = sconosciuta, cioe' non
## installato); `fallimento` = il motivo per cui una prova precedente non ha generato ("" se
## non e' mai stato provato, o se l'ultima prova e' andata bene).
## Ritorna {segno, motivo, gb_servono}.
static func giudica(byte: int, vram_gb: float, ram_gb: float, fallimento: String = "") -> Dictionary:
	# IL FATTO BATTE LA PREVISIONE. Se e' stato provato e non parte, non importa quanto sia
	# piccolo: la stima direbbe «va benissimo» e sarebbe una bugia con un numero accanto.
	if fallimento != "":
		return {"segno": NO, "gb_servono": 0.0,
			"motivo": Testi.s("hardware/provato_e_non_parte", [fallimento])}

	if byte <= 0:
		return {"segno": IGNOTO, "gb_servono": 0.0, "motivo": Testi.s("hardware/da_scaricare")}

	var gb := float(byte) / 1_073_741_824.0
	var servono := gb * MARGINE

	if vram_gb > 0.0 and servono <= vram_gb * QUOTA_VRAM:
		return {"segno": OK, "gb_servono": servono,
			"motivo": Testi.s("hardware/sta_in_vram", [gb, servono, vram_gb])}

	if ram_gb > 0.0 and servono <= ram_gb * QUOTA_RAM:
		# Due modi diversi di stare «al limite», e vanno detti diversamente: senza scheda
		# nota non si puo' promettere che vada veloce, ma nemmeno accusare la VRAM.
		if vram_gb > 0.0:
			return {"segno": LIMITE, "gb_servono": servono,
				"motivo": Testi.s("hardware/fuori_dalla_vram", [gb, servono, vram_gb, ram_gb])}
		return {"segno": LIMITE, "gb_servono": servono,
			"motivo": Testi.s("hardware/sta_in_ram_vram_ignota", [gb, servono, ram_gb])}

	return {"segno": NO, "gb_servono": servono,
		"motivo": Testi.s("hardware/troppo_grosso", [gb, servono, ram_gb])}

## Il segno da mettere davanti al nome. Non basta il colore: chi non distingue il verde dal
## rosso deve poter leggere lo stesso il verdetto.
static func simbolo(segno: String) -> String:
	match segno:
		OK: return "✓"
		LIMITE: return "?"
		NO: return "✗"
		_: return "·"

static func colore(segno: String) -> Color:
	match segno:
		OK: return Color("4e9a8e")      # verderame, come il resto delle cose che vanno
		LIMITE: return Color("cba24b")  # oro: attenzione, non allarme
		NO: return Color("b04a34")      # sangue di bue
		_: return Color("b4a98d")       # osso spento: nessun giudizio
