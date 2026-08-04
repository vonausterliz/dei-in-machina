class_name Bbcode
extends RefCounted

## IL TESTO CHE ARRIVA DA FUORI NON DEVE POTER SCRIVERE MARCATORI.
##
## Le tre viste del gioco (narrazione, Olimpo, ciurma) sono `RichTextLabel` con
## `bbcode_enabled = true`: interpretano `[b]`, `[color=…]`, `[img]`. Dentro ci finisce
## testo che NON abbiamo scritto noi — le battute degli dei, la voce di Omero, quella dei
## compagni, e ciò che digita il giocatore. Un modello che produce una quadra apre un
## marcatore, e da lì in poi la pagina è sua: può colorare le proprie parole d'oro come i
## titoli, chiudere un grassetto che non aveva aperto, far sparire una riga.
##
## Nel caso peggiore non è un'esecuzione di codice — `[img]` in Godot carica solo risorse
## locali, e a `meta_clicked` non è collegato nulla — ma è **contraffazione**
## dell'interfaccia, e in un gioco che si regge sul non far vedere gli dèi non è poco: la
## voce di un dio potrebbe travestirsi da voce del gioco.
##
## Il rimedio è di una riga e va messo al CONFINE: quando il testo entra, non quando si
## disegna. Dopo il confine il testo è nostro e i marcatori che ci aggiungiamo sono
## intenzionali. `[lb]` è il modo di RichTextLabel per dire «una quadra, letterale».

## Rende inerte ogni marcatore. La quadra si vede lo stesso a schermo: non si perde nulla
## di ciò che il modello ha scritto, smette solo di essere un comando.
static func neutro(t: String) -> String:
	return t.replace("[", "[lb]")
