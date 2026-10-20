# InfinityPaper

InfinityPaper je nativna aplikacija za iPhone i iPad za crtanje i skiciranje na platnu koje se može pomerati i zumirati. Interfejs je napravljen u SwiftUI-ju, a crtanje koristi UIKit i Core Graphics.

## Mogućnosti

- Slobodno crtanje uz izbor boje i debljine poteza.
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
| Pomeranje papira | Prevlačenje sa dva prsta |
| Zumiranje | Pinch gest ili komande alatne trake |
| Vraćanje prikaza | Dvostruki dodir sa dva prsta resetuje zum i centrira sadržaj |
| Boja, debljina, undo/redo | Plutajuća alatna traka |
| Centriranje, fit, novi prostor i focus | Dodatne komande alatne trake |
| Papir, izvoz i čuvanje | Settings |

## Čuvanje podataka

Aplikacija čuva **jednu tekuću sesiju**, kao `session.json` u Documents direktorijumu svog sandboxa. Sesija sadrži poteze i položaj/zum prikaza. Podešavanja se čuvaju u `UserDefaults`.

- **On background** čuva crtež kada aplikacija napušta aktivno stanje.
- **Periodic** dodatno čuva promene na svakih 60 sekundi dok je aplikacija aktivna.
- Automatsko učitavanje poslednje sesije može se isključiti u podešavanjima.
- Brisanje platna uklanja i sačuvanu sesiju, nakon potvrde. Za zadržavanje više crteža koristite izvoz pre brisanja ili otvaranja novog prostora.
- Disk operacije se izvršavaju na serijskom pozadinskom redu. Pre zamene starog formata pravi se rezervna kopija; neuspešno učitan sadržaj čuva se kao recovery kopija.

## Struktura projekta

| Fajlovi | Odgovornost |
| --- | --- |
| `InfinityPaperApp.swift`, `ContentView.swift` | Pokretanje, početni ekran i povezivanje SwiftUI-ja sa canvasom |
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

Repozitorijum sadrži **36 XCTest test metoda**. U Xcode-u izaberite scheme **InfinityPaper**, kompatibilni simulator ili uređaj i pokrenite **Product → Test** (`⌘U`). Test plan je `InfinityPaper.xctestplan`.

Za pokretanje iz terminala, prvo pronađite UDID dostupnog simulatora, pa zamenite `SIMULATOR_UDID` u komandi:

```bash
xcodebuild \
  -project InfinityPaper.xcodeproj \
  -scheme InfinityPaper \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  test
```

Poslednja provera: aplikacija i svih 36 test metoda uspešno su kompajlirani za iOS. Dodatno su prošla 33 testa logike u lokalnom macOS test okruženju sa UIKit zamenskim tipovima; to pomoćno okruženje nije deo repozitorijuma. Izvršavanje iOS testova i vizuelna provera zahtevaju dostupan simulator runtime ili uređaj.
