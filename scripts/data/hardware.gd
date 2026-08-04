class_name Hardware
extends RefCounted

## QUANTA MEMORIA HA QUESTA MACCHINA.
##
## Serve a una domanda sola: il modello che sto per scegliere ci gira? Un provider in rete
## non se ne cura — il ferro e' loro — ma Ollama gira in casa, e un modello da 42 GB su una
## scheda da 12 non e' «lento»: e' inservibile. Prima non c'era modo di saperlo se non
## provando, e provare un modello da 42 GB vuol dire aspettare qualche minuto per scoprirlo.
##
## Due numeri, presi da fonti diverse perche' nessuna li da' entrambi:
##  - RAM: `OS.get_memory_info().physical`, che Godot sa ovunque.
##  - VRAM: nessuna API portabile la espone. Si chiede a `nvidia-smi` dove c'e'; su Apple
##    Silicon la memoria e' unificata e la si deduce dalla RAM; altrove resta ignota, e in
##    quel caso si giudica sulla sola RAM DICENDOLO, invece di inventare una cifra.
##
## Si misura una volta e si ricorda: il menu dei modelli si ridisegna a ogni scelta, e
## lanciare un processo esterno a ogni ridisegno sarebbe assurdo.

static var _ram_gb := -1.0
static var _vram_gb := -1.0

## GB fisici totali. NON «available»: le cache del sistema sono riscattabili, e su questa
## macchina Godot riporta 7,9 GB disponibili mentre `free` ne conta 55. Il totale e' un
## numero stabile; il disponibile dipende da cos'altro sta girando in questo istante.
static func ram_gb() -> float:
	if _ram_gb < 0.0:
		_ram_gb = float(OS.get_memory_info().get("physical", 0)) / 1_073_741_824.0
	return _ram_gb

## GB di memoria video, o 0.0 se non si riesce a saperlo.
static func vram_gb() -> float:
	if _vram_gb >= 0.0:
		return _vram_gb
	_vram_gb = 0.0
	# Apple Silicon: memoria unificata. Ollama ne concede al calcolo circa i due terzi,
	# quindi non e' tutta la RAM ma nemmeno una scheda a parte.
	if OS.get_name() == "macOS" and OS.get_processor_name().contains("Apple"):
		_vram_gb = ram_gb() * 0.66
		return _vram_gb
	var uscita: Array = []
	var rc := OS.execute("nvidia-smi",
		["--query-gpu=memory.total", "--format=csv,noheader,nounits"], uscita)
	if rc == 0 and not uscita.is_empty():
		var mib := String(uscita[0]).strip_edges().get_slice("\n", 0).to_float()
		if mib > 0.0:
			_vram_gb = mib / 1024.0
	return _vram_gb

static func vram_nota() -> bool:
	return vram_gb() > 0.0

## Per il tooltip: «12 GB di scheda video, 60 GB di RAM».
static func descrizione() -> String:
	if vram_nota():
		return Testi.s("hardware/con_vram", [vram_gb(), ram_gb()])
	return Testi.s("hardware/senza_vram", [ram_gb()])

## Solo per i test: rimette lo stato non misurato, o impone valori finti.
static func dimentica(ram := -1.0, vram := -1.0) -> void:
	_ram_gb = ram
	_vram_gb = vram
