#!/usr/bin/env python3
"""Ricava data/coste_mediterraneo.json dalle coste reali di Natural Earth.

PERCHE'. Le coste della carta erano poligoni disegnati a mano con pochi vertici: nessuna
resa grafica puo' salvare una geometria sbagliata. Qui la geografia e' vera; lo stile
resta il nostro.

FONTE. Natural Earth 1:50m Physical Coastline — pubblico dominio, nessuna attribuzione
dovuta (ne_50m_coastline.zip da naturalearth.s3.amazonaws.com).

NIENTE DIPENDENZE. Lo shapefile e' un formato semplice e qui si legge a mano: aggiungere
pyshp/GDAL al progetto per un'operazione che si fa una volta sola non ha senso.

USO:  python3 tools/coste/converti_coste.py <cartella_shapefile> [uscita.json]
"""
import json, math, struct, sys
from pathlib import Path

# Il riquadro del POEMA, non del Mediterraneo intero: il viaggio di Ulisse sta fra le
# Bocche di Bonifacio (9.2E) e la Troade (26.2E), fra Gerba (33.8N) e il Circeo (41.2N).
# Includere Iberia e Levante rimpiccioliva tutto cio' che conta per mostrare mare vuoto.
LON_MIN, LON_MAX = 7.5, 28.5
LAT_MIN, LAT_MAX = 30.5, 44.0
SEMPLIFICA = 0.006   # riquadro piu' stretto, quindi piu' dettaglio a parita' di resa    # tolleranza Douglas-Peucker, in gradi (~1 km)
MIN_PUNTI  = 4        # sotto questa soglia il frammento e' rumore, non una costa


def leggi_forme(shp: Path, tipi=(3, 5)):
    """Legge PolyLine (3) e Polygon (5): stessa struttura nel record.
    Ritorna liste di anelli [(lon, lat), ...]."""
    dati = shp.read_bytes()
    i, fine, out = 100, len(dati), []          # 100 byte di intestazione
    while i < fine:
        _num, lung = struct.unpack(">ii", dati[i:i + 8])
        i += 8
        corpo = dati[i:i + lung * 2]
        i += lung * 2
        (tipo,) = struct.unpack("<i", corpo[:4])
        if tipo not in tipi:                   # tipo che non ci interessa
            continue
        n_parti, n_punti = struct.unpack("<ii", corpo[36:44])
        parti = struct.unpack("<%di" % n_parti, corpo[44:44 + 4 * n_parti])
        base = 44 + 4 * n_parti
        punti = struct.unpack("<%dd" % (2 * n_punti), corpo[base:base + 16 * n_punti])
        for k, inizio in enumerate(parti):
            stop = parti[k + 1] if k + 1 < n_parti else n_punti
            out.append([(punti[2 * j], punti[2 * j + 1]) for j in range(inizio, stop)])
    return out


def ritaglia_poligono(anello, x0, y0, x1, y1):
    """Sutherland-Hodgman contro il riquadro. Serve ai POLIGONI: tagliarli come si fa con
    le linee (spezzandoli) lascerebbe figure aperte, e il riempimento uscirebbe storto."""
    def taglia(punti, dentro_f, incrocio_f):
        fuori = []
        for k, b in enumerate(punti):
            a = punti[k - 1]
            if dentro_f(b):
                if not dentro_f(a):
                    fuori.append(incrocio_f(a, b))
                fuori.append(b)
            elif dentro_f(a):
                fuori.append(incrocio_f(a, b))
        return fuori

    def su_x(a, b, x):
        t = (x - a[0]) / (b[0] - a[0])
        return (x, a[1] + t * (b[1] - a[1]))

    def su_y(a, b, y):
        t = (y - a[1]) / (b[1] - a[1])
        return (a[0] + t * (b[0] - a[0]), y)

    r = list(anello)
    for dentro_f, incrocio_f in (
        (lambda p: p[0] >= x0, lambda a, b: su_x(a, b, x0)),
        (lambda p: p[0] <= x1, lambda a, b: su_x(a, b, x1)),
        (lambda p: p[1] >= y0, lambda a, b: su_y(a, b, y0)),
        (lambda p: p[1] <= y1, lambda a, b: su_y(a, b, y1)),
    ):
        if not r:
            return []
        r = taglia(r, dentro_f, incrocio_f)
    return r


def dentro(p):
    return LON_MIN <= p[0] <= LON_MAX and LAT_MIN <= p[1] <= LAT_MAX


def ritaglia(linea):
    """Spezza una linea nei tratti che stanno nel riquadro (niente clipping fine: i
    frammenti che escono si interrompono, e la terra continua fuori dal bordo)."""
    tratti, corrente = [], []
    for p in linea:
        if dentro(p):
            corrente.append(p)
        elif corrente:
            tratti.append(corrente)
            corrente = []
    if corrente:
        tratti.append(corrente)
    return tratti


def semplifica(punti, eps):
    """Douglas-Peucker: toglie i vertici che non cambiano la forma."""
    if len(punti) < 3:
        return punti
    a, b = punti[0], punti[-1]
    dx, dy = b[0] - a[0], b[1] - a[1]
    lung = math.hypot(dx, dy)
    peggiore, dist_max = 0, 0.0
    for k in range(1, len(punti) - 1):
        p = punti[k]
        if lung == 0:
            d = math.hypot(p[0] - a[0], p[1] - a[1])
        else:
            d = abs(dy * p[0] - dx * p[1] + b[0] * a[1] - b[1] * a[0]) / lung
        if d > dist_max:
            peggiore, dist_max = k, d
    if dist_max <= eps:
        return [a, b]
    return semplifica(punti[:peggiore + 1], eps)[:-1] + semplifica(punti[peggiore:], eps)


def normalizza(punti):
    """Gradi -> 0..1 nel riquadro. La longitudine si stringe col coseno della latitudine
    media: senza, il Mediterraneo viene largo e schiacciato."""
    k = math.cos(math.radians((LAT_MIN + LAT_MAX) / 2.0))
    lx0, lx1 = LON_MIN * k, LON_MAX * k
    out = []
    for lon, lat in punti:
        x = (lon * k - lx0) / (lx1 - lx0)
        y = (LAT_MAX - lat) / (LAT_MAX - LAT_MIN)     # y in giu': nord in alto
        out.append([round(x, 5), round(y, 5)])
    return out


def main():
    sorgente = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    uscita = Path(sys.argv[2] if len(sys.argv) > 2 else "data/coste_mediterraneo.json")
    shp = next(sorgente.glob("*coastline*.shp"))
    linee = []
    for linea in leggi_forme(shp):
        for tratto in ritaglia(linea):
            snello = semplifica(tratto, SEMPLIFICA)
            if len(snello) >= MIN_PUNTI:
                linee.append(normalizza(snello))
    linee.sort(key=len, reverse=True)

    # Le TERRE: poligoni ritagliati sul riquadro, per il riempimento. Il profilo dorato si
    # disegna dalle coste (sopra), non da questi: dopo il ritaglio un poligono ha anche i
    # lati artificiali del bordo, e disegnarli sembrerebbe una costa che non esiste.
    terre = []
    try:
        shp_terra = next(sorgente.glob("*land*.shp"))
    except StopIteration:
        shp_terra = None
    if shp_terra:
        for anello in leggi_forme(shp_terra, tipi=(5,)):
            if not any(dentro(p) for p in anello):
                continue
            r = ritaglia_poligono(anello, LON_MIN, LAT_MIN, LON_MAX, LAT_MAX)
            r = semplifica(r, SEMPLIFICA) if len(r) > 2 else r
            if len(r) >= 3:
                terre.append(normalizza(r))
        terre.sort(key=len, reverse=True)
    uscita.parent.mkdir(parents=True, exist_ok=True)
    json.dump({
        "_fonte": "Natural Earth 1:50m Physical Coastline — pubblico dominio",
        "_generato_da": "tools/coste/converti_coste.py",
        "_nota": ("Coordinate 0..1 nel riquadro del Mediterraneo. x corretto col coseno "
                  "della latitudine media; y cresce verso il basso (nord in alto)."),
        "riquadro": {"lon": [LON_MIN, LON_MAX], "lat": [LAT_MIN, LAT_MAX]},
        "linee": linee,
        "terre": terre,
    }, uscita.open("w"), separators=(",", ":"))
    print("%s — %d tratti di costa (%d punti), %d poligoni di terra (%d punti)" % (
        uscita, len(linee), sum(len(l) for l in linee),
        len(terre), sum(len(t) for t in terre)))


if __name__ == "__main__":
    main()
