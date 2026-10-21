# Priprema verzije 1.5

Grana: `codex/app-store-preparation`. Izmene nisu komitovane niti pušovane.

## Završeno u projektu

- Zadržani postojeći bundle ID `Gazza.InfinityPaper`, Apple Team i verzija 1.5.
- Minimalni iOS za app eksplicitno postavljen na 18.6 za Debug i Release, umesto zavisnosti od preporuke instaliranog Xcode-a.
- Dodat `PrivacyInfo.xcprivacy`: bez praćenja i prikupljenih podataka; lokalni UserDefaults razlog CA92.1.
- Dodat prikaz politike privatnosti u Settings → About. Objavljena je nova politika zasnovana na istom tekstu, sa kontaktom i objašnjenjem GitHub Pages hostinga.
- Dodato `ITSAppUsesNonExemptEncryption = NO`: sadašnji kod ne implementira sopstvenu/neizuzetu enkripciju.
- Proverene sve app ikone: deklarisane dimenzije odgovaraju PNG fajlovima; uključena 1024×1024 ikona bez alpha kanala.
- Release arhiviranje za iOS uređaj uspešno. Manifest je u app bundle-u, minimum iOS 18.6, verzija 1.5/build 1; dSYM postoji.

Arhiva je napravljena sa `CODE_SIGNING_ALLOWED=NO`. Služi proveri pakovanja; nije potpisana IPA i nije spremna za upload. Apple validacija, provisioning i distribucioni potpis još nisu provereni.

## Pre upload-a

1. U postojećem App Store Connect zapisu za verziju 1.4 pripremiti novu verziju 1.5/build 1. Vlasnik je potvrdio da verzija 1.5 još nije uploadovana. Sačuvati postojeći bundle ID.
2. Uneti Support URL https://sgazz.github.io/infinitypaper-support/ i novu Privacy Policy adresu https://sgazz.github.io/infinitypaper-support/privacy-policy.html . Politika je objavljena u support repozitorijumu komitom 8ac6d09. Proveriti da GitHub Pages završio deployment i da stranica radi bez prijave. Privacy Policy URL je potreban i kada aplikacija ne prikuplja podatke.
3. Proveriti App Privacy izjavu prema stvarnom ponašanju ove verzije: kod ne šalje podatke developeru, nema analitike, oglasa, naloga ni spoljnih SDK-ova. Preporuka za ovu verziju: “No, we do not collect data from this app”. Postojeće objavljene izjave ne menjati bez provere šta radi trenutno dostupna 1.4.
4. Pripremiti stvarne screenshot-ove prema zasebnom planu. Nisu generisani u ovom paketu.
5. Proći aplikaciju na iPhone-u i iPad-u: toolbar, mreže izbora, pomoć i politika, oba izgleda, rotacija, veći tekst, biblioteka, čuvanje nakon ponovnog pokretanja, uvoz iz Photos/Files i PDF/PNG izvoz. Apple Pencil proveriti na fizičkom iPad-u. Nisu sve ove vizuelne/hardverske provere izvršene.
6. U Xcode-u izabrati Release / Any iOS Device → Product → Archive. U Organizer-u proveriti odgovarajući Team, Validate App i Distribute App → App Store Connect. Za upload je potreban nalog i odgovarajući potpis/profil; ne uključivati “TestFlight Internal Only” ako isti build treba i za App Review.
7. Posle obrade build-a prvo TestFlight provera; zatim odabrati build u verziji 1.5, proveriti metapodatke, starosnu ocenu, prava na sadržaj, export compliance i review kontakt. Odabrati način objavljivanja.

Ništa nije uploadovano u App Store Connect niti poslato na App Review.

## Apple izvori

- [Required reason APIs / CA92.1](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [App Privacy i javna politika](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [Screenshot specifikacije](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Upload build-ova](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
