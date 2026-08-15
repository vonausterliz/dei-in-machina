# Quadro narrativo — contratto della fase 4 e integrazione atomica della fase 5

## Che cosa significa «autorevole»

Il quadro è autorevole perché fotografa **lo stato della partita e le decisioni già prese
dal motore deterministico**. Non è un secondo canone dell'Odissea e non forza il gioco a
far accadere un episodio perché accade nel poema. Omero può variare prosa, immagini e ritmo;
non può cambiare lo stato, aggiungere conseguenze permanenti o proseguire oltre il passaggio
deciso.

Per lo scope attuale la policy resta deliberatamente stretta:

- l'ordine delle tappe è quello di `Episodi.ordine()`, senza rami alternativi;
- un passaggio è zero oppure uno per turno, sempre verso la tappa immediatamente successiva;
- la pressione continua per gradi e, quando sposta Ulisse, la causa è `prodigio`;
- una partenza scelta o una fuga restano possibili secondo le regole già in `Viaggio`.

La policy non è hardcoded nel quadro: `QuadroNarrativo.politica_rotta_fissa(ordine, nomi)`
la riceve dai dati. In futuro cambiare politica narrativa non richiederà di falsificare uno
stato o riscrivere il contratto.

## Contratto di dati

`scripts/narrazione/quadro_narrativo.gd` espone funzioni statiche e usa soltanto
`Dictionary`/`Array`, senza Autoload e senza importare il validatore dell'azione:

```gdscript
var quadro := QuadroNarrativo.crea(
    stato_prima,
    {"testo": input_testo, "sintesi": envelope["sintesi"],
     "tipo": envelope["tipo"], "tag": envelope["tag"]},
    {"delta": delta, "eventi": eventi_turno, "fatti": fatti_deterministici,
     "esito": esito, "pressione": {"grado": grado, "spinge": spinge}},
    stato_dopo,
    momento,
    fatti_ammessi,
    fatti_vietati,
    passaggio,
    QuadroNarrativo.politica_rotta_fissa(ordine, nomi)
)
```

Le sezioni sono sempre distinte:

- `stato_prima` e `stato_dopo`: almeno `episodio: {id, nome}`, più soli dati
  player-facing necessari alla scena;
- `azione`: parole esatte e interpretazione già validata;
- `conseguenze`: esito deterministico, mai proposto da Omero;
- `passaggio`: esplicitamente assente oppure `{avvenuto, da, a, causa}`;
- `momento`;
- `vincoli.salto_temporale_ammesso`: in questo flusso e' sempre `false`, perche' il
  momento del turno non autorizza a inventare giorni o notti trascorsi;
- `fatti.ammessi` e `fatti.vietati` (questi ultimi possono essere stringhe o
  `{id, descrizione?, marcatori:[...]}`).

`valida()` rifiuta un cambio di episodio senza passaggio, una causa fuori elenco, un salto
di tappa e una spinta della pressione che non sia un prodigio. `come_contesto_omero()` crea
il contesto per `LLMManager` e mantiene `azione`/`sintesi` in cima per compatibilità. Il mock
legge anche il passaggio e rende origine e destinazione nella stessa voce deterministica:
anche nei test il cambio non è un teletrasporto.

`per_validatore()` è l'adattatore puro al guardrail della prosa: produce sempre
`passaggio_avvenuto`, `origine`, `destinazione`, `causa`, `rotta`, `momento`,
`salto_temporale_ammesso`, `pressione` e `fatti_vietati`, anche quando origine e destinazione
sono la tappa corrente e il passaggio non e' avvenuto. Il validatore non importa
`QuadroNarrativo`: la composizione spetta a `Narratore`, quindi non c'è dipendenza circolare.

## Integrazione atomica della fase 5

L'integrazione è applicata in `GameManager.esegui_turno()`, mantenendo `Viaggio` come unica
autorità deterministica sull'avanzamento. La riorganizzazione non aggiunge regole o rami:
cambia il momento in cui lo stato già deciso viene consegnato a Omero.

Ordine effettivo in `GameManager.esegui_turno()`:

1. Prima di `Delta.applica`, cattura per copia profonda `stato_prima` e
   `episodio_prima`. Lo snapshot deve contenere solo informazioni player-facing; mai
   `registro_divino`, proposte, scavalcamenti o identità nascoste.
2. Completa validazione, risveglio, deliberazione e composizione del `delta`; applica il
   delta una volta sola.
3. Risolve **prima dell'avanzamento** tutte le regole della vecchia tappa, in particolare
   `_trattiene()` di Ogigia e l'esito terminale. Se si avanzasse prima, `_trattiene()`
   leggerebbe per errore la tappa nuova.
4. Se l'esito continua ed il turno è in-mondo, chiama una sola volta
   `viaggio.avanza(envelope)`. Questo è il solo punto che decide e muta la tappa. Far cadere
   qui i destinati della tappa chiusa. Non esiste più una richiesta separata a Omero per
   il passaggio.
5. Cattura `stato_dopo`. Per l'arrivo finale a Itaca usa l'`episodio` restituito da
   `Viaggio.avanza()`: oggi il ramo finale restituisce `itaca` senza chiamare `entra()`,
   quindi leggere soltanto `stato.viaggio.corrente` darebbe ancora Scheria.
6. Costruisce `passaggio`: se `avanzato`, `da` è lo snapshot prima, `a` è il risultato di
   avanzamento e `causa` è quella già restituita da `Viaggio`; altrimenti è `{}`. Per lo
   scope corrente `spinge = avanzato and causa == "prodigio"`, perché `avanza()` azzera il
   contatore entrando nella tappa nuova e il grado non è più ricavabile dopo.
7. Costruisce e valida il quadro. Se non è valido, non chiama il modello: è un errore di
   orchestrazione, non qualcosa che Omero possa riparare.
8. Chiama **una sola volta** `LLMManager.narrazione_e_spunti(...)`. Il contesto contiene il
   quadro e una sezione di continuità subordinata (cronaca, ultime mosse, ultima voce e
   parole ai compagni): conserva il filo senza diventare una seconda fonte di stato. La
   narrazione comprende azione, conseguenze e traversata; gli spunti guardano lo stato dopo.
9. Fa commentare la ciurma sulla narrazione unica.
10. Registra la voce conservando esplicitamente `voce.episodio = episodio_prima` e
    `voce.quadro_narrativo = quadro`, senza ricavarne l'episodio dallo stato ormai mutato;
    infine aggiorna la cronaca.

Risultato pubblico:

```gdscript
{
    "voce": voce,                         # narrazione unica
    "episodio": avanzamento["episodio"], # stato dopo
    "avanzato": avanzamento["avanzato"],
    "causa": avanzamento.get("causa", ""),
    "intro": avanzamento["intro"],
    "transizione": "",                   # chiave compatibile, niente seconda voce
    "quadro_narrativo": quadro,
}
```

In `scenes/main.gd` la UI mostra una sola voce di Omero. Aggiorna titolo, mappa e musica
quando `avanzato`; non appende `transizione` e non presenta `intro` come una seconda
narrazione dopo che il quadro ha già raccontato l'arrivo. L'intro resta utile come dato di
scena e per l'apertura di una partita, non come secondo approdo.

Questa sequenza rende atomica la transizione anche in errore: o esiste un quadro valido con
un solo stato dopo e un solo passaggio, oppure Omero non viene chiamato. La sua prosa non
viene mai letta per mutare lo stato, quindi un dettaglio estemporaneo non diventa canonico.
