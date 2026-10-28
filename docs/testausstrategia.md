# Pesutupa – testausstrategia ja testisuunnitelma

| | |
|---|---|
| Versio | 0.2 (luonnos) |
| Päivämäärä | 28.10.2026 |
| Tila | Katselmoitavana |
| Laatija | Testiautomaatiokonsultti |
| Viitekehys | ISTQB CTFL v4.0, rakenne ISO/IEC/IEEE 29119-3 (testisuunnitelma) |
| Muutokset | 0.2: rajattu toiminnalliseen testaukseen; ei-toiminnalliset testityypit rajattu pois (luku 2.5) |

---

## 1. Johdanto

### 1.1 Tarkoitus

Dokumentti kuvaa pesutuvan varausjärjestelmän **toiminnallisen testauksen** strategian ja suunnitelman: mitä testataan, miten, missä, kuka ja millä kriteereillä. ISTQB:n mukaisesti testauksen tavoitteet ovat:

- todentaa, että järjestelmä toimii vaatimusten ja hyväksymiskriteerien mukaisesti (CLAUDE.md, kohta 12)
- löytää toiminnallisia vikoja ennen kuin ne päätyvät asukkaille
- tuottaa sidosryhmille (taloyhtiö, ylläpitäjä) tietoa julkaisupäätöksen tueksi
- varmistaa, ettei muutos riko aiemmin toiminutta (regressio)

### 1.2 Testauksen kohde

Suomenkielinen, mobiiliystävällinen pesutuvan varausjärjestelmä:

| Osa | Teknologia |
|---|---|
| Käyttöliittymä | Staattinen HTML/CSS/JS (ES-moduulit), GitHub Pages |
| Rajapinta | Supabase PostgREST (RPC-funktiot) |
| Tietokanta | Supabase PostgreSQL. Liiketoimintasäännöt on toteutettu tietokantafunktioissa ja -rajoitteissa |
| Kirjautuminen | Yhteinen salasana, istunto 30 vrk |
| Julkaisu | GitHub Actions → GitHub Pages |

### 1.3 Testiperusta (test basis)

- `CLAUDE.md`: vaatimukset, varaussäännöt, käyttöohjeet, hyväksymiskriteerit
- `README.md`: käyttöönotto ja ylläpito
- Tietokantamigraatiot `supabase/migrations/*.sql`
- Käyttöliittymän lähdekoodi `index.html`, `js/*.js`

### 1.4 Termit

| Termi | Merkitys tässä projektissa |
|---|---|
| Istunto | Kirjautumisen tuottama tunniste, joka säilyy selaimessa 30 vrk |
| Laite | Pesukone tai kuivuri |
| Aukioloaika | Varattava aika klo 8–22 Suomen aikaa |
| Tuotantokanta | Asukkaiden käytössä oleva Supabase-projekti |
| Testikanta | Paikallinen Docker-ympäristö (PostgreSQL 17 + PostgREST 12.2.8) |

---

## 2. Testausstrategia

### 2.1 Strategiatyyppi

Strategia on **vaatimusperusteinen ja riskiperusteinen analyyttinen strategia** (ISTQB: analytical):

- Testit johdetaan CLAUDE.md:n toiminnallisista vaatimuksista ja varaussäännöistä (jäljitettävyys luvussa 6).
- Testauksen syvyys mitoitetaan toiminnallisten tuoteriskien mukaan (luku 3).

Sitä täydennetään:

- **Regressiota välttävällä strategialla:** automatisoidut regressiotestit ajetaan jokaisesta muutoksesta.
- **Reaktiivisella strategialla:** toiminnallinen tutkiva testaus puhelimella julkaisujen yhteydessä.

### 2.2 Ohjaavat periaatteet

1. **Tuotantodataa ei muuteta.** Tuotantokantaan ei kirjoiteta testejä varten mitään eikä sieltä poisteta mitään. Tuotantoa vastaan ajetaan vain kirjoittamattomia tarkistuksia. Kirjoittavat testit ajetaan testikannassa.
2. **Säännöt testataan siellä, missä ne on toteutettu.** Kesto, päällekkäisyys, aukioloaika ja oikeus toimintoihin toteutetaan tietokannassa, joten niiden kattava testaus tehdään tietokanta- ja API-tasolla. Käyttöliittymätesteissä varmistetaan käyttäjäpolut ja se, että säännöt näkyvät käyttäjälle oikein.
3. **Testipyramidi.** Paljon nopeita tietokanta- ja API-testejä, vähemmän päästä päähän -testejä (E2E), vähän manuaalista testausta.
4. **Shift left.** Vaatimukset ja migraatiot katselmoidaan ennen toteutusta ja ennen tuotantoon ajoa (staattinen testaus).
5. **Testit ovat toistettavia.** Testit eivät riipu kellonajasta tai aiempien ajojen jäänteistä. Tietokantatestit ajetaan transaktiossa, joka perutaan.

### 2.3 Testitasot

| Taso (ISTQB) | Kohde | Toteutus | Ympäristö |
|---|---|---|---|
| Komponenttitestaus | Tietokantafunktiot ja rajoitteet (varaussäännöt) | `tests/db/booking_rules_test.sql` (SQL, rollback) | Testikanta |
| Komponenttitestaus | JS-apufunktiot (aikalaskenta, vapaat ajat, muotoilut) | **Uusi:** yksikkötestit (`node:test` tai Vitest) | Kehittäjän kone, CI |
| Komponenttien integraatiotestaus | Rajapinta ↔ tietokantafunktiot, rinnakkaiset varaukset | `tests/api_test.mjs` | Testikanta |
| Järjestelmätestaus | Koko sovellus selaimessa, puhelimen ja tietokoneen näyttökoko | **Uusi:** Playwright E2E | Testikanta + paikallinen palvelin |
| Järjestelmäintegraatiotestaus | GitHub Pages ↔ Supabase: julkaistu sivu saa yhteyden kantaan | Kirjoittamaton savutesti | Tuotanto (vain luku) |
| Hyväksymistestaus | Hyväksymiskriteerit (CLAUDE.md 12), käyttöohjeet | Manuaalinen tarkistuslista (README 5.3) | Tuotanto, testaajan omat varaukset poistetaan heti |

### 2.4 Testityypit

| Testityyppi | Mitä |
|---|---|
| Toiminnallinen testaus | Kirjautuminen ja uloskirjautuminen, varauksen luonti, listaus, poisto ja jatkaminen, kalenterinäkymä, Omat varaukset, ilmoitukset, käyttöohjeet |
| Rinnakkaisuus (toiminnallinen sääntö) | Kun kaksi käyttäjää varaa saman ajan yhtä aikaa, vain yksi onnistuu |
| Virhe- ja poikkeustilanteiden toiminnallisuus | Selkeä virheilmoitus, epäonnistunutta varausta ei näytetä onnistuneena, vanhentunutta tilannetta ei näytetä varmana (CLAUDE.md 9) |
| Regressiotestaus | Kaikki edellä, automatisoituna |
| Vahvistustestaus (confirmation) | Korjatut viat. Vialle kirjoitetaan ensin testi, joka toistaa sen |

### 2.5 Rajattu pois: ei-toiminnallinen testaus

Seuraavat testityypit eivät kuulu tämän toimeksiannon suunnitteluun. Niiden suunnittelusta vastaa projektin muu osapuoli tai ne hyväksytään jäännösriskinä:

| Testityyppi | Huomio |
|---|---|
| Tietoturvatestaus (RLS-auditointi, tunkeutumistestaus, salasanan arvaus, syötteen injektio, salaisuuksien vuoto) | Projektissa on olemassa oikeustestejä (`tests/db`, `tests/api_test.mjs`). Ne pidetään regressiosarjassa, mutta niiden laajentaminen ei kuulu tähän suunnitelmaan |
| Suorituskyky- ja kuormitustestaus | Käyttäjiä kymmeniä |
| Saavutettavuustestaus (WCAG) | – |
| Käytettävyystestaus | Toiminnallinen hyväksymistestaus tuottaa epävirallista käytettävyyspalautetta |
| Laaja yhteensopivuustestaus (selain- ja laitematriisi) | Toiminnalliset E2E-testit ajetaan puhelimen ja tietokoneen näyttökoossa. Hyväksymiskriteeri "toimii puhelimella ja tietokoneella" todennetaan toiminnallisesti |

Kirjautuminen ja oikeus toimintoihin testataan, koska ne ovat vaatimuksissa toiminnallista käyttäytymistä:

- kirjautumaton ei pääse kalenteriin
- kuka tahansa kirjautunut voi poistaa varauksen
- vain varauksen tehnyt laite voi jatkaa vuoroa

### 2.6 Automaatioperiaatteet

- Automatisoidaan kaikki, mikä on deterministinen ja toistuu jokaisessa julkaisussa: varaussäännöt, rinnakkaisuus ja keskeiset käyttäjäpolut.
- Manuaalisesti testataan kertaluonteiset tarkistukset ja hyväksymistestaus oikealla puhelimella.
- Aikariippuvuus hallitaan:
  - Tietokantatestit asettavat aukioloajan itse ja käyttävät suhteellisia aikoja, esimerkiksi huomenna klo 10.
  - E2E-testeissä selaimen kello asetetaan (Playwright `page.clock`).
- Testit ajetaan CI:ssä GitHub Actionsilla samalla `tests/local/docker-compose.yml`-ympäristöllä kuin paikallisesti.

---

## 3. Toiminnallinen tuoteriskianalyysi

Todennäköisyys (T) ja vaikutus (V) asteikolla 1–3. Riskitaso = T × V. Taso 6–9 = korkea, 3–4 = keskitaso, 1–2 = matala.

| # | Riski | T | V | Taso | Testauksen painotus |
|---|---|---|---|---|---|
| R1 | Samalle laitteelle syntyy päällekkäisiä varauksia (myös samanaikaisissa pyynnöissä) | 2 | 3 | 6 | DB-rajoitetestit, rinnakkaisuustesti, raja-arvot (vierekkäiset varaukset) |
| R2 | Varaus näytetään onnistuneena, vaikka tallennus epäonnistui, tai poistettu varaus jää näkyviin | 2 | 3 | 6 | E2E virhetilanteilla, API-vastausten tarkistus |
| R3 | Migraatio muuttaa sääntöjä tahattomasti tai rikkoo toiminnon | 2 | 3 | 6 | Täysi regressio testikannassa ennen tuotantoa, migraation katselmointi |
| R4 | Varaussäännöt (3 h, 30 min jaksot, klo 8–22, 90 vrk, yht. 3 h vierekkäin) eivät toteudu | 2 | 2 | 4 | Ekvivalenssiluokat ja raja-arvot DB-tasolla |
| R5 | Ajat näkyvät väärin (aikavyöhyke, kesäajan vaihto, vuorokauden raja) | 2 | 2 | 4 | Rajatapaukset kesäajan vaihtopäivinä, E2E eri kellonajoilla |
| R6 | Käyttöliittymä näyttää vanhentuneen tilanteen varmana tai ei päivity | 2 | 2 | 4 | E2E verkkokatkolla ja kahdella käyttäjällä |
| R7 | Vapaat ajat lasketaan väärin (alkamisaikalista, kestovalinnat, "Ei varauksia" -tila) | 2 | 2 | 4 | Yksikkötestit laskennalle, E2E |
| R8 | Vuoron jatkaminen toimii väärin | 2 | 2 | 4 | Päätöstaulu DB-tasolla |
| R9 | Keskeinen polku ei toimi puhelimen näyttökoossa | 2 | 2 | 4 | E2E 375 px, hyväksymistestaus puhelimella |
| R10 | Istunto: vanhentunutta istuntoa ei ohjata kirjautumiseen, tai omat varaukset katoavat uusinnassa | 1 | 2 | 2 | DB-tilasiirtymätestit, E2E |
| R11 | Kuka tahansa voi poistaa minkä tahansa varauksen (tietoinen päätös) | 3 | 1 | 3 | Vahvistuskyselyn testi (asunnon numero näkyy). Riski hyväksytty |

---

## 4. Testisuunnitelma

### 4.1 Laajuus

**Testataan (toiminnalliset ominaisuudet)**

| Ominaisuus | Keskeinen sisältö |
|---|---|
| F1 Kirjautuminen | Oikea ja väärä salasana, istunnon säilyminen ja uusiminen, uloskirjautuminen, vanhentunut istunto |
| F2 Kalenterinäkymä | Päivän vaihto (nuolet, kalenterivalitsin), laitesuodatin, asunto ja varausaika erillisinä, vapaat ajat, tilatekstit |
| F3 Varauksen luonti | Laite, päivä, alkamisaika, kesto, asunnon numero, onnistumis- ja virheilmoitukset |
| F4 Varaussäännöt | 30 min–3 h, 30 min jaksot, klo 8–22, 90 vrk horisontti, ei mennyttä aikaa, vierekkäiset yht. 3 h, päällekkäisyys laitekohtaisesti |
| F5 Varauksen poisto | Vahvistuskysely asunnon numerolla, kenen tahansa varaus, päättynyttä ei voi poistaa, aika vapautuu |
| F6 Vuoron jatkaminen | +30 min tai +1 h, vain viimeisen tunnin aikana, vain oma laite, jatkoaika vapaa, ei yli klo 22 |
| F7 Omat varaukset | Laitekohtainen lista, säilyy uudelleenkirjautumisessa |
| F8 Ajantasaisuus | Automaattinen päivitys 30 s, päivitysaika näkyvissä, varoitus vanhentuneesta tiedosta, latausympyrä |
| F9 Käyttöohjeet | 9 ohjetta näkyvät sisällöltään muuttumattomina |

**Ei testata**

- Ei-toiminnalliset testityypit (luku 2.5)
- 15 minuutin sääntö teknisenä toimintona: sitä ei ole toteutettu (CLAUDE.md 6), joten vain ohjeteksti tarkistetaan
- Supabase- ja GitHub-palveluiden sisäinen toiminta
- Ylläpitotoiminnot SQL Editorissa (salasanan vaihto, aukioloaikojen muutos), paitsi aukioloaikojen vaikutus varauksiin

### 4.2 Testitekniikat

| Tekniikka (ISTQB) | Kohde | Esimerkit |
|---|---|---|
| Ekvivalenssiluokat | Kesto, asunnon numero, laite | Kelvollinen 30–180 min / liian pitkä / nolla / negatiivinen / ei 30 min jakso; asunto "12", "A 12" / "abc" / tyhjä; laite 1, 2 / tuntematon |
| Raja-arvoanalyysi | Kesto, aukioloaika, horisontti | 30 ja 180 min (ok), 0 ja 210 min (hylätty); alku 7.30 (hylätty) / 8.00 (ok); loppu 22.00 (ok) / 22.30 (hylätty); alku 22.00 (hylätty); 90 / 91 vrk |
| Päätöstaulu | Vuoron jatkaminen | Taulu 4.2.1 |
| Tilasiirtymätestaus | Istunto, varaus | Istunto: ei → voimassa → uusittu / vanhentunut / uloskirjattu. Varaus: tuleva → käynnissä → päättynyt / poistettu |
| Käyttötapaustestaus | Asukkaan polut | Kirjaudu → valitse päivä → varaa → näe varaus → poista |
| Kokemusperusteinen | Puhelinkäyttö, virhetilanteet | Tutkiva testaus aikarajatuin sessioin (45 min, testikirja), virheiden arvaus (esim. tuplaklikkaus Varaa-painikkeessa) |

#### 4.2.1 Päätöstaulu: vuoron jatkaminen

| Ehto | S1 | S2 | S3 | S4 | S5 |
|---|---|---|---|---|---|
| Varaus tehty samalla laitteella | K | E | K | K | K |
| Vuoron viimeinen tunti on alkanut | K | K | E | K | K |
| Jatkoaika (30 min / 1 h) on vapaa | K | K | K | E | K |
| Jatko päättyy viimeistään klo 22 | K | K | K | K | E |
| **Tulos** | **Jatko onnistuu** | Hylätään | Hylätään | Hylätään (päällekkäisyys) | Hylätään |

K = kyllä, E = ei.

### 4.3 Testiympäristöt

| Ympäristö | Käyttö | Saako kirjoittaa? |
|---|---|---|
| **Testikanta (Docker)** | Komponentti-, integraatio- ja E2E-testit, CI | Kyllä. Luodaan joka ajossa alusta |
| **Tuotanto** | Savutesti julkaisun jälkeen, hyväksymistestaus | **Automaattiset testit eivät kirjoita.** Hyväksymistestaaja voi tehdä käsin oman varauksen ja poistaa sen heti, jos taloyhtiö hyväksyy tämän (avoin kysymys 1) |

E2E-testit ajetaan kahdessa näyttökoossa: puhelin (375 × 800) ja tietokone (1280 × 800).

### 4.4 Testidata

- Testikanta alustetaan migraatioilla ja paikallisella testisalasanalla.
- Testit luovat tarvitsemansa varaukset itse suhteellisin ajoin. Ne eivät oleta, että kannassa on valmiiksi dataa.
- Tuotannon dataa ei kopioida testiympäristöön.

### 4.5 Testauksen suoritus

| Vaihe | Laukaisija | Sisältö | Kesto (arvio) |
|---|---|---|---|
| Kehittäjän ajo | Ennen committia | DB- ja API-testit | < 1 min |
| CI | Push / pull request | Yksikkö-, DB-, API- ja E2E-testit | 3–5 min |
| Julkaisun jälkeen | Pages-julkaisun päätyttyä | Kirjoittamaton savutesti tuotantoa vastaan | < 1 min |
| Ennen migraatiota tuotantoon | Käsin | Migraation katselmointi, täysi regressio testikannassa | 30 min |
| Hyväksymistestaus | Merkittävä muutos | Tarkistuslista puhelimella ja tietokoneella | 30 min |

---

## 5. Aloitus- ja lopetuskriteerit

### 5.1 Aloituskriteerit (entry criteria)

- Muutos on versionhallinnassa ja vaatimusmuutos kirjattu (CLAUDE.md)
- Migraatiot ajautuvat virheettä tyhjään testikantaan
- Testiympäristö käynnistyy
- Muutoksen vaatimukset ovat selvät ja testattavat

### 5.2 Lopetuskriteerit (exit criteria) julkaisulle

- Kaikki automatisoidut testit läpäisty
- Korkean riskitason (R1–R3) testit läpäisty ilman poikkeuksia
- Ei avoimia vakavuusluokan Kriittinen tai Korkea vikoja
- Jokaisella toiminnallisella vaatimuksella (luku 6) on vähintään yksi läpäisty testi
- Hyväksymiskriteerit (CLAUDE.md 12) todennettu
- Tuotannon savutesti läpäisty julkaisun jälkeen

### 5.3 Keskeytys- ja jatkamiskriteerit

- **Keskeytys:** testikanta ei käynnisty, migraatio epäonnistuu tai päällekkäisyystestit epäonnistuvat
- **Jatkaminen:** syy korjattu ja vahvistustesti läpäisty

---

## 6. Jäljitettävyys ja nykyinen kattavuus

| Vaatimus (CLAUDE.md) | Ominaisuus | Nykyiset testit | Kattavuus | Toimenpide |
|---|---|---|---|---|
| Sisäänpääsy yhteisellä salasanalla | F1 | DB, API | Hyvä | E2E-polku |
| Istunto 30 vrk, uusiminen | F1, F7 | DB | Hyvä | Vanhentuneen istunnon käsittely käyttöliittymässä (E2E) |
| Molempien laitteiden varaukset näkyvät | F2 | DB, API | Hyvä | E2E |
| Asunto ja varausaika erillisissä sarakkeissa | F2 | Manuaalinen | Heikko | E2E: taulukon sarakkeet |
| Päivän valinta ja kalenterissa liikkuminen | F2 | Manuaalinen | Heikko | E2E: nuolet, kalenterivalitsin, menneet päivät estetty lomakkeessa |
| Vapaat ja varatut ajat erotettu tekstein | F2 | Manuaalinen | Heikko | E2E: tilatekstit "Vapaa" / "Varattu" |
| Varauksen teko | F3 | DB, API | Hyvä | E2E-polku |
| Enimmäiskesto 3 h, 30 min jaksot | F4 | DB | Hyvä | – |
| Vierekkäiset varaukset yhteensä 3 h | F4 | DB | Osittainen | Molemmat suunnat, eri laitteet, eri asunnot |
| Varattava aika klo 8–22 | F4 | DB | Hyvä | Alkamisaikalista käyttöliittymässä (E2E) |
| Päällekkäisyyksien esto | F4 | DB, API (20 rinnakkaista) | Hyvä | – |
| Pesukone ei estä kuivuria | F4 | DB, API | Hyvä | – |
| Peruminen ja ajan vapautuminen | F5 | DB, API | Hyvä | E2E: vahvistuskysely asunnon numerolla |
| Jatkaminen tunti kerrallaan | F6 | DB | Osittainen | Päätöstaulun S1–S5 kaikki tapaukset |
| Omat varaukset | F7 | DB | Hyvä | E2E |
| Ajantasaisuus | F8 | Manuaalinen | Heikko | E2E kahdella selainkontekstilla |
| Vanhentunutta tietoa ei näytetä varmana | F8 | Manuaalinen | Heikko | E2E verkkokatkolla |
| Epäonnistunutta tallennusta ei näytetä onnistuneena | F3 | – | Puuttuu | E2E: palvelinvirhe varauksen aikana |
| Käyttöohjeet | F9 | Manuaalinen | Heikko | E2E: 9 ohjetta |
| Toimii puhelimella ja tietokoneella | kaikki | Manuaalinen | Heikko | E2E kahdessa näyttökoossa |
| Ajat paikallisessa ajassa | F2, F3 | – | Puuttuu | DB ja E2E kesäajan vaihtopäivälle |

Suurimmat aukot:
- **Käyttöliittymän toiminnallisille poluille ei ole automaatiota.**
- **Testejä ei ajeta CI:ssä.**
- **Aika- ja kesäaikatapauksille ei ole testejä.**

---

## 7. Testitapausesimerkit

| ID | Taso | Tekniikka | Esiehto | Vaiheet | Odotettu tulos | Riski |
|---|---|---|---|---|---|---|
| TC-DB-01 | Komponentti | Raja-arvo | Kirjautunut | Varaa pesukone huomenna 10.00, kesto 180 min | Onnistuu | R4 |
| TC-DB-02 | Komponentti | Raja-arvo | Kirjautunut | Kesto 210 min | Hylätään: kesto enintään 3 h | R4 |
| TC-DB-03 | Komponentti | Raja-arvo | Aukiolo 8–22 | Alku 7.30, kesto 60 min | Hylätään: "Pesutupaa voi varata vain klo 8.00–22.00." | R4 |
| TC-DB-04 | Komponentti | Raja-arvo | Aukiolo 8–22 | Alku 20.30, kesto 90 min | Onnistuu (päättyy 22.00) | R4 |
| TC-DB-05 | Komponentti | Päätöstaulu S4 | Oma käynnissä oleva varaus, viimeinen tunti, seuraava tunti varattu | Jatka vuoroa | Hylätään päällekkäisyytenä | R8 |
| TC-DB-06 | Komponentti | Päätöstaulu S5 | Oma varaus 20.30–21.30, viimeinen tunti alkanut | Jatka vuoroa | Hylätään (ylittäisi klo 22) | R8 |
| TC-API-01 | Integraatio | Rinnakkaisuus | Kaksi istuntoa | 20 samanaikaista varausta samaan aikaan | Täsmälleen 1 onnistuu, 19 saa päällekkäisyysvirheen | R1 |
| TC-E2E-01 | Järjestelmä | Käyttötapaus | Testikanta, 375 px | Kirjaudu → seuraava päivä → varaa kuivuri 18.00 1 h asunnolle 9 | Onnistumisilmoitus, rivi "9 \| 18.00–19.00" kuivurin taulukossa ja Omissa varauksissa | R9 |
| TC-E2E-02 | Järjestelmä | Käyttötapaus | Kaksi selainkontekstia | A varaa, B odottaa enintään 35 s | B näkee varauksen ilman sivun päivitystä | R6 |
| TC-E2E-03 | Järjestelmä | Virheen arvaus | Varaus näkyy | Katkaise verkko, odota päivitystä | Varoitus "voi olla vanhentunut", vapaita aikoja ei näytetä varmana | R6 |
| TC-E2E-04 | Järjestelmä | Virheen arvaus | Varauslomake täytetty | Palvelin palauttaa virheen tallennuksessa | Virheilmoitus, varausta ei näy kalenterissa eikä Omissa varauksissa | R2 |
| TC-E2E-05 | Järjestelmä | Käyttötapaus | Toisen asunnon varaus näkyy | Poista → peruuta vahvistus; poista → hyväksy | Peruutus ei poista. Hyväksyntä poistaa, kysely mainitsee asunnon numeron, aika näkyy vapaana | R11 |
| TC-E2E-06 | Järjestelmä | Tilasiirtymä | Istunto poistettu kannasta | Tee mikä tahansa toiminto | Ohjataan kirjautumiseen, ilmoitus "Istunto on vanhentunut" | R10 |
| TC-E2E-07 | Järjestelmä | Raja-arvo | Selaimen kello 28.3.2027 (kesäajan alku) | Avaa päivä, varaa 8.00–9.00 | Ajat näkyvät oikein Suomen aikana | R5 |
| TC-PROD-01 | Järjestelmäintegraatio | Savutesti | Julkaisu tehty | `node tests/api_test.mjs` tuotannon osoitteella | Tarkistukset läpi, kantaan ei kirjoiteta | R3 |

---

## 8. Organisointi

### 8.1 Roolit

| Rooli | Vastuu |
|---|---|
| Testiautomaatiokonsultti | Toiminnallisen testauksen strategia ja suunnitelma, automaatiokehys, CI, raportointi |
| Kehittäjä | Komponenttitestit, vikojen korjaus, vahvistustestit |
| Ylläpitäjä (taloyhtiö) | Migraatioiden ajo tuotantoon, hyväksyntä |
| Asukasedustaja | Hyväksymistestaus puhelimella |
| (Muu osapuoli) | Ei-toiminnallinen testaus (luku 2.5) |

### 8.2 Työkalut

| Tarve | Työkalu |
|---|---|
| Tietokantatestit | psql + SQL-testit (vaihtoehto: pgTAP) |
| API-testit | Node.js (`fetch`) |
| E2E | Playwright |
| Yksikkötestit | `node:test` tai Vitest |
| CI | GitHub Actions |
| Vianhallinta | GitHub Issues (tunnisteet: vakavuus, prioriteetti, riski-ID) |

### 8.3 Aikataulu (ehdotus)

| Vaihe | Tehtävät | Kesto |
|---|---|---|
| 1 | Suunnitelman katselmointi ja hyväksyntä | 0,5 pv |
| 2 | Nykyisten DB- ja API-testien ajo CI:ssä | 1 pv |
| 3 | Playwright-kehys, E2E-polut TC-E2E-01…06 | 2–3 pv |
| 4 | Aukkojen täydennys: päätöstaulu, vierekkäiset varaukset, kesäaika, yksikkötestit | 1–2 pv |
| 5 | Savutesti julkaisun jälkeen CI:hin, hyväksymistestaus | 1 pv |

### 8.4 Poikkeamien hallinta

Vikaraportti (ISTQB) sisältää:

- tunniste ja otsikko
- ympäristö ja versio (commit)
- toistovaiheet
- odotettu ja havaittu tulos
- vakavuus ja prioriteetti
- liitteet (kuvakaappaus, Playwright-trace)
- riski-ID

| Vakavuus | Kuvaus | Esimerkki |
|---|---|---|
| Kriittinen | Varausdatan eheys vaarantuu | Päällekkäinen varaus syntyy, varaus katoaa |
| Korkea | Keskeinen toiminto ei toimi | Varausta ei voi tehdä puhelimella |
| Keskitaso | Toiminto toimii puutteellisesti | Väärä virheilmoitus, väärä vapaa aika listassa |
| Matala | Kosmeettinen | Teksti rivittyy kapealla näytöllä |

### 8.5 Raportointi ja mittarit

- **Testin edistymisraportti** jokaisesta CI-ajosta (GitHub Actions -yhteenveto, Playwright HTML-raportti).
- **Testin loppuraportti** merkittävän julkaisun jälkeen: mitä testattiin, poikkeamat lopetuskriteereistä, avoimet viat, jäännösriski.
- Mittarit:
  - läpäisyprosentti
  - vaatimuskattavuus (luku 6)
  - riskikattavuus (R1–R11)
  - avoimet viat vakavuuksittain
  - epävakaiden (flaky) testien määrä

---

## 9. Projektiriskit, oletukset ja avoimet kysymykset

### 9.1 Projektiriskit

| Riski | Vaikutus | Hallinta |
|---|---|---|
| Docker-testikanta eroaa Supabasesta | Migraatio voi toimia testissä mutta ei tuotannossa | Migraation katselmointi, savutesti heti ajon jälkeen |
| Aikariippuvat testit voivat olla epävakaita | Väärät hälytykset | Kello asetetaan E2E:ssä, DB-testit käyttävät suhteellisia aikoja |
| Tuotantodataa ei saa käyttää | Oikean käytön ongelmat jäävät huomaamatta | Hyväksymistestaus oikeilla laitteilla, palautekanava asukkaille |
| Ei-toiminnallinen testaus rajattu pois | Esim. saavutettavuus- tai tietoturvapuutteet jäävät tämän suunnitelman ulkopuolelle | Rajaus kirjataan näkyvästi (2.5), vastuu sovitaan sidosryhmien kanssa |

### 9.2 Oletukset

- Käyttäjiä on kymmeniä, samanaikaisia muutamia.
- Taloyhtiön säännöt (käyttöohjeet) ovat annettuja, eikä testaus muuta niitä.
- Ei-toiminnallisen testauksen tarve arvioidaan tämän suunnitelman ulkopuolella.

### 9.3 Avoimet kysymykset sidosryhmille

1. Saako hyväksymistestaaja tehdä tuotantoon käsin testivarauksen, joka poistetaan heti?
2. Kuka tekee hyväksymistestauksen ja millä laitteilla?
3. Kuka vastaa ei-toiminnallisesta testauksesta, vai hyväksytäänkö se jäännösriskinä?
4. Hyväksytäänkö tietoisesti riski, että kuka tahansa voi poistaa minkä tahansa varauksen (R11)?
5. Ajetaanko tuotannon savutesti automaattisesti jokaisen julkaisun jälkeen?
