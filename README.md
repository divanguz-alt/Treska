# Treska

ZET Zagreb — živa karta tramvaja i autobusa te tabla dolazaka za najbliža
stajališta.

- **Karta** u gornjoj polovici: vozila u pokretu, stajališta, tvoja lokacija i
  krug od 800 m.
- **Tabla** u donjoj: 5 najbližih tramvajskih i 5 autobusnih stajališta s
  dolascima. Zeleno/amber = stvarno vrijeme (GTFS-RT), prigušeno = vozni red.
- **Tramvaji / autobusi** prebacuju se tabovima; karta prati odabrani način.
- **Light + dark** tema (Sustav / Svijetlo / Tamno) u izborniku gore desno.
- Dijagnostika je iza ikone `i` — ne zauzima ekran.

## Zašto je brža od prve verzije

Prva verzija je svake 2 sekunde na UI dretvi ponovno obrađivala cijeli vozni red
(`stop_times.txt`, 112 MB, 1.7 milijuna redaka), crtala ~700 markera s blur
filtrom i vrtjela animaciju po svakom redu. ZET 2 radi ovako:

- pozadinski izolat preuzima i parsira raspored **jednom** (≈580 ms), drži
  kompaktni indeks u `Int32List` strukturama i tamo spaja realtime podatke;
- UI dobiva samo gotov, mali snapshot (5 stajališta × 10 dolazaka + vozila);
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

Prvo pokretanje preuzima ~19 MB rasporeda (kešira se 12 h). Potreban je internet
i dopuštenje za lokaciju; bez GPS-a app radi oko Zagrebačkog glavnog kolodvora.

## Podaci

- raspored: <https://zet.hr/gtfs-scheduled/latest>
- realtime: <https://zet.hr/gtfs-rt-protobuf>
- karta: CARTO (dark_all / light_all)

Aplikacija nije povezana sa ZET-om.
