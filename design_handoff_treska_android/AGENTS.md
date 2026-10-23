# Upute za agenta

Gradiš Android aplikaciju **Treska** (ZET tramvaji i autobusi uživo).
1. Pročitaj `README.md` u cijelosti. To je specifikacija dizajna.
2. Otvori `reference/Treska v2.dc.html` u browseru (uz `support.js`) da vidiš ponašanje.
3. Radi u Kotlin + Jetpack Compose + Material 3. Kartu radi s MapLibre Android ili osmdroid i OSM podlogom.
4. Backend se radi odvojeno. Napravi `TransitRepository` interface prema „Ugovor s backendom” i `FakeTransitRepository` sa simuliranim podacima dok pravi ne bude spreman.
5. Ne mijenjaj boje, tekstove ni veličine iz README-a. Svi UI tekstovi su na hrvatskom, točno kako su navedeni.
6. Ikonu postavi iz `assets/icon/` kao adaptive icon (foreground + background + monochrome).
