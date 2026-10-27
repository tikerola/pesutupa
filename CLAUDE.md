# CLAUDE.md — Pesutuvan varausjärjestelmä

## 1. Projektin tarkoitus

Toteuta suomenkielinen, mobiiliystävällinen verkkopohjainen pesutuvan varausjärjestelmä taloyhtiön asukkaille.

Järjestelmän avulla asukkaat voivat tarkastella pesutuvan varaustilannetta, varata pesukoneen tai kuivurin, perua omia varauksiaan ja tarkastella muiden tekemiä varauksia.

Sovelluksen tulee olla yksinkertainen käyttää, selkeä myös pienellä puhelimen näytöllä ja mahdollisimman edullinen ylläpitää.

## 2. Tekninen toteutus

Ensisijainen tekninen ratkaisu:

- **Frontend:** HTML, CSS ja JavaScript tai kevyt vastaava frontend-kehys.
- **Julkaisu:** GitHub Pages.
- **Tietokanta:** Supabase PostgreSQL.
- **Kirjautuminen:** yhteinen salasana, joka tarkistetaan turvallisesti palvelinpuolella tai asianmukaisella tunnistautumisratkaisulla.
- **Tietoturva:** Supabasen Row Level Security (RLS), tietokannan rajoitteet ja turvalliset käyttöoikeudet.

Tavoitteena on maksuton tai mahdollisimman edullinen käyttöönotto.

Älä oleta, että GitHub Pages tarjoaa palvelinpuolen koodin suorittamisen. Älä koskaan tallenna salasanoja tai Supabasen `service_role`-avainta julkiseen lähdekoodiin.

Supabasen julkista `anon`- tai publishable-avainta saa käyttää selaimessa vain, kun tietokannan käyttöoikeudet ja RLS-säännöt on määritetty turvallisesti.

Yhteisen salasanan toteutus ei saa perustua pelkkään JavaScriptiin tallennettuun salasanaan tai piilotettuun käyttöliittymään. Valitse toteutus, jossa salasana tarkistetaan luotettavasti ja varausrajapinta on suojattu. Selvitä ennen toteutusta, miten yhteinen tunnistautuminen toteutetaan Supabasen kanssa ilman tarpeettoman monimutkaista omaa palvelinta.

## 3. Käyttäjät ja kirjautuminen

- Kaikilla talon asukkailla on yhteinen salasana.
- Kirjautumisnäkymä on suomenkielinen.
- Onnistuneen kirjautumisen jälkeen käyttäjä pääsee varauskalenteriin.
- Kirjautuminen voidaan pitää voimassa samalla laitteella kohtuullisen ajan, esimerkiksi 30 päivää, turvallisen istunnon avulla.
- Käyttäjältä pyydetään asunnon numero varausta tehtäessä.
- Asunnon numero ei yksin ole käyttäjän tunnistautumistapa.
- Älä kerää asukkaiden nimiä tai sähköpostiosoitteita, ellei niille ilmene erillistä tarvetta.

## 4. Varattavat laitteet

Pesutuvassa on kaksi erikseen varattavaa laitetta:

1. Pesukone
2. Kuivuri

Laitteilla on omat varauskalenterinsa tai selvästi toisistaan erotetut kalenterinäkymät.

Varausta tehtäessä valitaan aina laite, jota varaus koskee.

Pesukoneen varaus ei estä kuivurin varaamista samalle ajalle, eikä päinvastoin.

## 5. Kalenterin käyttöliittymä

Kalenterin tulee olla suomenkielinen ja mobiiliystävällinen.

Näytä varaukset selkeästi joko viikko- tai päiväkalenterissa. Käyttäjän pitää voida siirtyä eri päivien välillä ja nähdä vapaana olevat ajat.

Jokaisesta varauksesta näytetään omissa sarakkeissaan:

- **Asunto:** varauksen tehneen asunnon numero, esimerkiksi `9`.
- **Varausaika:** varauksen alkamis- ja päättymisaika, esimerkiksi `17.00–20.00`.

Laite näkyy kalenterin otsikossa tai muussa selkeästi erottuvassa kohdassa.

Esimerkki:

### Pesukone

| Asunto | Varausaika |
|---|---|
| 9 | 17.00–20.00 |
| 12 | 20.00–22.00 |
| – | Vapaa |

### Kuivuri

| Asunto | Varausaika |
|---|---|
| 9 | 20.00–21.00 |
| – | Vapaa |

Esimerkin varaukset ovat havainnollistavia, eivät todellisia varauksia.

Asunnon numero ja varausaika on pidettävä erillisinä tietoina ja visuaalisesti erillään toisistaan myös pienillä näytöillä. Älä yhdistä niitä yhdeksi tekstikentäksi, kuten `Asunto 9 · 17.00–20.00`.

Käyttöliittymän tulee sisältää:
- Päivämäärän valinta.
- Kalenterissa liikkuminen.
- Laitteen valinta.
- Uuden varauksen tekeminen.
- Omat varaukset.
- Oman varauksen peruminen.
- Pesutuvan käyttöohjeet.
- Selkeät onnistumis- ja virheilmoitukset.

Vapaat ajat ja varatut ajat on erotettava visuaalisesti toisistaan. Värien lisäksi käytä tekstimuotoisia tilatietoja saavutettavuuden parantamiseksi.

## 6. Varaussäännöt

### Varausten kesto

- Pesukoneen tai kuivurin voi varata enintään kolmeksi tunniksi kerrallaan.
- Varaus ei saa olla kestoltaan nolla tai negatiivinen.
- Varaukset tehdään puolen tunnin jaksoissa: varaus alkaa ja päättyy tasa- tai puolelta tunnilta, ja kesto on 30 minuutista 3 tuntiin (päätetty 27.10.2026; alun perin yhden tunnin jaksot).
- Käyttäjä voi varata laitteen vain, jos valittu aika on vapaa.

### Varausten jatkaminen

- Jos oman vuoron jälkeen ei ole muita varauksia, käyttäjä voi jatkaa vuoroaan tunti kerrallaan.
- Jatkaminen sallitaan vain, jos seuraava tunti on vapaa.
- Jatkaminen ei saa aiheuttaa päällekkäisyyttä toisen varauksen kanssa.
- Jatkovaraus käsitellään uutena varauksena tai olemassa olevan varauksen hallittuna muutoksena.

### Varausten päällekkäisyydet

- Samalle laitteelle ei saa syntyä päällekkäisiä varauksia.
- Päällekkäisyyksien esto on toteutettava myös tietokantatasolla, ei vain käyttöliittymässä.
- Tarkista varaustilanne uudelleen tallennuksen yhteydessä.
- Jos kaksi käyttäjää yrittää varata saman ajan yhtä aikaa, vain yksi varaus saa onnistua.
- Päällekkäisyys tarkistetaan laitekohtaisesti.

### Varausten peruminen

- Käyttäjä voi perua oman varauksensa.
- Perumisen jälkeen aika vapautuu muiden varattavaksi.
- Perumisesta näytetään vahvistus.
- Kuka tahansa kirjautunut käyttäjä voi poistaa minkä tahansa varauksen. Ennen poistoa kysytään vahvistus, jossa näkyy varauksen asunnon numero (päätetty 27.10.2026; alun perin muiden varauksia ei voinut perua).

### 15 minuutin sääntö

Jos käyttäjä ei ole aloittanut vuoroaan 15 minuutin kuluessa varauksen alkamisesta, toinen käyttäjä voi ottaa kuluvan tunnin käyttöönsä.

Tämä sääntö näytetään käyttöohjeissa.

Älä toteuta automaattista varauksen vapauttamista pelkän kellon perusteella, koska järjestelmä ei ilman erillistä mekanismia voi tietää, onko käyttäjä aloittanut vuoronsa. Mahdollinen myöhempi toteutus edellyttää erikseen suunniteltua vuoron aloituksen vahvistusta ja selkeitä sääntöjä.

## 7. Pesutuvan käyttöohjeet

Näytä seuraavat ohjeet varauskalenterin yhteydessä:

1. Pesukoneen ja kuivurin voi varata enintään kolmeksi tunniksi kerrallaan, jotta pesuaikoja riittää kaikille.
2. Jos oman vuoron jälkeen ei ole muita varauksia, vuoroa voi jatkaa tunti kerrallaan.
3. Viimeisen pesutunnin jälkeen kuivuria voi varata vielä tunniksi, jotta kuivuri on seuraavan käyttäjän käytettävissä.
4. Merkitse pesukoneen ja kuivurin varaukset erikseen.
5. Peru varaus, jos et tarvitse varaamaasi aikaa.
6. Jos et ole aloittanut vuoroasi 15 minuutin kuluessa varauksen alkamisesta, toinen käyttäjä voi ottaa kuluvan tunnin käyttöönsä.
7. Tyhjennä pesukone ja kuivuri puhtaista pyykeistä oman vuorosi päätyttyä.
8. Puhdista kuivurin nukkasihti käytön jälkeen.
9. Pesukone pestään tyhjänä 95 °C:n ohjelmalla kaksi kertaa vuodessa talkoiden yhteydessä.

Säilytä ohjeiden sisältö ja merkitys. Älä muuta taloyhtiön sääntöjä itsenäisesti.

## 8. Tietomalli

Toteuta vähintään seuraavat tietokantataulut.

### devices

- `id`: yksilöllinen tunniste.
- `name`: laitteen nimi.
- `active`: tieto siitä, onko laite käytössä.

Alusta laitteiksi Pesukone ja Kuivuri.

### bookings

- `id`: yksilöllinen tunniste.
- `device_id`: viite varattuun laitteeseen.
- `apartment_number`: asunnon numero.
- `start_at`: varauksen alkamisajankohta.
- `end_at`: varauksen päättymisajankohta.
- `created_at`: varauksen luontiajankohta.

Tallenna ajankohdat tietokantaan johdonmukaisesti, esimerkiksi PostgreSQL `timestamptz`-muodossa. Näytä ajat käyttäjän paikallisessa ajassa.

Älä tallenna tarpeettomia henkilötietoja.

Lisää tarvittavat viiteavaimet, indeksit, validoinnit ja päällekkäisten varausten estot.

Päällekkäisyydet pitää estää atomisesti tietokannassa esimerkiksi PostgreSQL:n exclusion constraint -rajoitteella tai vastaavalla transaktionaalisella ratkaisulla.

Jos yhteinen kirjautuminen ei tarjoa käyttäjäkohtaista tunnistetta, suunnittele perumiselle ja muokkaukselle turvallinen valtuutusmekanismi. Älä salli varausten muokkaamista pelkän arvattavan varaus-ID:n perusteella.

## 9. Tietoturva ja virhetilanteet

- Ota käyttöön RLS kaikille selaimesta käytettäville tauluille.
- Estä luvattomat luku-, lisäys-, muokkaus- ja poistotoiminnot.
- Älä luota pelkkään käyttöliittymän validointiin.
- Tarkista asunnon numero, laite, alkamisaika, päättymisaika ja varauksen kesto myös palvelinpuolella tai tietokannan tasolla.
- Estä päällekkäiset varaukset myös samanaikaisten pyyntöjen aikana.
- Älä paljasta salaisuuksia tai palvelimen ylläpitoavaimia julkisessa repositoriossa.
- Älä kirjaa salasanoja tai istuntotunnisteita sovelluslokeihin.
- Näytä käyttäjälle ymmärrettävät virheilmoitukset.
- Jos tallennus epäonnistuu, älä näytä varausta onnistuneena.
- Älä näytä tietokannasta vanhentunutta varaustilannetta varmana tietona.

## 10. Julkaisu ja ylläpito

Projektin pitää olla julkaistavissa GitHub Pagesissa.

Sisällytä projektiin:
- Kaikki tarvittavat lähdekooditiedostot.
- Selkeät asennus- ja käyttöönotto-ohjeet.
- Supabasen tietokantamigraatiot tai SQL-tiedostot.
- Ohjeet RLS-sääntöjen määrittämiseen.
- GitHub Pages -julkaisuohjeet.
- Ohjeet Supabasen ympäristöasetusten määrittämiseen.
- Esimerkki ympäristöasetuksista ilman oikeita salaisuuksia.
- Testausohjeet.

Älä väitä sovellusta käyttövalmiiksi ennen kuin kirjautuminen, tietokanta, käyttöoikeudet, varausten luonti, peruminen ja päällekkäisyyksien esto on testattu.

## 11. Kehityksen työjärjestys

Toteuta järjestelmä seuraavassa järjestyksessä:

1. Luo projektin rakenne ja responsiivinen käyttöliittymä.
2. Toteuta kalenteri ja erilliset laitenäkymät.
3. Toteuta Supabasen tietokantataulut ja tietoturvasäännöt.
4. Suunnittele ja toteuta yhteinen salasanakirjautuminen turvallisesti.
5. Toteuta varausten luonti, listaus ja peruminen.
6. Toteuta kolmen tunnin enimmäiskesto ja päällekkäisyyksien esto tietokantatasolla.
7. Toteuta virheilmoitukset ja lataustilat.
8. Testaa rinnakkaiset varausyritykset ja käyttöoikeudet.
9. Julkaise GitHub Pagesissa ja dokumentoi käyttöönotto.

Tee ensin toimiva, pieni versio. Älä lisää tarpeettomia ominaisuuksia, kuten maksuja, sähköposti-ilmoituksia tai monimutkaisia käyttäjähallintoja, ellei niitä erikseen pyydetä.

## 12. Valmis-versio hyväksytään, kun

- Asukas pääsee sisään yhteisellä salasanalla.
- Asukas voi tarkastella molempien laitteiden varauksia.
- Asunnon numero ja varausaika näkyvät erillisissä sarakkeissa.
- Asukas voi tehdä ja perua varauksen.
- Samalle laitteelle ei voi tehdä päällekkäisiä varauksia.
- Enimmäiskesto on kolme tuntia.
- Varaustiedot näkyvät kaikille käyttäjille ajantasaisesti.
- Käyttöohjeet ovat helposti löydettävissä.
- Sovellus toimii puhelimella ja tietokoneella.
- Tietokannan käyttöoikeudet on testattu.
- Projekti voidaan julkaista dokumentoitujen ohjeiden avulla GitHub Pagesissa.
