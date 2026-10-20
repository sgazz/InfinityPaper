# InfinityPaper

InfinityPaper je nativna aplikacija za iPhone i iPad za crtanje i skiciranje na platnu koje se može pomerati i zumirati. Interfejs je napravljen u SwiftUI-ju, a crtanje koristi UIKit i Core Graphics.

## Mogućnosti

- Uvoz jedne referentne slike po crtežu iz Photos ili Files, uz položaj, veličinu, providnost i izbor uključivanja u izvoz.
- Biblioteka crteža sa nazivima, pregledima, preimenovanjem, dupliranjem i brisanjem.
- Slobodno crtanje uz izbor boje i debljine poteza.
- Apple Pencil podešavanja na kompatibilnom iPad-u: crtanje samo olovkom, odziv na pritisak, osetljivost i širenje poteza nagibom.
- Gumica za cele poteze, sa undo/redo podrškom za ceo gest brisanja.
- Lasso selekcija, pomeranje, dupliranje i brisanje grupe poteza, uz grupni undo/redo.
- Podloge bez vodiča, sa linijama, mrežom ili tačkicama; razmak se pamti uz crtež.
- Pomeranje platna sa inercijom, zumiranje i zaključavanje pomeranja papira.
- Undo/redo, centriranje crteža i uklapanje celog sadržaja u prikaz.
- Focus režim sa skrivenom alatnom trakom.
- Dve površine papira: **Quiet Paper** i **Electric Paper**, sa svetlim i tamnim izgledom.
- Lokalno čuvanje sesije, automatsko učitavanje i podesivo automatsko čuvanje.
- Izvoz vidljivog dela ili celog crteža u **PDF** ili **PNG** i deljenje kroz sistemski meni.
- Podesive margine, PNG rezolucija, providna pozadina i imenovanje izvoza. Tekstura papira može se uključiti u PNG izvoz vidljivog dela.

## Pokretanje

Potreban je Mac sa Xcode-om i instaliranim iOS SDK-om. Projekat je poslednji put uspešno kompajliran sa **Xcode 27.1**. Nema spoljnih paketnih zavisnosti.

```bash
git clone https://github.com/sgazz/InfinityPaper.git
cd InfinityPaper
open InfinityPaper.xcodeproj
```

1. U Xcode-u izaberite scheme **InfinityPaper**.
2. Izaberite iPhone/iPad simulator sa instaliranim runtime-om ili povezani uređaj.
3. Za fizički uređaj podesite svoj **Team** u **Signing & Capabilities**; po potrebi promenite bundle identifier.
4. Pokrenite aplikaciju komandom **Product → Run** (`⌘R`).

Deployment target aplikacije koristi `$(RECOMMENDED_IPHONEOS_DEPLOYMENT_TARGET)` i zavisi od izabranog Xcode-a. Test target trenutno zahteva **iOS 18.6 ili noviji**. Dostupne simulatore možete proveriti komandom `xcrun simctl list devices available`.

### Kompajliranje bez pokretanja

Iz korena repozitorijuma:

```bash
xcodebuild \
  -project InfinityPaper.xcodeproj \
  -scheme InfinityPaper \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

Ova komanda kompajlira aplikaciju i testove; ne pokreće ih i ne pravi potpisanu aplikaciju za instaliranje na uređaj.

## Korišćenje

| Radnja | Kontrola |
| --- | --- |
| Crtanje | Jedan dodir i prevlačenje |
| Izbor alata | Meni sa ikonom aktivnog alata: Pen, Whole-stroke eraser ili Lasso selection |
| Brisanje poteza | Izabrati Whole-stroke eraser, pa dodirnuti potez ili prevući preko njega |
| Selekcija | Izabrati Lasso selection i povući petlju oko poteza; kratak dodir bira najbliži gornji potez |
| Pomeranje izbora | Prevlačenje jednim prstom unutar isprekidanog okvira |
| Dupliranje / brisanje izbora | Meni aktivnog alata → Duplicate selection / Delete selection |
| Poništavanje izbora | Meni aktivnog alata → Deselect; izbor olovke ili gumice takođe uklanja okvir |
| Biblioteka | Meni „… → My drawings“; dugme + kreira crtež, a meni … upravlja postojećim radom |
| Pomeranje papira | Prevlačenje sa dva prsta; jedan prst kada je uključen Pencil-only režim |
| Zumiranje | Pinch gest ili komande alatne trake |
| Vraćanje prikaza | Dvostruki dodir sa dva prsta resetuje zum i centrira sadržaj |
| Boja, debljina, undo/redo | Plutajuća alatna traka |
| Centriranje, fit, novi prostor i focus | Dodatne komande alatne trake |
| Papir, izvoz i čuvanje | Settings |

## Čuvanje podataka

Svaki crtež ima zaseban direktorijum `Documents/Drawings/<UUID>/` u sandboxu aplikacije:

- `document.json` — identitet, naziv i datum kreiranja.
- `session.json` — potezi, položaj/zum prikaza i podloga sa razmakom vodiča.

Postojeći `Documents/session.json` automatski se prenosi u prvi crtež biblioteke, uz očuvan original. Migracija se ne ponavlja, čak ni nakon brisanja prenetog crteža. Oštećen sadržaj ostaje sačuvan i označen nedostupnim pregledom; otvaranje zahteva validne podatke.

**On background** čuva rad pri napuštanju aktivnog stanja; **Periodic** dodatno čuva na svakih 60 sekundi. Povratak u biblioteku preko menija „… → My drawings“ uvek čeka završetak čuvanja. Ako čuvanje ne uspe, editor ostaje otvoren sa porukom o grešci.

Opcija **Reopen last drawing on launch** određuje da li se pri pokretanju ponovo otvara poslednji aktivni crtež. **Clear** prazni samo trenutni crtež, dok **New drawing** čuva tekući rad i otvara zaseban novi dokument. Brisanje iz biblioteke zahteva potvrdu i uklanja ceo izabrani dokument.

Podešavanja se čuvaju u `UserDefaults`. Disk operacije koriste zajednički serijski pozadinski red. Pre zamene starog formata pravi se rezervna kopija, a neuspešno učitavanje kroz session store pravi recovery kopiju.

Podloga se podešava u **Settings → Paper → Guides**. Opcija **Include paper guides** određuje da li vodiči ulaze u PDF/PNG izvoz, uključujući PNG sa providnom pozadinom. Pri veoma malom zumu ili izvozu velikog crteža vodiči se proređuju da broj nacrtanih elemenata ostane ograničen.

## Rad sa selekcijom

Lasso bira cele poteze čija vidljiva središnja putanja ulazi u petlju ili prelazi njenu granicu. Prevlačenje izvan postojećeg okvira započinje novi izbor; dva prsta i dalje služe za pomeranje papira i zumiranje. Prelazak na navigacioni gest otkazuje nezavršen pregled pomeraja.

Jedan završen pomeraj, dupliranje ili brisanje grupe predstavlja jedan undo korak. Duplikati dobijaju zasebne identitete i pomeraju se malo udesno i nadole. Pomeranje cele grupe ograničeno je tako da potezi ostanu unutar podržanih koordinata.

Okvir i lasso su privremeni i ne ulaze u izvoz niti u sačuvani dokument. Završene izmene poteza se čuvaju normalno. Pri odlasku u pozadinu, povratku u biblioteku ili izvozu aktivni pomeraj se završava pre pravljenja snimka dokumenta.

## Apple Pencil

Na iPad-u otvoriti **Settings → Apple Pencil**:

- **Draw only with Apple Pencil** razdvaja crtanje od navigacije: Pencil crta, briše ili bira poteze, a jedan prst pomera papir. Dva prsta i dalje zumiraju. Isključiti zaključavanje papira za pomeranje.
- **Pressure changes line width** uključuje promenu debljine pritiskom. Slider **Pressure sensitivity** podešava odziv na slabiji pritisak.
- **Tilt widens strokes** širi potez pri naginjanju olovke.

Početno je crtanje prstom omogućeno, pritisak uključen, a nagib isključen. iPhone zadržava crtanje prstom i ne prikazuje Pencil sekciju. Efekti zavise od podataka koje olovka i uređaj šalju.

Profil debljine pamti se uz uzorke poteza i ostaje očuvan pri čuvanju, selekciji, kopiranju, undo/redo i izvozu. Promena podešavanja utiče na nove poteze. Stari crteži bez profila ostaju nepromenjeni; nije potrebno ponovo ih uvoziti.

## Referentna slika

Otvoriti **Settings → Reference image → Import reference image**. Slika se bira kroz **Photos** ili **Files** i postavlja iza poteza i vodiča papira. Zaseban panel omogućava pregled položaja, pomeranje strelicama, centriranje, uklapanje u trenutni pogled, veličinu, providnost, skrivanje i uklanjanje slike.

**Done** primenjuje sve izmene panela kao jedan undo korak; **Cancel** čuva prethodno stanje. Nova slika zamenjuje prethodnu tek kada se promene potvrde. Referenca je zaključana: gumica i lasso rade samo sa potezima. Clear uklanja i poteze i referencu nakon potvrde.

U **Settings → Export & Share → Include reference image** bira se da li vidljiva slika ulazi u PDF/PNG. To važi i za PNG sa providnom pozadinom. Pri izvozu celog crteža granice uključuju sliku samo ako je uključena u izvoz, vidljiva i nije potpuno providna.

Uvoz pravi lokalnu PNG kopiju sa ispravljenom orijentacijom i očuvanom providnošću, do 2048 piksela po strani i 8 MB. Ako je potrebno, slika se dodatno smanjuje na 1024 piksela. Izvori preko 100 megapiksela ili 40.000 piksela po strani odbijaju se. Višekadrovski formati koriste prvi kadar.

Kopija i položaj čuvaju se u session.json dokumenta; nije potrebna trajna veza sa originalnom fotografijom/datotekom. Dupliranje crteža zadržava sliku, a biblioteka koristi male preglede do 256 piksela. Stari crteži bez referenci normalno se učitavaju.

## Struktura projekta

| Fajlovi | Odgovornost |
| --- | --- |
| `InfinityPaperApp.swift`, `ContentView.swift` | Pokretanje, početni ekran i povezivanje SwiftUI-ja sa canvasom |
| `DrawingLibraryView.swift`, `DrawingLibraryStore.swift` | Biblioteka, pregledi, zasebni dokumenti i migracija stare sesije |
| `ReferenceImage.swift`, `CanvasReferenceRenderer.swift` | Model, ograničenja uvoza, trajnost i crtanje referentnog sloja |
| `ReferencePhotoPicker.swift`, `ReferenceImageSettingsView.swift` | Izbor iz Photos/Files i podešavanje slike |
| `CanvasInputController.swift`, `PencilResponse.swift` | Razdvajanje Pencil/finger dodira, pritisak, nagib i profil debljine |
| `CanvasSelectionController.swift`, `CanvasSelectionGeometry.swift`, `CanvasSelectionRenderer.swift` | Lasso, prolazni pregled pomeranja i prikaz izbora |
| `CanvasStrokeGeometry.swift`, `CanvasStrokeHitTesting.swift` | Zajednička putanja crtanja i geometrija gumice |
| `PaperPattern.swift`, `PaperPatternRenderer.swift` | Podloge sa linijama, mrežom i tačkicama |
| `TapeCanvasUIView.swift` | Dodiri, gestovi, UIKit prikaz i koordinacija canvas komponenti |
| `CanvasFloatingToolbar.swift`, `SettingsView.swift` | Alatna traka, broker stanja i podešavanja |
| `CanvasViewport.swift`, `CanvasGeometry.swift` | Koordinatne transformacije i zajednička geometrijska pravila |
| `CanvasRenderer.swift`, `CanvasRenderState.swift` | Priprema i crtanje poteza, tekstura i keširanje |
| `CanvasMotionController.swift` | Inercija i raspoređivanje automatskog pomeranja |
| `TapeCanvasSessionState.swift` | Potezi, prostorni indeks, undo/redo i revizije sesije |
| `CanvasPersistenceCoordinator.swift`, `CanvasSessionManager.swift` | Koordinacija čuvanja/učitavanja, autosave i životni ciklus |
| `SessionModel.swift`, `SessionFileStore.swift` | JSON modeli, validacija i rad sa datotekama |
| `CanvasExportManager.swift` | PDF/PNG izvoz |
| `AppSettings.swift`, `CanvasBrush.swift`, `PaperSurface.swift` | Podešavanja, paleta i izgled papira |
| `InfinityPaperTests/` | XCTest testovi geometrije, čuvanja, podešavanja i životnog ciklusa |

Swift izvorni fajlovi iz tabele nalaze se u direktorijumu `InfinityPaper/`.

## Testovi

Repozitorijum sadrži **79 XCTest test metoda**. U Xcode-u izaberite scheme **InfinityPaper**, kompatibilni simulator ili uređaj i pokrenite **Product → Test** (`⌘U`). Test plan je `InfinityPaper.xctestplan`.

Za pokretanje iz terminala, prvo pronađite UDID dostupnog simulatora, pa zamenite `SIMULATOR_UDID` u komandi:

```bash
xcodebuild \
  -project InfinityPaper.xcodeproj \
  -scheme InfinityPaper \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  test
```

Poslednja provera: aplikacija i svih 79 test metoda uspešno su kompajlirani za iOS. Dodatno je prošlo 74 testova logike u lokalnom macOS test okruženju sa UIKit zamenskim tipovima; to pomoćno okruženje nije deo repozitorijuma. Izvršavanje iOS testova i vizuelna provera zahtevaju dostupan simulator runtime ili uređaj.
