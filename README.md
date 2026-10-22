# Treska

ZET Zagreb — živa karta tramvaja i autobusa te tabla dolazaka za najbliža
stajališta.

- **Karta** u gornjoj polovici: vozila u pokretu, stajališta, tvoja lokacija i
  krug od 800 m.
- **Tabla** u donjoj: 5 najbližih tramvajskih i 5 autobusnih stajališta s
  dolascima. Zeleno/amber = stvarno vrijeme (GTFS-RT), `≈` = procijenjeno iz
  kašnjenja vozila, prigušeno = vozni red.
- **Svježina podataka** je vidljiva: `◉ SADA` ili `◉ N min` uz sat u zaglavlju,
  pa se odmah vidi koliko su podaci stari.
- **Tramvaji / autobusi** prebacuju se tabovima; karta prati odabrani način.
- **Light + dark** tema (Sustav / Svijetlo / Tamno) u izborniku gore desno.
- **Postavke** (zubčanik u zaglavlju): tema, ponovno preuzimanje rasporeda i
  **ažuriranje aplikacije**. Aplikacija provjeri GitHub izdanja
  (`divanguz-alt/Treska`), pokaže što je novo, preuzme APK i otvori Androidov
  instalater. Prvi put Android traži dopuštenje "instaliraj nepoznate
  aplikacije".
- Dijagnostika je iza ikone `i` — ne zauzima ekran.

## Zašto je brža od prve verzije

Prva verzija je svake 2 sekunde na UI dretvi ponovno obrađivala cijeli vozni red
(`stop_times.txt`, 112 MB, 1.7 milijuna redaka), crtala ~700 markera s blur
filtrom i vrtjela animaciju po svakom redu. ZET 2 radi ovako:

- pozadinski izolat preuzima i parsira raspored **jednom** (≈580 ms), drži
  kompaktni indeks u `Int32List` strukturama i tamo spaja realtime podatke;
- UI dobiva samo gotov, mali snapshot (5 stajališta × 10 dolazaka + vozila);
- vozila dolaze **WebSocketom** (~10 s, isti izvor koji koristi
  zet.skoljka.org) čim ih ZET objavi, a `stop_time_update` prognoze i dalje
  stižu REST-om svakih 5 s; ako veza padne, sve se vraća na REST;
- osvježavanje je svakih 5 s, pauzira se kad je aplikacija u pozadini;
- karta i tabla se osvježavaju odvojeno, jedna animacija za cijeli ekran.

Rezultat: spajanje realtime podataka traje 2–14 ms, bez blokiranja klika i
skrolanja.

## Pokretanje

```bash
export PATH="$PATH:/Users/ivanluzar/Documents/Coding tools/flutter/bin"
flutter pub get
flutter run
```

Release APK:

```bash
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

Novo izdanje za samo-ažuriranje: digni `version` u `pubspec.yaml`, izgradi APK i
objavi GitHub Release s oznakom `vX.Y.Z` i priloženim APK-om. Aplikacija ga
pronađe sama — ništa drugo ne treba mijenjati.

Prvo pokretanje preuzima ~19 MB rasporeda (kešira se 12 h). Potreban je internet
i dopuštenje za lokaciju; bez GPS-a app radi oko Zagrebačkog glavnog kolodvora.

## Podaci

- raspored: <https://zet.hr/gtfs-scheduled/latest>
- realtime (prognoze): <https://zet.hr/gtfs-rt-protobuf>
- realtime (vozila, stream): `wss://zet.skoljka.org/ws-v4` — javni relay otvorenog
  koda za zet.skoljka.org; koristi se samo za brže pozicije, uz REST zamjenu.
- karta: OpenStreetMap (light) / Esri Dark Gray (dark)

Aplikacija nije povezana sa ZET-om.
