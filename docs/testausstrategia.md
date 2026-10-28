# Pesutupa – testausstrategia ja testisuunnitelma

| | |
|---|---|
| Versio | 0.1 (luonnos) |
| Päivämäärä | 28.10.2026 |
| Tila | Katselmoitavana |
| Laatija | Testiautomaatiokonsultti |
| Viitekehys | ISTQB CTFL v4.0, rakenne ISO/IEC/IEEE 29119-3 (testisuunnitelma) |

---

## 1. Johdanto

### 1.1 Tarkoitus

Dokumentti kuvaa pesutuvan varausjärjestelmän testausstrategian (organisaatio- ja projektitason periaatteet) ja testisuunnitelman (mitä testataan, miten, missä, kuka ja millä kriteereillä). ISTQB:n mukaisesti testauksen tavoitteet ovat:

- arvioida, täyttääkö järjestelmä vaatimukset ja hyväksymiskriteerit (CLAUDE.md, kohta 12)
- löytää vikoja ja vähentää tuotannon laaturiskiä
- tuottaa sidosryhmille (taloyhtiö, ylläpitäjä) tietoa julkaisupäätöksen tueksi
- varmistaa, ettei muutos riko aiemmin toiminutta (regressio)

### 1.2 Testauksen kohde

Suomenkielinen, mobiiliystävällinen pesutuvan varausjärjestelmä:

| Osa | Teknologia |
|---|---|
| Käyttöliittymä | Staattinen HTML/CSS/JS (ES-moduulit), GitHub Pages |
| Rajapinta | Supabase PostgREST (RPC-funktiot `public`-skeemassa) |
| Tietokanta | Supabase PostgreSQL, taulut `app_private`-skeemassa, RLS päällä |
| Tunnistautuminen | Yhteinen salasana (bcrypt), istuntotunniste 30 vrk (SHA-256-tiiviste kannassa) |
| Julkaisu | GitHub Actions → GitHub Pages |

### 1.3 Testiperusta (test basis)

- `CLAUDE.md`: vaatimukset, varaussäännöt, käyttöohjeet, hyväksymiskriteerit
- `README.md`: tietoturvamalli, käyttöönotto, ylläpito
- Tietokantamigraatiot `supabase/migrations/*.sql` (liiketoimintasäännöt on toteutettu kannassa)
- Käyttöliittymän lähdekoodi `index.html`, `js/*.js`, `css/styles.css`

### 1.4 Termit

| Termi | Merkitys tässä projektissa |
|---|---|
| Istunto | Kirjautumisen tuottama 64 merkin tunniste, tallennettu selaimen localStorageen |
| Laite | Pesukone tai kuivuri (`devices`-taulu) |
| Aukioloaika | Varattava aika klo 8–22 Suomen aikaa (`settings`) |
| Tuotantokanta | Asukkaiden käytössä oleva Supabase-projekti |
| Testikanta | Paikallinen Docker-ympäristö (PostgreSQL 17 + PostgREST 12.2.8) |

---

## 2. Testausstrategia

### 2.1 Strategiatyyppi

Pääasiallinen strategia on **riskiperusteinen analyyttinen strategia** (ISTQB: analytical, risk-based): testauksen määrä ja syvyys mitoitetaan tuoteriskien mukaan (luku 3). Sitä täydennetään:

- **Metodisella strategialla**: OWASP-tyyppinen tarkistuslista tietoturvalle ja WCAG 2.1 AA saavutettavuudelle.
- **Regressiota välttävällä strategialla**: automatisoidut regressiotestit ajetaan jokaisesta muutoksesta.
- **Reaktiivisella strategialla**: tutkiva testaus (exploratory) mobiililaitteilla julkaisujen yhteydessä.

### 2.2 Ohjaavat periaatteet

1. **Tuotantodataa ei muuteta.** Tuotantokantaan ei kirjoiteta testejä varten mitään eikä sieltä poisteta mitään. Tuotantoa vastaan ajetaan vain kirjoittamattomia tarkistuksia. Kirjoittavat testit ajetaan testikannassa tai erillisessä testiprojektissa.
2. **Liiketoimintasäännöt testataan siellä, missä ne on toteutettu.** Kesto, päällekkäisyys, aukioloaika ja valtuutus toteutetaan tietokannassa, joten niiden pääasiallinen testaus tehdään tietokanta- ja API-tasolla, ei käyttöliittymän kautta.
3. **Testipyramidi.** Paljon nopeita tietokanta- ja API-testejä, vähemmän päästä päähän -testejä (E2E), vähän manuaalista testausta.
4. **Shift left.** Staattinen testaus (katselmointi, linttaus, Supabase Security Advisor) tehdään ennen kuin migraatio ajetaan tuotantoon.
5. **Testit ovat toistettavia.** Testit eivät saa riippua kellonajasta tai aiempien ajojen jäänteistä. Tietokantatestit ajetaan transaktiossa, joka perutaan.

### 2.3 Testitasot

| Taso (ISTQB) | Kohde | Toteutus | Ympäristö |
|---|---|---|---|
| Komponenttitestaus | Tietokantafunktiot ja rajoitteet | `tests/db/booking_rules_test.sql` (SQL, rollback) | Testikanta |
| Komponenttitestaus | JS-apufunktiot (aikalaskenta, muotoilut) | **Uusi:** yksikkötestit (Node `node:test` tai Vitest) | Kehittäjän kone, CI |
| Komponenttien integraatiotestaus | PostgREST ↔ funktiot, oikeudet, rinnakkaisuus | `tests/api_test.mjs` | Testikanta |
| Järjestelmätestaus | Koko sovellus selaimessa | **Uusi:** Playwright E2E, mobiili- ja työpöytäkoko | Testikanta + paikallinen palvelin |
| Järjestelmäintegraatiotestaus | GitHub Pages ↔ Supabase (CORS, avaimet, konfiguraatio) | Kirjoittamaton savutesti tuotantoa vastaan | Tuotanto (vain luku) |
| Hyväksymistestaus | Hyväksymiskriteerit (CLAUDE.md 12), käyttöohjeet | Manuaalinen tarkistuslista (README 5.3), käyttäjähyväksyntä | Testiprojekti tai tuotanto (käyttäjän omat varaukset) |

### 2.4 Testityypit

| Testityyppi | Mitä | Miten |
|---|---|---|
| Toiminnallinen | Varaus, poisto, jatkaminen, listaus, kirjautuminen | DB-, API- ja E2E-testit |
| Tietoturva | RLS, piilotetut taulut, funktioiden oikeudet, istunnot, kirjautumisrajoitus, XSS, salaisuudet | DB/API-testit, OWASP-tarkistuslista, Supabase Security Advisor, salaisuusskannaus |
| Rinnakkaisuus | Samanaikaiset varaukset | API-testi: 20 rinnakkaista pyyntöä, täsmälleen 1 onnistuu |
| Käytettävyys | Selkeys pienellä näytöllä, ilmoitukset | Tutkiva testaus, käyttäjäpalaute |
| Saavutettavuus | WCAG 2.1 AA: kontrasti, näppäimistö, ruudunlukija, tekstimuotoiset tilat | **Uusi:** axe-core Playwrightissa + manuaalinen ruudunlukijatesti |
| Yhteensopivuus | iOS Safari, Android Chrome, työpöytä Chrome/Firefox/Edge | Playwright (Chromium, WebKit, Firefox) + oikeat puhelimet |
| Suorituskyky | Vasteajat, Supabase-ilmaistason rajat | Kevyt mittaus (ei kuormitustestausta, käyttäjiä kymmeniä) |
| Luotettavuus | Verkkokatko, vanhentunut tieto, istunnon vanheneminen | E2E verkkoa hidastaen ja katkaisten |
| Regressio | Kaikki edellä | Automatisoitu ajo CI:ssä jokaisesta muutoksesta |
| Vahvistustestaus (confirmation) | Korjatut viat | Vialle kirjoitetaan ensin testi, joka toistaa sen |

### 2.5 Automaatioperiaatteet

- Automatisoidaan kaikki, mikä on deterministinen ja toistuu jokaisessa julkaisussa: liiketoimintasäännöt, oikeudet, rinnakkaisuus ja keskeiset käyttäjäpolut.
- Ei automatisoida kertaluonteisia tai vahvasti subjektiivisia arvioita (ulkoasun miellyttävyys, ohjetekstien ymmärrettävyys).
- Aikariippuvuus hallitaan: testit asettavat aukioloajan itse ja käyttävät suhteellisia aikoja (huomenna klo 10). E2E-testeissä selaimen kello asetetaan (Playwright `page.clock`).
- Testit ajetaan CI:ssä GitHub Actionsilla. Docker-palvelut käynnistetään samalla `tests/local/docker-compose.yml`-tiedostolla kuin paikallisesti.

---

## 3. Tuoteriskianalyysi

Todennäköisyys (T) ja vaikutus (V) asteikolla 1–3. Riskitaso = T × V. Taso 6–9 = korkea, 3–4 = keskitaso, 1–2 = matala.

| # | Riski | T | V | Taso | Testauksen painotus |
|---|---|---|---|---|---|
| R1 | Samalle laitteelle syntyy päällekkäisiä varauksia (myös samanaikaisissa pyynnöissä) | 2 | 3 | 6 | DB-rajoitetestit, rinnakkaisuustesti, raja-arvot (vierekkäiset varaukset) |
| R2 | Varausdataa voi lukea, muuttaa tai poistaa ilman kirjautumista | 2 | 3 | 6 | Oikeustestit jokaiselle taululle ja funktiolle, savutesti tuotantoa vastaan |
| R3 | Migraatio rikkoo tuotannon tai hävittää dataa | 2 | 3 | 6 | Migraatioiden ajo tyhjään kantaan ja kantaan, jossa on dataa; katselmointi |
| R4 | Aikavyöhyke tai kesäaika aiheuttaa väärät ajat (UTC vs. Europe/Helsinki, 23/25 tunnin vuorokausi) | 2 | 2 | 4 | Rajatapaukset kesäajan vaihtopäivinä, selaimen aikavyöhykkeen vaihto |
| R5 | Käyttöliittymä näyttää vanhentuneen tilanteen varmana | 2 | 2 | 4 | E2E verkkokatkolla, vanhentuneen tiedon varoitus |
| R6 | Säännöt (3 h, 30 min jaksot, klo 8–22, 90 vrk) eivät toteudu | 2 | 2 | 4 | Ekvivalenssiluokat ja raja-arvot DB-tasolla |
| R7 | Salasanan arvaus (lyhyt, vähintään 5 merkkiä) | 2 | 2 | 4 | Kirjautumisrajoituksen testit (10/asiakas, 200/globaali, 15 min) |
| R8 | Sovellus ei toimi tai on hankala puhelimella | 2 | 2 | 4 | E2E 375 px, oikeat laitteet, tutkiva testaus |
| R9 | XSS tai muu syötteen injektio asunnon numerossa | 1 | 3 | 3 | Syötteen validointitestit, tarkistus että käyttöliittymä käyttää textContentia |
| R10 | Salaisuus (service_role) päätyy julkiseen repoon tai sivustolle | 1 | 3 | 3 | Salaisuusskannaus CI:ssä, julkaisutyönkulun avaintarkistus |
| R11 | Saavutettavuus puutteellinen | 2 | 1 | 2 | axe-core, näppäimistötesti |
| R12 | Kuka tahansa voi poistaa minkä tahansa varauksen (tietoinen päätös) | 3 | 1 | 3 | Vahvistuskyselyn testi. Riski hyväksytty, ei teknistä estoa |
| R13 | Supabasen ilmaistaso pysäyttää projektin käyttämättömyyden vuoksi | 2 | 2 | 4 | Ei testattava; seuranta ja ohje ylläpitäjälle |

---

## 4. Testisuunnitelma

### 4.1 Laajuus

**Testataan**

- Kirjautuminen, istunnon uusiminen ja uloskirjautuminen, kirjautumisrajoitus
- Varauksen luonti, listaus, poisto ja jatkaminen kaikkine sääntöineen
- Kalenterinäkymä: päivän vaihto, laitesuodatin, vapaat ajat, tilatekstit, Omat varaukset
- Virhe- ja lataustilat, vanhentuneen tiedon varoitus, automaattinen päivitys
- Tietokannan käyttöoikeudet ja RLS
- Julkaisutyönkulku (konfiguraation generointi, avaintarkistus)
- Käyttöohjeiden näkyvyys ja sisältö (9 sääntöä muuttamattomina)

**Ei testata (rajaukset)**

- Supabase- ja GitHub-palveluiden sisäinen toiminta ja saatavuus
- 15 minuutin sääntö teknisenä toimintona: sitä ei ole toteutettu (CLAUDE.md 6), joten vain ohjeteksti tarkistetaan
- Kuormitustestaus suurilla käyttäjämäärillä (käyttäjiä kymmeniä)
- Vanhat selaimet ilman ES-moduulitukea

### 4.2 Testitekniikat

| Tekniikka (ISTQB) | Kohde | Esimerkit |
|---|---|---|
| Ekvivalenssiluokat | Kesto, asunnon numero, laite, salasana | Kelvollinen 30–180 min / liian pitkä / nolla / negatiivinen; asunto "12", "A 12" / "abc" / tyhjä |
| Raja-arvoanalyysi | Kesto, aukioloaika, varaushorisontti, salasanan pituus, rajoitus | 30/180 (ok), 0/210 (hylätty); alku 7.30 (hylätty) / 8.00 (ok); loppu 22.00 (ok) / 22.30 (hylätty); 90/91 vrk; 4/5 merkkiä; 9./10. virheellinen kirjautuminen |
| Päätöstaulu | Vuoron jatkaminen | Oma istunto × viimeinen tunti × seuraava tunti vapaa × ei ylitä klo 22 → sallittu vain, kun kaikki ehdot täyttyvät |
| Tilasiirtymätestaus | Istunto, varaus | Istunto: ei → voimassa → uusittu / vanhentunut / uloskirjattu. Varaus: tuleva → käynnissä → päättynyt / poistettu |
| Käyttötapaustestaus | Asukkaan polut | Kirjaudu → valitse päivä → varaa → näe varaus → poista |
| Kokemusperusteinen | Mobiilikäyttö, virhetilanteet | Tutkiva testaus aikarajatuin sessioin (esim. 45 min, testikirjan avulla), virheiden arvaus |
| Tarkistuslista | Tietoturva, saavutettavuus | OWASP Top 10 soveltuvin osin, WCAG 2.1 AA |

### 4.3 Testiympäristöt

| Ympäristö | Käyttö | Saako kirjoittaa? |
|---|---|---|
| **Testikanta (Docker)** | DB-, API- ja E2E-testit, CI | Kyllä. Luodaan joka ajossa alusta (`--fresh`) |
| **Testiprojekti (Supabase, ehdotus)** | Migraatioiden kokeilu oikeassa Supabasessa ennen tuotantoa, hyväksymistestaus | Kyllä. Erillinen ilmaistason projekti, ei asukasdataa |
| **Tuotanto** | Savutesti julkaisun jälkeen | **Ei.** Vain kirjoittamattomat tarkistukset (`tests/api_test.mjs` ilman localhostia) |

Selaimet: Chromium, WebKit (Safari-moottori) ja Firefox Playwrightilla. Lisäksi vähintään yksi oikea iPhone ja yksi Android-puhelin hyväksymistestauksessa.

### 4.4 Testidata

- Testikanta alustetaan migraatioilla ja testisalasanalla `testisalasana-123` (vain paikallinen).
- Testit luovat tarvitsemansa varaukset itse suhteellisin ajoin. Ne eivät oleta, että kannassa on valmiiksi dataa.
- Asukkaiden tietoja ei kopioida testiympäristöihin. Data ei ole henkilöityä, mutta periaate pidetään.
- Tuotannon oikeaa salasanaa ei tallenneta testeihin, CI:hin eikä dokumentaatioon.

### 4.5 Testauksen suoritus ja automaatio

| Vaihe | Laukaisija | Sisältö | Kesto (arvio) |
|---|---|---|---|
| Kehittäjän ajo | Ennen committia | DB- ja API-testit | < 1 min |
| CI (pull request / push) | GitHub Actions | Linttaus, yksikkötestit, DB, API, E2E, axe, salaisuusskannaus | 3–5 min |
| Julkaisun jälkeen | Pages-julkaisun päätyttyä | Kirjoittamaton savutesti tuotantoa vastaan + sivun latautuminen | < 1 min |
| Ennen migraatiota tuotantoon | Käsin | Migraatio testiprojektiin, regressio, katselmointi | 30 min |
| Hyväksymistestaus | Merkittävä muutos | Tarkistuslista (README 5.3) puhelimella ja tietokoneella | 30 min |

---

## 5. Aloitus- ja lopetuskriteerit

### 5.1 Aloituskriteerit (entry criteria)

- Muutos on versionhallinnassa ja kuvattu (commit-viesti, tarvittaessa CLAUDE.md-päätös)
- Migraatiot ajautuvat virheettä tyhjään testikantaan
- Testiympäristö käynnistyy (`docker compose up --wait`)
- Muutoksen vaatimukset ovat selvät ja testattavat

### 5.2 Lopetuskriteerit (exit criteria) julkaisulle

- Kaikki automatisoidut testit läpäisty (DB, API, E2E, axe ilman vakavia löydöksiä)
- Korkean riskitason (R1–R3) testit läpäisty ilman poikkeuksia
- Ei avoimia vakavuusluokan Kriittinen tai Korkea vikoja
- Hyväksymiskriteerit (CLAUDE.md 12) on todennettu tarkistuslistalla
- Tuotannon savutesti läpäisty julkaisun jälkeen

### 5.3 Keskeytys- ja jatkamiskriteerit

- **Keskeytys:** testikanta ei käynnisty, migraatio epäonnistuu tai savutesti näyttää, että taulut ovat luettavissa tuotannossa. Tietoturvalöydös tuotannossa johtaa julkaisun peruutukseen.
- **Jatkaminen:** syy on korjattu ja vahvistustesti läpäisty.

---

## 6. Jäljitettävyys ja nykyinen kattavuus

| Vaatimus (CLAUDE.md) | Nykyiset testit | Kattavuus | Aukko / toimenpide |
|---|---|---|---|
| Kirjautuminen yhteisellä salasanalla | DB, API | Hyvä | E2E-polku puuttuu |
| Istunto 30 vrk, uusiminen | DB | Hyvä | Vanhenemisen käsittely käyttöliittymässä (E2E) |
| Kirjautumisrajoitus | DB | Hyvä | Globaali raja (200) ei testattu |
| Molempien laitteiden varaukset näkyvät | DB, API | Hyvä | E2E |
| Asunto ja varausaika erillisissä sarakkeissa | Manuaalinen | Heikko | E2E-tarkistus taulukon rakenteesta |
| Varauksen teko ja poisto | DB, API | Hyvä | E2E-polku, vahvistuskysely |
| Päällekkäisyyksien esto | DB, API (20 rinnakkaista) | Hyvä | – |
| Enimmäiskesto 3 h, 30 min jaksot | DB | Hyvä | – |
| Vierekkäiset varaukset yhteensä 3 h | DB | Osittainen | Lisää: vierekkäisyys molempiin suuntiin, eri laitteet |
| Varattava aika klo 8–22 | DB | Hyvä | Käyttöliittymän alkamisaikalista (E2E) |
| Jatkaminen tunti kerrallaan | DB | Hyvä | Päätöstaulun kaikki yhdistelmät, rajana klo 22 |
| Ajantasaisuus (30 s päivitys) | Manuaalinen | Heikko | E2E kahdella selainkontekstilla |
| Vanhentunutta tietoa ei näytetä varmana | Manuaalinen | Heikko | E2E verkkokatkolla |
| Käyttöohjeet | Manuaalinen | Heikko | E2E: 9 ohjetta näkyvät muuttumattomina |
| Toimii puhelimella ja tietokoneella | Manuaalinen | Heikko | E2E 375 px + WebKit, oikeat laitteet |
| Tietokannan käyttöoikeudet | DB, API, tuotannon savutesti | Hyvä | – |
| Julkaistavissa ohjeiden avulla | Manuaalinen | Osittainen | Julkaisutyönkulun avaintarkistuksen testi |
| Aikavyöhyke ja kesäaika | – | Puuttuu | DB- ja E2E-testit kesäajan vaihtopäivälle |
| Saavutettavuus | – | Puuttuu | axe-core + manuaalinen |

Suurimmat aukot: **käyttöliittymän automaatio puuttuu kokonaan**, **testejä ei ajeta CI:ssä** eikä **ole erillistä Supabase-testiprojektia**.

---

## 7. Testitapausesimerkit

| ID | Taso | Tekniikka | Esiehto | Vaiheet | Odotettu tulos | Riski |
|---|---|---|---|---|---|---|
| TC-DB-01 | Komponentti | Raja-arvo | Kirjautunut istunto | Varaa pesukone huomenna 10.00, kesto 180 min | Onnistuu | R6 |
| TC-DB-02 | Komponentti | Raja-arvo | Kuten yllä | Kesto 210 min | Hylätään (P0001) | R6 |
| TC-DB-03 | Komponentti | Raja-arvo | Aukiolo 8–22 | Alku 7.30, kesto 60 min | Hylätään: "Pesutupaa voi varata vain klo 8.00–22.00." | R6 |
| TC-DB-04 | Komponentti | Raja-arvo | Aukiolo 8–22 | Alku 20.30, kesto 90 min (loppu 22.00) | Onnistuu | R6 |
| TC-DB-05 | Komponentti | Päätöstaulu | Oma käynnissä oleva varaus, viimeinen tunti, seuraava tunti varattu | Jatka vuoroa | Hylätään (23P01) | R1 |
| TC-API-01 | Integraatio | Rinnakkaisuus | Kaksi istuntoa | 20 samanaikaista varausta samaan aikaan | Täsmälleen 1 onnistuu, 19 saa 23P01 | R1 |
| TC-API-02 | Integraatio | Tarkistuslista | Ei istuntoa | `GET /rest/v1/bookings` | 401/404, ei dataa | R2 |
| TC-E2E-01 | Järjestelmä | Käyttötapaus | Testikanta, 375 px | Kirjaudu → seuraava päivä → varaa kuivuri 18.00 1 h asunnolle 9 | Onnistumisilmoitus, rivi "9 / 18.00–19.00" kuivurin taulukossa ja Omissa varauksissa | R8 |
| TC-E2E-02 | Järjestelmä | Käyttötapaus | Kaksi selainkontekstia | A varaa, B odottaa enintään 35 s | B näkee varauksen ilman sivun päivitystä | R5 |
| TC-E2E-03 | Järjestelmä | Virheen arvaus | Varaus näkyy | Katkaise verkko, odota päivitystä | Keltainen varoitus "voi olla vanhentunut", ei vapaita aikoja varmana | R5 |
| TC-E2E-04 | Järjestelmä | Tilasiirtymä | Istunto poistettu kannasta | Tee mikä tahansa toiminto | Ohjataan kirjautumiseen, ilmoitus "Istunto on vanhentunut" | R2 |
| TC-E2E-05 | Järjestelmä | Raja-arvo | Selaimen kello 28.3.2027 (kesäajan alku) | Avaa päivä, varaa 8.00–9.00 | Ajat näkyvät oikein Suomen aikana | R4 |
| TC-SEC-01 | Järjestelmä | Tarkistuslista | Kirjautunut | Asunnon numero `<img src=x onerror=alert(1)>` | Hylätään validoinnissa, ei suoritettavaa koodia | R9 |
| TC-PROD-01 | Järjestelmäintegraatio | Savutesti | Julkaisu tehty | `node tests/api_test.mjs` tuotannon osoitteella | 13 tarkistusta läpi, kantaan ei kirjoiteta | R2 |

---

## 8. Organisointi

### 8.1 Roolit

| Rooli | Vastuu |
|---|---|
| Testiautomaatiokonsultti | Strategia, suunnitelma, automaatiokehys, CI, raportointi |
| Kehittäjä | Komponenttitestit, vikojen korjaus, vahvistustestit |
| Ylläpitäjä (taloyhtiö) | Migraatioiden ajo tuotantoon, salasanan hallinta, hyväksyntä |
| Asukasedustaja | Hyväksymistestaus puhelimella, palaute käytettävyydestä |

### 8.2 Työkalut

| Tarve | Työkalu |
|---|---|
| Tietokantatestit | psql + SQL-testit (vaihtoehto: pgTAP) |
| API-testit | Node.js (`fetch`) |
| E2E ja saavutettavuus | Playwright + @axe-core/playwright |
| Yksikkötestit | `node:test` tai Vitest |
| CI | GitHub Actions |
| Salaisuusskannaus | gitleaks tai GitHubin secret scanning |
| Staattinen analyysi | ESLint, Supabase Security Advisor / Database Linter |
| Vianhallinta | GitHub Issues (tunnisteet: vakavuus, prioriteetti, riski-ID) |

### 8.3 Aikataulu (ehdotus)

| Vaihe | Tehtävät | Kesto |
|---|---|---|
| 1 | Suunnitelman katselmointi, testiprojektin perustaminen Supabaseen | 1 pv |
| 2 | Nykyisten DB- ja API-testien ajo CI:ssä | 1 pv |
| 3 | Playwright-kehys, keskeiset E2E-polut (TC-E2E-01…04), axe | 2–3 pv |
| 4 | Aukkojen täydennys: kesäaika, globaali rajoitus, jatkamisen päätöstaulu | 1–2 pv |
| 5 | Julkaisun jälkeinen savutesti CI:hin, hyväksymistestaus | 1 pv |

### 8.4 Poikkeamien hallinta

Vikaraportti (ISTQB): tunniste, otsikko, ympäristö ja versio (commit), toistovaiheet, odotettu ja havaittu tulos, vakavuus, prioriteetti, liitteet (kuvakaappaus, Playwright-trace), riski-ID.

| Vakavuus | Kuvaus | Esimerkki |
|---|---|---|
| Kriittinen | Tietoturva tai datan eheys vaarantuu | Päällekkäinen varaus syntyy, taulu luettavissa ilman kirjautumista |
| Korkea | Keskeinen toiminto ei toimi | Varausta ei voi tehdä puhelimella |
| Keskitaso | Toiminto toimii puutteellisesti | Väärä virheilmoitus |
| Matala | Kosmeettinen | Asettelu kapealla näytöllä |

### 8.5 Raportointi ja mittarit

- **Testin edistymisraportti** jokaisesta CI-ajosta (GitHub Actions -yhteenveto, Playwright HTML-raportti).
- **Testin loppuraportti** merkittävän julkaisun jälkeen: mitä testattiin, poikkeamat lopetuskriteereistä, avoimet viat, jäännösriski.
- Mittarit:
  - läpäisyprosentti
  - vaatimuskattavuus (luvun 6 taulukko)
  - riskikattavuus (R1–R13)
  - avoimet viat vakavuuksittain
  - testien ajoaika
  - epävakaiden (flaky) testien määrä

---

## 9. Projektiriskit, oletukset ja avoimet kysymykset

### 9.1 Projektiriskit

| Riski | Vaikutus | Hallinta |
|---|---|---|
| Ei erillistä testiprojektia Supabasessa | Migraatiot kokeillaan vain Dockerissa, joka eroaa Supabasesta (roolit, laajennukset) | Perustetaan ilmainen testiprojekti |
| Aikariippuvat testit voivat olla epävakaita (esim. ajo lähellä keskiyötä) | Väärät hälytykset | Kello mockataan E2E:ssä, DB-testit käyttävät suhteellisia aikoja |
| Tuotantodataa ei saa käyttää | Oikean käytön ongelmat jäävät huomaamatta | Hyväksymistestaus oikeilla laitteilla, käyttäjäpalautekanava |
| Pieni projekti, vähän resursseja | Testauksen ylläpito jää | Pidetään testit kevyinä ja CI:ssä automaattisina |

### 9.2 Oletukset

- Käyttäjiä on kymmeniä, samanaikaisia muutamia.
- Data ei ole henkilöityä (asunnon numero ja ajat).
- Taloyhtiön säännöt (käyttöohjeet) ovat annettuja eikä testaus muuta niitä.

### 9.3 Avoimet kysymykset sidosryhmille

1. Saako Supabaseen perustaa erillisen testiprojektin?
2. Kuka tekee hyväksymistestauksen ja millä laitteilla?
3. Hyväksytäänkö tietoisesti riski, että kuka tahansa voi poistaa minkä tahansa varauksen (R12)?
4. Tarvitaanko saavutettavuudelle muodollinen taso (esim. WCAG 2.1 AA)?
5. Ajetaanko tuotannon savutesti automaattisesti jokaisen julkaisun jälkeen?
