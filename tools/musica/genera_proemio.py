#!/usr/bin/env python3
"""Genera la musica della schermata d'apertura: ~30 secondi di lira e bordone.

PERCHE' GENERATA E NON SCARICATA
--------------------------------
La musica di un'epoca si puo' evocare in due modi: prendere una registrazione di
qualcun altro, oppure ricostruirne i mezzi. Il primo modo qui non e' praticabile — una
registrazione trovata in rete ha un autore e una licenza, e un file misterioso dentro un
repository e' un debito che nessuno sa piu' da dove venga. Il secondo si', ed e' anche
piu' onesto: questo script E' la partitura, si legge, si modifica e si riesegue.

QUANTO E' «GRECA»
-----------------
Della musica del tempo di Omero (VIII secolo a.C.) non sopravvive una sola nota. Il
frammento notato piu' antico e' di quattro secoli dopo, e l'unico brano completo che ci
sia arrivato — l'epitaffio di Sicilo — e' del I secolo d.C. Quindi qui non si «ricostruisce»
niente: si prendono i tratti che le fonti concordano nel descrivere e si scrive qualcosa di
nuovo con quelli.

  - Una voce sola. La musica greca antica era monodica: nessun accordo, nessuna armonia
    nel senso moderno. C'e' la melodia, e sotto un bordone tenuto.
  - Il genere diatonico, per tetracordi discendenti. La melodia si muove per gradi
    congiunti dentro un ambito stretto, poco piu' di un'ottava.
  - Ritmo dal metro del verso, non dalla battuta. L'esametro dattilico (— ᴗ ᴗ) da' il passo:
    una lunga e due brevi, e il tempo e' quello della recitazione.
  - Il suono della lira: corde pizzicate, che decadono. Qui e' un Karplus-Strong, che
    simula una corda facendo circolare del rumore in un ritardo che si smorza — poche
    righe di codice per un timbro che ha davvero il morso del plettro.

Uso:  python3 tools/musica/genera_proemio.py
      (scrive assets/audio/proemio.ogg; serve ffmpeg per la conversione)
"""

import math
import pathlib
import subprocess
import sys
import wave

import numpy as np

SR = 44100
DURATA = 30.0
QUI = pathlib.Path(__file__).resolve().parents[2]
USCITA = QUI / "assets" / "audio" / "proemio.ogg"

# --- La scala ---
# Ottava di Mi in genere diatonico: due tetracordi discendenti congiunti, come le fonti
# descrivono il sistema greco. In cifre moderne e' un modo dorico su Mi.
BASE = 164.81  # Mi3
GRADI = [0, 1, 3, 5, 7, 8, 10, 12, 14, 15]  # semitoni sopra la base


def nota(grado: int) -> float:
    """Frequenza del grado della scala (puo' uscire dall'elenco: si estende per ottave)."""
    if grado < len(GRADI):
        return BASE * 2 ** (GRADI[grado] / 12.0)
    return nota(grado - 7) * 2.0


def corda(freq: float, durata: float, forza: float = 1.0, smorzo: float = 0.996) -> np.ndarray:
    """Una corda pizzicata (Karplus-Strong).

    Un anello di rumore lungo quanto il periodo della nota: a ogni giro si media con il
    campione precedente e si perde un po' di energia. Le armoniche alte muoiono per prime,
    esattamente come su una corda vera — ed e' quello che distingue un pizzicato da un
    fischio.
    """
    n = int(durata * SR)
    p = max(2, int(SR / freq))
    rng = np.random.default_rng(int(freq * 1000) % 100_000)  # riproducibile
    anello = rng.uniform(-1.0, 1.0, p)
    # Il plettro non eccita tutte le frequenze allo stesso modo: un filo di passa-basso
    # sull'eccitazione toglie il graffio metallico e lascia il legno.
    anello = np.convolve(anello, [0.35, 0.5, 0.35], mode="same")
    # VIA LA CONTINUA. Il filtro del Karplus-Strong e' una media di due campioni, cioe' un
    # passa-basso: se il rumore iniziale ha media diversa da zero, quella componente non
    # decade mai e si accumula come un rimbombo sotto i 60 Hz. Alla prima misura le
    # frequenze dominanti del brano erano tutte li' sotto, e della lira non si vedeva
    # traccia — non perche' fosse piano, ma perche' era sepolta.
    anello -= anello.mean()
    out = np.empty(n, dtype=np.float64)
    i = 0
    for k in range(n):
        out[k] = anello[i]
        anello[i] = smorzo * 0.5 * (anello[i] + anello[(i + 1) % p])
        i = (i + 1) % p
    # Coda: la corda non si ferma di colpo quando finisce la nota scritta.
    return out * forza


def bordone(freq: float, durata: float) -> np.ndarray:
    """La nota tenuta sotto la melodia: fiato lungo, non elettronico.

    Un'onda con poche armoniche dispari e un vibrato lentissimo. Il vibrato e' cio' che
    la fa sembrare soffiata da qualcuno invece che calcolata.
    """
    t = np.arange(int(durata * SR)) / SR
    vib = 1.0 + 0.004 * np.sin(2 * math.pi * 4.7 * t)
    onda = np.zeros_like(t)
    for arm, peso in [(1, 1.0), (2, 0.22), (3, 0.16), (5, 0.06)]:
        onda += peso * np.sin(2 * math.pi * freq * arm * t * vib)
    # Respiro: l'intensita' non e' mai piatta.
    onda *= 0.55 + 0.45 * (0.5 + 0.5 * np.sin(2 * math.pi * 0.11 * t - 1.2))
    return onda / 1.45


def metti(tela: np.ndarray, suono: np.ndarray, quando: float) -> None:
    i = int(quando * SR)
    fine = min(len(tela), i + len(suono))
    if fine > i:
        tela[i:fine] += suono[: fine - i]


def melodia() -> list[tuple[float, int, float, float]]:
    """(istante, grado, durata, forza).

    Il passo viene dall'esametro: una lunga e due brevi. Quattro frasi che scendono e
    risalgono dentro un'ottava, con l'ultima che si posa sulla nota di base — perche' una
    schermata d'apertura deve finire, non interrompersi.
    """
    lunga, breve = 0.62, 0.31
    frasi = [
        [4, 5, 4, 3, 4, 2],
        [4, 6, 5, 4, 3, 2, 1],
        [2, 3, 4, 5, 6, 7, 6, 5],
        [4, 3, 2, 1, 0],
    ]
    fuori: list[tuple[float, int, float, float]] = []
    t = 2.6  # i primi secondi sono solo bordone: la lira entra dopo
    for n_frase, frase in enumerate(frasi):
        for i, g in enumerate(frase):
            # Dattilo: la prima di ogni terna e' lunga, le altre due brevi.
            d = lunga if i % 3 == 0 else breve
            forza = 0.85 if i % 3 == 0 else 0.55
            if i == len(frase) - 1:
                d, forza = lunga * 2.0, 0.9   # la chiusa di frase respira
            fuori.append((t, g, d + 1.4, forza))   # +1.4 = la coda della corda
            t += d
        t += 0.75 if n_frase < len(frasi) - 1 else 0.0
    return fuori


def costruisci() -> np.ndarray:
    n = int(DURATA * SR)
    tela = np.zeros(n, dtype=np.float64)

    # Il bordone: la tonica sotto tutto, e la quinta piu' tenue.
    # Il bordone sta SOTTO, non davanti: alla prima versione copriva la melodia — misurato,
    # non sentito a orecchio (le frequenze dominanti erano tutte sue).
    metti(tela, bordone(BASE / 2, DURATA) * 0.17, 0.0)
    metti(tela, bordone(BASE * 2 ** (7 / 12.0) / 2, DURATA) * 0.07, 4.0)

    for quando, grado, durata, forza in melodia():
        metti(tela, corda(nota(grado), durata, forza * 0.42), quando)
        # L'ottava sopra, molto tenue: la lira greca aveva piu' corde di quelle della
        # melodia, e un pizzicato solo nel registro grave suona come un basso, non come
        # una lira.
        if forza > 0.7:
            metti(tela, corda(nota(grado) * 2.0, durata * 0.7, forza * 0.10), quando)

    # Un tocco di ottava alta sull'ultima nota: la lira aveva piu' corde di quelle usate.
    metti(tela, corda(nota(7), 3.0, 0.16), melodia()[-1][0])

    # Entrata e uscita. L'uscita e' lunga: la schermata resta ancora tre secondi dopo il
    # silenzio, e il silenzio dev'essere arrivato per gradi, non come uno strappo.
    t = np.arange(n) / SR
    inviluppo = np.clip(t / 2.2, 0.0, 1.0) * np.clip((DURATA - t) / 4.0, 0.0, 1.0)
    tela *= inviluppo

    # Passa-alto a 45 Hz: sotto la nota piu' grave del brano non c'e' musica, solo la
    # continua residua e il rumore dell'inviluppo. Toglierla libera spazio per il resto.
    tela = _passa_alto(tela, 45.0)

    picco = float(np.max(np.abs(tela)))
    if picco > 0:
        tela = tela / picco * 0.72   # non al massimo: e' un'apertura, non un annuncio
    return tela


def _passa_alto(x: np.ndarray, taglio: float) -> np.ndarray:
    """Un polo solo: basta a togliere la continua senza colorare cio' che resta."""
    a = math.exp(-2.0 * math.pi * taglio / SR)
    y = np.empty_like(x)
    prec_x = 0.0
    prec_y = 0.0
    for i, v in enumerate(x):
        prec_y = a * (prec_y + v - prec_x)
        prec_x = v
        y[i] = prec_y
    return y


def scrivi(campioni: np.ndarray) -> None:
    USCITA.parent.mkdir(parents=True, exist_ok=True)
    temporaneo = USCITA.with_suffix(".wav")
    dati = (np.clip(campioni, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(str(temporaneo), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(dati.tobytes())
    # OGG invece di WAV: trenta secondi non compressi sono 2,6 MB dentro un repository,
    # e Godot legge l'ogg nativamente.
    esito = subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(temporaneo),
         "-c:a", "libvorbis", "-q:a", "4", str(USCITA)],
        capture_output=True, text=True)
    if esito.returncode != 0:
        print("ffmpeg ha fallito:", esito.stderr, file=sys.stderr)
        print("resta il WAV:", temporaneo, file=sys.stderr)
        return
    temporaneo.unlink()
    print(f"scritto {USCITA.relative_to(QUI)}  ({USCITA.stat().st_size / 1024:.0f} KB, {DURATA:.0f}s)")


if __name__ == "__main__":
    scrivi(costruisci())
