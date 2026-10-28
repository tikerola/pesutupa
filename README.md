# Pesutuvan varausjärjestelmä

Suomenkielinen ja mobiiliystävällinen pesutuvan varauskalenteri taloyhtiön asukkaille.

- **Frontend:** HTML, CSS ja JavaScript ilman build-vaihetta tai riippuvuuksia. Julkaistaan GitHub Pagesissa.
- **Tietokanta ja rajapinta:** Supabase (PostgreSQL ja sen automaattinen REST-rajapinta).
- **Kustannus:** GitHub Pages ja Supabasen Free-taso riittävät.

## Sisällys

1. [Miten tietoturva on toteutettu](#1-miten-tietoturva-on-toteutettu)
2. [Supabasen käyttöönotto](#2-supabasen-käyttöönotto)
3. [GitHub Pages -julkaisu](#3-github-pages--julkaisu)
4. [Ylläpito](#4-ylläpito)
5. [Testaus](#5-testaus)
6. [Projektin rakenne](#6-projektin-rakenne)
7. [Tunnetut rajoitukset](#7-tunnetut-rajoitukset)

---

## 1. Miten tietoturva on toteutettu

GitHub Pages ei suorita palvelinkoodia, joten kaikki tarkistukset tehdään tietokannassa.

- **Yhteinen salasana** tallennetaan tietokantaan vain bcrypt-tiivisteenä. Selain lähettää salasanan `login`-funktiolle, joka vertaa sitä tiivisteeseen. Salasanaa ei ole lähdekoodissa.
- **Onnistunut kirjautuminen** antaa satunnaisen 256-bittisen istuntotunnisteen, joka on voimassa 30 päivää. Se tallennetaan selaimen `localStorage`en. Tietokantaan tallennetaan vain tunnisteen SHA-256-tiiviste.
- **Arvaamisen esto:** 10 väärää salasanaa samasta osoitteesta tai 200 väärää yhteensä 15 minuutin aikana estää kirjautumisen hetkeksi. Jo kirjautuneet laitteet toimivat normaalisti.
- **Taulut ovat skeemassa `app_private`**, jota Supabasen REST-rajapinta ei julkaise. Selaimen rooleilla (`anon`, `authenticated`) ei ole niihin mitään oikeuksia, ja jokaisella taululla on lisäksi **RLS päällä** ilman sallivia politiikkoja.
- **Selain voi kutsua vain** julkisen skeeman funktioita `login`, `logout`, `get_devices`, `list_bookings`, `my_bookings`, `create_booking`, `extend_booking` ja `cancel_booking`. Jokainen niistä tarkistaa istunnon ja säännöt.
- **Päällekkäisyydet** estää PostgreSQL:n exclusion constraint (`bookings_no_overlap`). Se on atominen, joten samanaikaisista yrityksistä vain yksi voi onnistua.
- **Poistaminen:** kuka tahansa kirjautunut käyttäjä voi poistaa minkä tahansa tulevan tai käynnissä olevan varauksen. Käyttöliittymä kysyy ensin vahvistuksen ("Haluatko varmasti poistaa asunnon X varauksen?"). Ilman kirjautumista poisto ei onnistu, eikä päättyneitä varauksia voi poistaa.
- **Jatkaminen:** varaus kytketään istuntoon eli laitteeseen, jolla se tehtiin. Vain sama laite voi jatkaa vuoroa.
- **Muutosloki:** varausten luonnit, jatkot ja poistot kirjataan tietokannan liipaisimella tauluun `app_private.booking_log`, jota selain ei voi lukea suoraan. Kirjautuneet näkevät lokin funktiolla `list_booking_log` (90 päivää, enintään 200 riviä). Tekijä näytetään lyhyenä laitetunnisteena (esim. "Laite 7F3A"), josta istuntoa ei voi päätellä. Yhteisellä salasanalla henkilöä ei voi tunnistaa.
- **Selaimessa käytetään vain julkista anon- tai publishable-avainta.** Sillä ei pääse tauluihin käsiksi, koska oikeudet on rajattu tietokannassa.

### Tietokannassa tarkistettavat säännöt

| Sääntö | Missä tarkistetaan |
|---|---|
| Kesto 30 min – 3 h puolen tunnin välein; alku ja loppu tasa- tai puolelta tunnilta | `create_booking` ja `CHECK`-rajoitteet |
| Kesto ei voi olla nolla tai negatiivinen | `CHECK (end_at > start_at)` |
| Ei päällekkäisyyksiä samalla laitteella | exclusion constraint (laitekohtainen) |
| Pesukone ja kuivuri varataan erikseen | päällekkäisyys tarkistetaan laitteen mukaan |
| Varattava aika klo 8.00–22.00 Suomen aikaa (myös jatkaminen) | `create_booking`, `extend_booking` (asetukset `open_hour`, `close_hour`) |
| Mennyttä aikaa ei voi varata (kuluvan puolen tunnin jakson voi) | `create_booking` |
| Saman asunnon vierekkäiset varaukset samalle laitteelle yhteensä enintään 3 h | `create_booking` |
| Jatkaminen 30 minuutilla tai tunnilla, vain vuoron viimeisen tunnin aikana ja vain jos jatkoaika on vapaa | `extend_booking` ja exclusion constraint |
| Varauksen voi tehdä enintään 90 päivää etukäteen | `create_booking` (asetus `booking_horizon_days`) |
| Asunnon numero: 1–10 merkkiä, vähintään yksi numero, esim. `9` tai `A 12` | `create_booking` ja `CHECK` |

Ajat tallennetaan `timestamptz`-muodossa ja näytetään käyttäjän paikallisessa ajassa.

15 minuutin sääntö näytetään käyttöohjeissa. Sitä ei toteuteta automaattisesti, kuten vaatimuksissa linjataan.

---

## 2. Supabasen käyttöönotto

### 2.1 Luo projekti

1. Kirjaudu osoitteessa <https://supabase.com> ja luo uusi projekti (Free-taso riittää).
2. Valitse alueeksi esimerkiksi **North EU (Stockholm)** tai **Central EU (Frankfurt)**.
3. Tallenna tietokannan salasana salasanojen hallintaan. Sovellus ei tarvitse sitä.

### 2.2 Aja migraatiot

Aja kansion `supabase/migrations/` tiedostot **aikajärjestyksessä**, kukin omana kyselynään:

1. [`20261027000000_pesutupa_init.sql`](supabase/migrations/20261027000000_pesutupa_init.sql): taulut, funktiot ja oikeudet
2. [`20261028000000_half_hour_slots.sql`](supabase/migrations/20261028000000_half_hour_slots.sql): puolen tunnin varausjaksot
3. [`20261028010000_booking_hours.sql`](supabase/migrations/20261028010000_booking_hours.sql): varattava aika klo 8–22
4. [`20261028020000_cancel_any_booking.sql`](supabase/migrations/20261028020000_cancel_any_booking.sql): kuka tahansa kirjautunut voi poistaa varauksen
5. [`20261028030000_extend_half_hour.sql`](supabase/migrations/20261028030000_extend_half_hour.sql): vuoron jatko myös 30 minuutilla
6. [`20261028040000_booking_log.sql`](supabase/migrations/20261028040000_booking_log.sql): muutosloki (oma sivu `muutoshistoria.html`, linkki varaussivun alalaidassa)

Avaa projektissa **SQL Editor** → **New query**, liitä tiedoston koko sisältö ja paina **Run**. Tulokseksi pitää tulla *Success. No rows returned*.

**Päivitettäessä** aja uusi migraatio ennen kuin julkaiset uuden käyttöliittymän (push GitHubiin).

Vaihtoehtoisesti voit käyttää Supabase CLI:tä: `supabase link --project-ref <ref>` ja sen jälkeen `supabase db push`.

### 2.3 Aseta yhteinen salasana

Aja SQL Editorissa uutena kyselynä (vaihda oma salasanasi):

```sql
select app_private.set_shared_password('pyy4k');   -- vaihda omaksesi
```

- Salasanan pitää olla vähintään 5 merkkiä. Sekaisin kirjaimia ja numeroita (esim. `pyy4k`) on parempi kuin pelkkä sana tai numerosarja.
- **Älä tallenna tätä kyselyä** SQL Editorin snippetiksi, koska salasana jäisi selväkielisenä Supabasen kyselyhistoriaan. Tyhjennä editori ajon jälkeen.

### 2.4 Tarkista REST-rajapinnan asetukset

**Project Settings → Data API**:

- **Exposed schemas** -listassa pitää olla `public`. **`app_private` ei saa olla listassa.**
- Jos Data API on poissa käytöstä, ota se käyttöön.

Kirjautumista ei tarvitse määrittää kohdassa Authentication, koska sovellus ei käytä Supabase Authia.

### 2.5 Hae julkinen URL ja avain

- **Project URL:** Project Settings → Data API (tai *Connect*-painike), esim. `https://abcd1234.supabase.co`.
- **Julkinen avain:** Project Settings → API Keys. Kelpaa joko *publishable key* (`sb_publishable_…`) tai vanha *anon* (`eyJ…`).

> ⚠️ **Älä koskaan** käytä selaimessa tai repositoriossa `service_role`- tai `secret`-avainta (`sb_secret_…`). Julkaisutyönkulku pysäyttää julkaisun, jos sellainen annetaan.

### 2.6 Ympäristöasetukset

Sovellus lukee asetukset tiedostosta `js/config.js`. Esimerkki on tiedostossa [`js/config.example.js`](js/config.example.js):

```js
window.PESUTUPA_CONFIG = {
  supabaseUrl: 'https://your-project-ref.supabase.co',
  supabaseKey: 'your-anon-or-publishable-key',
};
```

`js/config.js` on `.gitignore`ssa. Julkaisussa GitHub Actions luo sen repositorion muuttujista (ks. kohta 3). Paikallista kokeilua varten voit kopioida esimerkin ja täyttää siihen omat arvosi.

---

## 3. GitHub Pages -julkaisu

1. Luo GitHubiin uusi repositorio ja vie koodi sinne (`main`- tai `master`-haara):
   ```bash
   git add .
   git commit -m "Pesutuvan varausjärjestelmä"
   git branch -M main
   git remote add origin https://github.com/<käyttäjä>/<repo>.git
   git push -u origin main
   ```
2. **Settings → Secrets and variables → Actions → Variables → New repository variable:**
   - `SUPABASE_URL`: kohdan 2.5 Project URL
   - `SUPABASE_KEY`: kohdan 2.5 julkinen avain

   Molemmat arvot ovat julkisia (ne näkyvät sivun lähdekoodissa), joten ne ovat *Variables*-osiossa eivätkä *Secrets*-osiossa.
3. **Settings → Pages → Build and deployment → Source:** valitse **GitHub Actions**.
4. **Actions**-välilehdellä työnkulku *Julkaise GitHub Pagesiin* ajetaan jokaisella `main`- tai `master`-haaran päivityksellä. Ensimmäisellä kerralla sen voi käynnistää käsin painikkeella *Run workflow*.
5. Sivu löytyy osoitteesta `https://<käyttäjä>.github.io/<repo>/`. Jaa osoite ja salasana asukkaille.

Repositorio voi olla julkinen, koska siinä ei ole salaisuuksia. Ilmaisella GitHub-tilillä Pages edellyttää julkista repositoriota.

**Ilman Actionsia:** jos haluat julkaista suoraan haarasta, luo `js/config.js` oikeilla arvoilla, poista se `.gitignore`sta ja valitse Pagesin lähteeksi *Deploy from a branch*. Tiedostossa saa olla vain julkinen avain.

---

## 4. Ylläpito

Ylläpito tehdään Supabasen SQL Editorissa. Tulevia varauksia voi poistaa myös suoraan sovelluksesta.

**Vaihda salasana** (vanhat kirjautumiset jäävät voimaan):
```sql
select app_private.set_shared_password('Uusi-pitkä-salasana');
```

**Vaihda salasana ja kirjaa kaikki laitteet ulos** (esim. jos salasana on vuotanut):
```sql
select app_private.set_shared_password('Uusi-pitkä-salasana', true);
```

**Katso tulevat varaukset:**
```sql
select b.id, d.name, b.apartment_number,
       b.start_at at time zone 'Europe/Helsinki' as alkaa,
       b.end_at   at time zone 'Europe/Helsinki' as paattyy
from app_private.bookings b join app_private.devices d on d.id = b.device_id
where b.end_at > now() order by b.start_at;
```

**Poista varaus SQL:llä** (esim. jos sovellukseen ei pääse):
```sql
delete from app_private.bookings where id = '<varauksen id>';
```

**Ota laite pois käytöstä tai takaisin käyttöön:**
```sql
update app_private.devices set active = false where name = 'Kuivuri';
```

**Muuta varattavaa aikaa** (esim. klo 7–23). Käyttöliittymä lukee ajat tietokannasta:
```sql
update app_private.settings set open_hour = 7, close_hour = 23;
```

**Muuta istunnon kestoa tai sitä, kuinka pitkälle etukäteen voi varata:**
```sql
update app_private.settings set session_days = 30, booking_horizon_days = 90;
```

**Huomio Supabasen Free-tasosta:** projekti keskeytetään, jos sitä ei käytetä viikkoon. Säännöllisessä käytössä tätä ei tapahdu. Keskeytetyn projektin voi palauttaa Supabasen hallintapaneelista.

---

## 5. Testaus

### 5.1 Paikallinen testiympäristö (Docker)

`tests/local/docker-compose.yml` käynnistää PostgreSQL:n ja PostgRESTin, joka on sama REST-kerros kuin Supabasessa. Migraatio ajetaan automaattisesti, ja testisalasanaksi asetetaan `testisalasana-123`.

```bash
# Tietokannan sääntö- ja käyttöoikeustestit (78 testiä)
bash tests/run-db-tests.sh --fresh

# REST-rajapinnan testit: 20 rinnakkaista varausyritystä samaan aikaan + käyttöoikeudet
node tests/api_test.mjs
```

Käyttöliittymän kokeilu paikallisesti:

```bash
# js/config.js paikallista ympäristöä varten
cat > js/config.js <<'EOF'
window.PESUTUPA_CONFIG = { restUrl: 'http://localhost:54321', supabaseKey: '' };
EOF
npx http-server -p 5500 -c-1
# avaa http://localhost:5500 ja kirjaudu salasanalla testisalasana-123
```

Sammutus: `docker compose -f tests/local/docker-compose.yml down -v`

Testit eivät jätä paikalliseen kantaan mitään: tietokantatesti ajetaan yhtenä transaktiona, joka perutaan (rollback) lopuksi. Testi myös kieltäytyy toimimasta, jos kanta ei ole paikallinen testikanta (asetus `pesutupa.test_database`, jonka vain `tests/local/00_supabase_stub.sql` asettaa).

### 5.2 Tarkistukset tuotantokantaa vastaan

Tuotantokanta on käytössä, joten sitä vastaan ajetaan vain tarkistuksia, jotka **eivät kirjoita kantaan mitään**. Ne eivät kirjaudu, eivät tee varauksia eivätkä kokeile salasanoja, eikä salasanaa tarvita.

```bash
PESUTUPA_SUPABASE_URL=https://abcd1234.supabase.co \
PESUTUPA_API_KEY=<julkinen avain> \
node tests/api_test.mjs
```

Tarkistukset varmistavat:
- taulut eivät näy REST-rajapinnassa
- salasanaa ei voi vaihtaa rajapinnan kautta
- mikään varaus- tai listausfunktio ei toimi ilman voimassa olevaa istuntoa

Istunto tarkistetaan ennen kuin mitään kirjoitetaan, joten hylätyt kutsut eivät muuta kantaa.

Kirjautuminen, varausten luonti ja poisto, 20 samanaikaista varausyritystä ja muut kirjoittavat testit ajetaan vain paikallisesti samoilla migraatioilla (kohta 5.1). API-testi tunnistaa paikallisen ympäristön osoitteesta (`localhost`) ja ajaa kirjoittavat testit vain siellä.

> Älä aja `tests/db/booking_rules_test.sql`-tiedostoa Supabasen SQL Editorissa. Se ei toimisi siellä (vartija pysäyttää sen), ja muutokset peruttaisiin joka tapauksessa.

### 5.3 Käsin testattavat asiat julkaisun jälkeen

- [ ] Kirjautuminen väärällä salasanalla näyttää virheen, ja oikealla salasanalla pääsee kalenteriin.
- [ ] Päivien selaus (‹ › ja suomenkielinen kalenteri) ja laitevalinta (*Molemmat / Pesukone / Kuivuri*) toimivat.
- [ ] Varauksen tekeminen näyttää onnistumisilmoituksen, ja varaus näkyy kalenterissa ja omissa varauksissa.
- [ ] Toisella laitteella (esim. puhelin ja tietokone) näkyy sama varaus noin 30 sekunnin kuluessa.
- [ ] Varauksen poisto kalenterista kysyy vahvistuksen ja kertoo asunnon numeron.
- [ ] Päivämäärät näkyvät muodossa 17.10.2026, ja kentän napautus avaa suomenkielisen kalenterin (viikko alkaa maanantaista).
- [ ] Varauksen poisto näyttää vahvistuksen, ja aika vapautuu.
- [ ] Sovellus toimii puhelimella ilman sivuttaisvieritystä.

---

## 6. Projektin rakenne

```
index.html                     Varaussivu
muutoshistoria.html            Muutoshistoria (oma sivu, linkki varaussivun alalaidassa)
css/styles.css                 Tyylit (mobiili ensin)
js/app.js                      Käyttöliittymän logiikka
js/api.js                      Supabasen RPC-kutsut (fetch, ei kirjastoja)
js/datepicker.js               Suomenkielinen päivämäärävalitsin
js/history.js                  Muutoshistoria-sivun toiminta
js/config.example.js           Esimerkki asetuksista
supabase/migrations/…sql       Taulut, rajoitteet, funktiot ja käyttöoikeudet
tests/db/booking_rules_test.sql  Tietokannan sääntö- ja oikeustestit
tests/api_test.mjs             REST-, rinnakkaisuus- ja oikeustestit
tests/run-db-tests.sh          Tietokantatestien ajo Dockerissa
tests/local/                   Paikallinen testiympäristö (Docker Compose)
.github/workflows/pages.yml    GitHub Pages -julkaisu
```

---

## 7. Tunnetut rajoitukset

- **"Omat varaukset" ja vuoron jatkaminen ovat laitekohtaisia.** Uudelleenkirjautuminen samalla laitteella säilyttää ne myös 30 päivän istunnon vanhennuttua. Jos selaintiedot tyhjennetään tai käyttäjä kirjautuu ulos, varaus näkyy edelleen kalenterissa ja sen voi poistaa sieltä, mutta vuoroa ei voi enää jatkaa.
- **Kuka tahansa kirjautunut voi poistaa minkä tahansa varauksen.** Vahvistuskysely estää vahinkopoistot, mutta tahallista poistamista se ei estä.
- **Yhteinen salasana on yhteinen.** Kuka tahansa salasanan tietävä voi tehdä ja poistaa varauksia millä tahansa asunnon numerolla. Jos salasana leviää, vaihda se ja kirjaa laitteet ulos (kohta 4).
- **Varaustilanne päivittyy 30 sekunnin välein** sekä aina, kun sivu tulee näkyviin ja varauksen yhteydessä. Tallennus tarkistetaan aina tietokannassa, joten vanhentunut näkymä ei voi aiheuttaa päällekkäistä varausta. Jos päivitys epäonnistuu, näkymässä näytetään varoitus.
- **Kirjautumisyritysten rajoitus** tunnistaa asiakkaan Supabasen välittämästä IP-osoitteesta. Kokonaisraja (200 virhettä / 15 min) suojaa myös hajautetulta arvaamiselta.
- **Ajat puolen tunnin jaksoissa:** järjestelmä olettaa aikavyöhykkeen, jonka poikkeama UTC:stä on tasatunteja (Suomi täyttää tämän).
