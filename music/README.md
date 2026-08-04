# La colonna sonora

Un brano per **momento** del gioco: la schermata d'apertura, ognuno dei quindici capitoli,
la traversata fra un capitolo e l'altro, i tre finali.

## Aggiungerne uno

**Metti il file in questa cartella e chiamalo come il momento.** Nient'altro.

```
music/troia.mp3        → suona alla partenza da Troia
music/ciclope.ogg      → suona nell'antro del Ciclope
music/fine_itaca.mp3   → suona quando torni a casa
```

Valgono `.mp3`, `.ogg` e `.wav`; maiuscole e minuscole non contano. Non serve reimportare
nulla né riaprire l'editor: i brani si leggono dal disco quando servono.

In `data/musica.json` si può, se serve, scrivere il nome del file per esteso (utile quando
ha un nome suo) e regolare `ciclo` — se il brano ricomincia da capo — e `volume_db`. Quello
che è scritto lì vince sempre sul nome del file.

Gli identificatori dei momenti sono nella tabella qui sotto, e nell'elenco in coda:
`splash`, `traversata`, `fine_morte`, `fine_prigionia_eterna`, `fine_itaca`.

## Come sono fatti i brani dei capitoli

Generati con **ACE-Step 1.5**. Sotto ci sono i prompt esatti, uno per capitolo: sono la
*partitura* di questa colonna sonora — si leggono, si rieseguono, si modificano. Chi vuole
una versione sua di un capitolo ha da dove partire, e chi vuole capire perché un brano suona
così lo trova scritto.

Tre vincoli valgono per tutti, e sono la ragione per cui i brani funzionano come musica di
gioco invece che come brani da ascoltare:

- **strumenti dell'epoca soltanto** — lira, kithara, aulos doppio, tamburo a cornice,
  crotali di bronzo, flauto di canna, bordone. Nessuna orchestra, nessun coro, nessun
  sintetizzatore, nessun suono da trailer;
- **anello senza cuciture** — nessuna cadenza finale, nessuna dissolvenza, nessun finale
  drammatico: le ultime battute devono tornare naturalmente all'armonia, al ritmo e alla
  trama d'apertura;
- **intensità costante** — un brano di sottofondo non deve crescere verso un climax, perché
  non sa quanto durerà la scena.

| # | Momento | BPM | Tonalità | Atmosfera |
|---|---|---:|---|---|
| 1 | `troia` — La partenza da Troia | 72 | Re minore | solenne, malinconica, inizio del viaggio |
| 2 | `ciconi` — I Ciconi di Ismaro | 96 | Mi minore | battaglia, tensione controllata |
| 3 | `lotofagi` — La terra dei Lotofagi | 58 | La minore | sogno, oblio, seduzione |
| 4 | `ciclope` — L'antro del Ciclope | 62 | Do minore | caverna, minaccia, peso |
| 5 | `eolo` — L'isola di Eolo | 76 | Sol minore | vento, meraviglia, instabilità |
| 6 | `laestrigoni` — Il porto dei Lestrigoni | 80 | Fa minore | imboscata, porto chiuso, terrore |
| 7 | `circe` — Il palazzo di Circe | 66 | Re minore | magia, lusso, pericolo seducente |
| 8 | `ade` — La soglia dell'Ade | 48 | Si minore | morte, rituale, immobilità |
| 9 | `sirene` — Il canto delle Sirene | 60 | Mi minore | attrazione fatale |
| 10 | `scilla` — Lo stretto di Scilla e Cariddi | 104 | Re minore, 6/8 | corrente, urgenza, due minacce |
| 11 | `trinacia` — L'isola del Sole | 68 | La minore | sacro, luminoso, proibito |
| 12 | `ogigia` — L'isola di Calipso | 56 | Sol minore | paradiso, nostalgia, prigionia dolce |
| 13 | `naufragio` — La tempesta | 112 | Do minore, 6/8 | caos marino, sopravvivenza |
| 14 | `scheria` — La terra dei Feaci | 78 | Sol maggiore / Mi minore | accoglienza, civiltà, sollievo |
| 15 | `itaca` — Itaca | 64 | Re minore con accenni più luminosi | ritorno, memoria, casa, tensione irrisolta |

---

## I prompt

### 1 · `troia` — La partenza da Troia
**72 BPM · Re minore**

> Historically inspired archaic Greek game ambience for the departure from Troy. Solemn and restrained, carrying the sadness of war, burnt ruins and the uncertainty of the sea voyage ahead. Ancient lyre and kithara play a slow Dorian modal pattern, supported by low frame drum pulses, distant double aulos and a quiet continuous drone. Heroic but not triumphant, melancholic but not tragic. Sparse arrangement, no vocals, no choir, no orchestra, no modern instruments, no cinematic trailer sound. Designed as seamless looping game background music. No final cadence, no fade-out, no dramatic ending. The last bars must return naturally to the opening harmony, rhythm and texture. Stable tempo, constant ambience, loop-friendly arrangement.

### 2 · `ciconi` — I Ciconi di Ismaro
**96 BPM · Mi minore**

> Archaic Greek battle ambience for the raid at Ismaros and the counterattack of the Cicones. Dry frame drums, hand percussion, bronze crotales, tense double aulos phrases and short aggressive kithara figures. Rhythmic and urgent but suitable as continuous gameplay background, not a cinematic battle climax. Uneasy repeating pulse, disciplined tribal rhythm, restrained danger, no large orchestra, no brass, no choir, no modern drums, no electronic sounds. Designed as seamless looping game background music. No final cadence, no fade-out, no dramatic ending. The last bars must return naturally to the opening harmony, rhythm and texture. Stable tempo, constant ambience, loop-friendly arrangement.

### 3 · `lotofagi` — La terra dei Lotofagi
**58 BPM · La minore**

> Dreamlike archaic Mediterranean ambience for the land of the Lotus Eaters. Soft plucked lyre, gentle kithara harmonics, airy reed flute, distant aulos and a warm hypnotic drone. Very slow circular melody, blurred sense of time, peaceful but subtly unsettling, seductive forgetfulness and loss of purpose. Minimal percussion, soft natural ambience, no vocals, no modern synthesizers, no cinematic orchestra, no bright resolution. Designed as seamless looping game background music. No final cadence, no fade-out, no dramatic ending. The last bars must return naturally to the opening harmony, rhythm and texture. Stable tempo, constant ambience, loop-friendly arrangement.

### 4 · `ciclope` — L'antro del Ciclope
**62 BPM · Do minore**

> Dark archaic Greek cave ambience for the lair of the Cyclops. Deep skin drums, low resonant drone, sparse lyre notes, rough wooden percussion and distant breathy aulos tones echoing inside a massive stone cavern. Slow irregular-feeling accents over a stable pulse, oppressive silence, primal danger, heavy footsteps suggested through percussion. No monster vocals, no choir, no orchestra, no modern horror effects, no jump-scare ending. Designed as seamless looping game background music. No final cadence, no fade-out, no dramatic ending. The last bars must return naturally to the opening harmony, rhythm and texture. Stable tempo, constant ambience, loop-friendly arrangement.

### 5 · `eolo` — L'isola di Eolo
**76 BPM · Sol minore**

> Airy archaic Greek ambience for the floating island of Aeolus, lord of the winds. Flowing lyre arpeggios, light kithara, breathy double aulos, soft frame drum and layers of natural wind-like instrumental textures. The melody should rise and fall like changing air currents, graceful and mysterious, with occasional unstable modal turns suggesting winds trapped inside a leather bag. No vocals, no storm climax, no modern pads, no orchestra. Designed as seamless looping game background music. No final cadence, no fade-out, no dramatic ending. The last bars must return naturally to the opening harmony, rhythm and texture. Stable tempo, constant ambience, loop-friendly arrangement.

### 6 · `laestrigoni` — Il porto dei Lestrigoni
**80 BPM · Fa minore**

> Tense archaic Greek harbour ambience for the land of the Laestrygonians. Low frame drums, ominous aulos, muted kithara strikes and a dark sustained drone. The music should suggest a narrow enclosed harbour, hidden watchers and an unavoidable ambush. Repeating rhythm that gradually feels more threatening without building to a final climax. Dense, claustrophobic and hostile, no vocals, no cinematic orchestra, no brass, no modern percussion, no horror stingers. Designed as seamless looping game background music. No final cadence, no fade-out, no dramatic ending. The last bars must return naturally to the opening harmony, rhythm and texture. Stable tempo, constant ambience, loop-friendly arrangement.

### 7 · `circe` — Il palazzo di Circe
**66 BPM · Re minore**

> Enchanting archaic Greek palace ambience for the sorceress Circe. Elegant lyre and kithara patterns, soft hand percussion, sinuous double aulos melody, delicate bronze crotales and a low hypnotic drone. Beautiful, refined and seductive, but with subtle dissonance suggesting transformation and danger. Repeating ritual motif, intimate palace acoustics, no vocals, no female choir, no modern fantasy orchestra, no sparkling synthesizers. Designed as seamless looping game background music. No final cadence, no fade-out, no dramatic ending. The last bars must return naturally to the opening harmony, rhythm and texture. Stable tempo, constant ambience, loop-friendly arrangement.

### 8 · `ade` — La soglia dell'Ade
**48 BPM · Si minore**

> Extremely dark ritual ambience for the threshold of the Greek underworld. Very low drone, sparse deep frame drum, isolated lyre strings, distant mournful aulos and occasional bronze resonance. Slow, cold and ceremonial, evoking shadows, forgotten souls and a forbidden border between the living and the dead. Minimal melody, long spaces between notes, no vocals, no choir, no orchestral crescendo, no modern horror soundtrack, no final resolution. Designed as seamless looping game background music. No final cadence, no fade-out, no dramatic ending. The last bars must return naturally to the opening harmony, rhythm and texture. Stable tempo, constant ambience, loop-friendly arrangement.

### 9 · `sirene` — Il canto delle Sirene
**60 BPM · Mi minore**

Niente parole vere: rischierebbero di ripetersi male nell'anello.

> Mesmerising archaic Greek ambience for the island of the Sirens. Soft lyre ostinato, distant aulos, gentle sea-like drone and ethereal wordless female vocal tones used as an instrument, without intelligible lyrics. Beautiful, irresistible and subtly dangerous, with circular melodic phrases that never fully resolve. The voices should feel distant and supernatural, not like a modern choir or pop singing. Sparse percussion, no orchestra, no cinematic climax, no modern synthesizers. Designed as seamless looping game background music. No final cadence, no fade-out, no dramatic ending. The last bars must return naturally to the opening harmony, rhythm and texture. Stable tempo, constant ambience, loop-friendly arrangement.

Se il modello finisce per cantare parole comprensibili, sostituire
`ethereal wordless female vocal tones` con
`breathy double aulos imitating distant human voices, absolutely no vocals`.

### 10 · `scilla` — Lo stretto di Scilla e Cariddi
**104 BPM · Re minore · 6/8**

> Urgent archaic Greek maritime ambience for the passage between Scylla and Charybdis. Fast 6/8 frame drum rhythm, tense repeated kithara figure, sharp double aulos phrases and a dark rotating drone. The rhythm should suggest rowing, violent currents and a ship being pulled between two dangers. Continuous tension without a cinematic conclusion, energetic but not overwhelming, no vocals, no orchestra, no modern drums, no brass, no trailer impacts. Designed as seamless looping game background music. No final cadence, no fade-out, no dramatic ending. The last bars must return naturally to the opening harmony, rhythm and texture. Stable tempo, constant ambience, loop-friendly arrangement.

### 11 · `trinacia` — L'isola del Sole
**68 BPM · La minore**

> Sacred archaic Greek pastoral ambience for the island of Helios and his forbidden cattle. Clear lyre and kithara, warm reed flute, soft frame drum and delicate bronze crotales. Sunlit, peaceful and majestic, yet marked by a subtle sense of taboo and divine surveillance. Modal pastoral melody with occasional darker notes foreshadowing sacrilege. No vocals, no choir, no triumphant orchestra, no modern fantasy sound, no dramatic ending. Designed as seamless looping game background music. No final cadence, no fade-out, no dramatic ending. The last bars must return naturally to the opening harmony, rhythm and texture. Stable tempo, constant ambience, loop-friendly arrangement.

### 12 · `ogigia` — L'isola di Calipso
**56 BPM · Sol minore**

> Lush but restrained archaic Mediterranean ambience for Calypso's island of Ogygia. Gentle lyre, flowing kithara, soft reed flute, distant aulos and a warm continuous drone. Peaceful, intimate and beautiful, with a persistent undertone of longing, isolation and the desire to return home. Slow circular melody, very light percussion, natural coastal atmosphere, no vocals, no romantic orchestra, no modern ambient synthesizers, no final resolution. Designed as seamless looping game background music. No final cadence, no fade-out, no dramatic ending. The last bars must return naturally to the opening harmony, rhythm and texture. Stable tempo, constant ambience, loop-friendly arrangement.

### 13 · `naufragio` — La tempesta
**112 BPM · Do minore · 6/8**

> Violent archaic Greek storm ambience for Odysseus' shipwreck. Rapid 6/8 frame drums, irregular hand percussion, low kithara ostinato, piercing double aulos and a turbulent drone suggesting wind and waves. Urgent, chaotic and relentless, but structured enough for continuous gameplay. Avoid a cinematic build or final crash; maintain a repeatable middle-intensity storm pattern. No vocals, no orchestra, no modern drums, no thunder sound effects dominating the music, no trailer impacts. Designed as seamless looping game background music. No final cadence, no fade-out, no dramatic ending. The last bars must return naturally to the opening harmony, rhythm and texture. Stable tempo, constant ambience, loop-friendly arrangement.

### 14 · `scheria` — La terra dei Feaci
**78 BPM · Sol maggiore oppure Mi minore**

> Graceful archaic Greek court ambience for the land of the Phaeacians. Refined lyre and kithara interplay, warm reed flute, gentle double aulos, light frame drum and subtle bronze crotales. Welcoming, cultured and serene, suggesting hospitality, storytelling and safe passage after long suffering. Elegant modal dance rhythm, calm and dignified, no vocals, no large orchestra, no medieval court music, no modern cinematic fantasy. Designed as seamless looping game background music. No final cadence, no fade-out, no dramatic ending. The last bars must return naturally to the opening harmony, rhythm and texture. Stable tempo, constant ambience, loop-friendly arrangement.

### 15 · `itaca` — Itaca
**64 BPM · Re minore, con accenni più luminosi**

> Emotional archaic Greek ambience for Odysseus returning to Ithaca. Intimate solo lyre begins a familiar recurring motif, joined by warm kithara, restrained aulos and a soft frame drum pulse. The mood combines recognition, longing, relief and hidden tension: home has been reached, but the struggle is not yet over. Noble and deeply human, never sentimental or triumphantly cinematic. No vocals, no choir, no orchestra, no modern instruments, no conclusive ending. Designed as seamless looping game background music. No final cadence, no fade-out, no dramatic ending. The last bars must return naturally to the opening harmony, rhythm and texture. Stable tempo, constant ambience, loop-friendly arrangement.

---

## I momenti che non sono capitoli

| Momento | Quando suona |
|---|---|
| `splash` | la schermata d'apertura. Non cicla: la schermata si congeda tre secondi dopo l'ultima nota, e un brano che ricomincia la terrebbe lì per sempre |
| `traversata` | il tragitto fra un capitolo e l'altro |
| `fine_morte` | Odisseo non ce l'ha fatta |
| `fine_prigionia_eterna` | è rimasto sull'isola dove il tempo non passa |
| `fine_itaca` | il ritorno |
