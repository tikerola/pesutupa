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
- **Peruminen ja jatkaminen:** varaus kytketään istuntoon eli laitteeseen, jolla se tehtiin. Vain sama laite voi perua tai jatkaa varauksen. Pelkkä varaus-ID ei riitä.
- **Selaimessa käytetään vain julkista anon- tai publishable-avainta.** Sillä ei pääse tauluihin käsiksi, koska oikeudet on rajattu tietokannassa.

### Tietokannassa tarkistettavat säännöt

| Sääntö | Missä tarkistetaan |
|---|---|
| Kesto 1–3 tuntia, kokonaisina tunteina | `create_booking` ja `CHECK`-rajoitteet |
| Kesto ei voi olla nolla tai negatiivinen | `CHECK (end_at > start_at)` |
| Ei päällekkäisyyksiä samalla laitteella | exclusion constraint (laitekohtainen) |
| Pesukone ja kuivuri varataan erikseen | päällekkäisyys tarkistetaan laitteen mukaan |
| Mennyttä aikaa ei voi varata (kuluva tunti voi) | `create_booking` |
| Saman asunnon vierekkäiset varaukset samalle laitteelle yhteensä enintään 3 h | `create_booking` |
| Jatkaminen tunti kerrallaan, vain vuoron viimeisen tunnin aikana ja vain jos seuraava tunti on vapaa | `extend_booking` ja exclusion constraint |
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

### 2.2 Aja migraatio

1. Avaa projektissa **SQL Editor** → **New query**.
2. Liitä editoriin tiedoston [`supabase/migrations/20261027000000_pesutupa_init.sql`](supabase/migrations/20261027000000_pesutupa_init.sql) koko sisältö ja paina **Run**.
3. Tulokseksi pitää tulla *Success. No rows returned*.

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

Ylläpito tehdään Supabasen SQL Editorissa. Tavallisella käyttäjätilalla muiden varauksia ei voi muuttaa.

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

**Poista varaus ylläpitäjänä** (esim. unohtunut varaus):
```sql
delete from app_private.bookings where id = '<varauksen id>';
```

**Ota laite pois käytöstä tai takaisin käyttöön:**
```sql
update app_private.devices set active = false where name = 'Kuivuri';
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
# Tietokannan sääntö- ja käyttöoikeustestit (49 testiä)
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

### 5.2 Testit oikeaa Supabase-projektia vastaan

Tee tämä käyttöönoton jälkeen ennen kuin osoite jaetaan asukkaille. Testi tekee testivarauksia noin 2–3 kuukauden päähän ja peruu ne lopuksi.

```bash
PESUTUPA_SUPABASE_URL=https://abcd1234.supabase.co \
PESUTUPA_API_KEY=<julkinen avain> \
PESUTUPA_PASSWORD='<yhteinen salasana>' \
node tests/api_test.mjs
```

Testi varmistaa, että taulut eivät näy REST-rajapinnassa, salasanaa ei voi vaihtaa rajapinnan kautta, väärä salasana hylätään, 20 samanaikaisesta varausyrityksestä vain yksi onnistuu, pesukoneen ja kuivurin voi varata samalle ajalle ja toisen laitteen varausta ei voi perua.

> `tests/db/booking_rules_test.sql` tyhjentää varaukset ja istunnot. **Älä aja sitä tuotantokantaan.**

### 5.3 Käsin testattavat asiat julkaisun jälkeen

- [ ] Kirjautuminen väärällä salasanalla näyttää virheen, ja oikealla salasanalla pääsee kalenteriin.
- [ ] Päivien selaus (‹ ›, päivämäärä, *Tänään*) ja laitevalinta (*Molemmat / Pesukone / Kuivuri*) toimivat.
- [ ] Varauksen tekeminen näyttää onnistumisilmoituksen, ja varaus näkyy kalenterissa ja omissa varauksissa.
- [ ] Toisella laitteella (esim. puhelin ja tietokone) näkyy sama varaus noin 30 sekunnin kuluessa. Varausta ei voi perua toiselta laitteelta.
- [ ] Varauksen peruminen näyttää vahvistuksen, ja aika vapautuu.
- [ ] Sovellus toimii puhelimella ilman sivuttaisvieritystä.

---

## 6. Projektin rakenne

```
index.html                     Sovelluksen ainoa sivu
css/styles.css                 Tyylit (mobiili ensin)
js/app.js                      Käyttöliittymän logiikka
js/api.js                      Supabasen RPC-kutsut (fetch, ei kirjastoja)
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

- **Varauksen voi perua tai jatkaa vain laitteelta, jolla se tehtiin.** Uudelleenkirjautuminen samalla laitteella säilyttää omat varaukset myös 30 päivän istunnon vanhennuttua. Jos laitteen selaintiedot tyhjennetään tai käyttäjä kirjautuu ulos, varauksia ei voi enää perua sillä laitteella. Silloin ylläpitäjä voi poistaa varauksen (kohta 4).
- **Yhteinen salasana on yhteinen.** Kuka tahansa salasanan tietävä voi tehdä varauksia millä tahansa asunnon numerolla. Jos salasana leviää, vaihda se ja kirjaa laitteet ulos (kohta 4).
- **Varaustilanne päivittyy 30 sekunnin välein** sekä aina, kun sivu tulee näkyviin ja varauksen yhteydessä. Tallennus tarkistetaan aina tietokannassa, joten vanhentunut näkymä ei voi aiheuttaa päällekkäistä varausta. Jos päivitys epäonnistuu, näkymässä näytetään varoitus.
- **Kirjautumisyritysten rajoitus** tunnistaa asiakkaan Supabasen välittämästä IP-osoitteesta. Kokonaisraja (200 virhettä / 15 min) suojaa myös hajautetulta arvaamiselta.
- **Ajat tasatunneittain:** järjestelmä olettaa aikavyöhykkeen, jossa tasatunnit ovat samat kuin UTC:ssä (Suomi täyttää tämän).
