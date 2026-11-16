.pragma library

// Data layer: Open-Meteo forecast + geocoding, WMO weather code mapping to
// Sailfish theme weather icons (Foreca-style codes used by Sailfish Weather),
// translations (UI, weather descriptions, wind/cloud names) and day names.

var FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
var GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"
var REVERSE_URL = "https://nominatim.openstreetmap.org/reverse"

var HOURLY = [
    "temperature_2m", "apparent_temperature", "precipitation", "rain",
    "showers", "snowfall", "cloud_cover", "wind_speed_10m",
    "wind_direction_10m", "wind_gusts_10m", "weather_code", "is_day",
    "pressure_msl", "precipitation_probability"
]

// Available forecast models (Open-Meteo "models" parameter).
// Names of the models are proper names; only the "best match" label is translated (key model_best).
var MODELS = [
    { id: "best_match",     key: "model_best" },
    { id: "icon_seamless",  name: "DWD ICON (D2 2 km / EU)" },
    { id: "metno_seamless", name: "MET Norway (yr.no)" },
    { id: "ecmwf_ifs025",   name: "ECMWF IFS 0.25°" },
    { id: "gfs_seamless",   name: "NOAA GFS" },
    { id: "meteofrance_seamless", name: "Météo-France AROME/ARPEGE" }
]

function forecastUrl(lat, lon, model) {
    var u = FORECAST_URL + "?latitude=" + lat.toFixed(4) + "&longitude=" + lon.toFixed(4)
            + "&hourly=" + HOURLY.join(",")
            + "&wind_speed_unit=ms&timezone=auto&forecast_days=8&past_hours=3"
    if (model && model !== "best_match") u += "&models=" + model
    return u
}

// ---- languages --------------------------------------------------------------
// Supported UI languages (2-letter codes). Anything else falls back to English.
var LANGS = ["en", "cs", "sk", "de", "pl", "fr", "es", "it", "ru"]

// "cs_CZ" / "cs" -> "cs"; unknown -> "en"
function lc(lang) {
    var c = (lang || "en").substr(0, 2).toLowerCase()
    return LANGS.indexOf(c) >= 0 ? c : "en"
}

// Open-Meteo geocoding supports a fixed list of languages; use the closest one.
function geoLang(lang) {
    var c = lc(lang)
    if (c === "sk") return "cs"
    return ["en", "cs", "de", "pl", "fr", "es", "it", "ru"].indexOf(c) >= 0 ? c : "en"
}

function geocodeUrl(query, lang) {
    return GEOCODE_URL + "?name=" + encodeURIComponent(query) + "&count=15&language=" + geoLang(lang) + "&format=json"
}

function reverseUrl(lat, lon, lang) {
    return REVERSE_URL + "?format=jsonv2&zoom=10&accept-language=" + lc(lang)
            + "&lat=" + lat + "&lon=" + lon
}

// Translation of a UI key. Missing key -> English -> key itself.
function tr(key, lang) {
    var d = UI[lc(lang)]
    if (d && d[key] !== undefined) return d[key]
    return UI.en[key] !== undefined ? UI.en[key] : key
}

// Generic JSON GET. cb(err, obj)
function getJson(url, cb) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        if (xhr.status === 200) {
            try {
                cb(null, JSON.parse(xhr.responseText))
            } catch (e) {
                cb("Invalid response: " + e, null)
            }
        } else {
            var msg = "HTTP " + xhr.status
            try {
                var j = JSON.parse(xhr.responseText)
                if (j.reason) msg += ": " + j.reason
            } catch (e2) {}
            cb(msg, null)
        }
    }
    xhr.open("GET", url)
    xhr.send()
}

// Parse the raw Open-Meteo response to an array of hourly records plus meta.
// Time strings are local time of the location (timezone=auto). We convert them
// to JS Date using the utc_offset_seconds so that comparisons with "now" work.
function parseForecast(raw) {
    var h = raw.hourly
    var off = raw.utc_offset_seconds || 0
    var n = h.time.length
    var hours = []
    for (var i = 0; i < n; i++) {
        // "2026-11-09T13:00" local -> epoch ms
        var t = h.time[i]
        var y = +t.substr(0, 4), mo = +t.substr(5, 2) - 1, d = +t.substr(8, 2)
        var hh = +t.substr(11, 2), mm = +t.substr(14, 2)
        var epoch = Date.UTC(y, mo, d, hh, mm) - off * 1000
        var snow = h.snowfall[i] || 0            // cm
        var prec = h.precipitation[i] || 0       // mm (rain + showers + snow water eq.)
        var rain = (h.rain[i] || 0) + (h.showers[i] || 0)
        hours.push({
            time: epoch,
            localHour: hh,
            localDate: t.substr(0, 10),
            temp: h.temperature_2m[i],
            feels: h.apparent_temperature[i],
            precip: prec,
            rain: rain,
            snow: snow,           // cm of snow
            snowWater: Math.max(0, prec - rain),
            clouds: h.cloud_cover[i],
            wind: h.wind_speed_10m[i],
            windDir: h.wind_direction_10m[i],
            gust: h.wind_gusts_10m[i],
            code: h.weather_code[i],
            isDay: h.is_day[i] === 1,
            pressure: h.pressure_msl[i],
            pop: h.precipitation_probability ? h.precipitation_probability[i] : null
        })
    }
    return {
        hours: hours,
        utcOffset: off,
        timezone: raw.timezone,
        elevation: raw.elevation,
        fetched: Date.now()
    }
}

// Index of the hourly record covering "now" (floor), or -1.
function indexNow(hours, now) {
    now = now || Date.now()
    for (var i = hours.length - 1; i >= 0; i--) {
        if (hours[i].time <= now) return i
    }
    return -1
}

// ---- Weather code mapping -------------------------------------------------
// Sailfish theme icons: icon-m-weather-{d|n}XYZ where X = cloudiness
// (0 clear, 1 almost clear, 2 half cloudy, 3 broken, 4 overcast, 5 thin high
// clouds, 6 fog), Y = precipitation (0 none, 1 slight, 2 showers, 3 steady,
// 4 thunder), Z = type (0 rain, 1 sleet, 2 snow). Not all combinations exist in
// the theme; the table below only uses existing ones.
var WMO_TO_FORECA = {
    0: "000", 1: "100", 2: "200", 3: "400",
    45: "600", 48: "600",
    51: "310", 53: "410", 55: "430",
    56: "311", 57: "431",
    61: "410", 63: "430", 65: "430",
    66: "411", 67: "431",
    71: "412", 73: "432", 75: "432", 77: "412",
    80: "220", 81: "320", 82: "430",
    85: "222", 86: "322",
    95: "240", 96: "440", 99: "440"
}

function iconCode(code, isDay) {
    var c = WMO_TO_FORECA[code] || "400"
    return (isDay ? "d" : "n") + c
}

function iconSource(code, isDay, size) {
    return "image://theme/icon-" + (size || "m") + "-weather-" + iconCode(code, isDay)
}

// Weather description by WMO code.
function describe(code, lang) {
    var t = UI[lc(lang)].wmo
    return t[code] || UI.en.wmo[code] || ""
}

// ---- day names ------------------------------------------------------------
// Day names come from the system locale (Qt), so they match the phone's
// language for every supported locale. Short names are upper-cased (MO, TU...).
function qtDay(dateStr) {
    var d = new Date(dateStr + "T12:00:00Z").getUTCDay()   // 0 = Sunday
    return d === 0 ? 7 : d                                  // Qt: 1 = Monday .. 7 = Sunday
}

function dayShort(dateStr, lang) {
    // QLocale::ShortFormat = 1
    return Qt.locale(lc(lang)).dayName(qtDay(dateStr), 1).toUpperCase()
}

function dayLong(dateStr, lang) {
    // QLocale::LongFormat = 0
    var s = Qt.locale(lc(lang)).dayName(qtDay(dateStr), 0)
    return s.charAt(0).toUpperCase() + s.substr(1)
}

function pad2(n) { return (n < 10 ? "0" : "") + n }

// Human readable local time of a record: "Monday 14:00"
function timeLabel(rec, lang) {
    return dayLong(rec.localDate, lang) + " " + pad2(rec.localHour) + ":00"
}

function windDirName(deg, lang) {
    var i = Math.round(((deg % 360) + 360) % 360 / 45) % 8
    return UI[lc(lang)].dirs[i]
}

// Beaufort-ish verbal wind description (m/s)
function windName(ms, lang) {
    var b = ms < 0.3 ? 0 : ms < 1.6 ? 1 : ms < 3.4 ? 2 : ms < 5.5 ? 3 : ms < 8 ? 4
          : ms < 10.8 ? 5 : ms < 13.9 ? 6 : ms < 17.2 ? 7 : ms < 20.8 ? 8 : 9
    return UI[lc(lang)].beaufort[b]
}

function cloudName(pct, lang) {
    var i = pct < 12 ? 0 : pct < 37 ? 1 : pct < 62 ? 2 : pct < 87 ? 3 : 4
    return UI[lc(lang)].clouds[i]
}

function formatTemp(t) {
    if (t === undefined || t === null) return "–"
    return (Math.round(t * 10) / 10).toFixed(1) + " °C"
}

// ---- translations -----------------------------------------------------------
var UI = {
en: {
    weather: "Weather", loading: "Loading...", feels_like: "Feels like",
    forecast_3: "3-day forecast", forecast_7: "7-day forecast",
    change_location: "Change location", settings: "Settings", refresh: "Refresh",
    locations: "Locations", search_place: "Search place", use_current: "Use current position",
    waiting_position: "Waiting for position...", position_unavailable: "Position not available",
    position_timeout: "Position timeout", results: "Results", saved_locations: "Saved locations",
    no_places: "No places found", no_saved: "No saved locations", my_location: "My location",
    remove: "Remove", removing: "Removing", could_not_load: "Could not load forecast",
    gusts: ", gusts %1 m/s", forecast_model: "Forecast model", model_best: "Best match (auto)",
    model_desc: "Open-Meteo weather model. 'Best match' picks the best regional model for the location.",
    default_range: "Default range", range_3: "3 days", range_7: "7 days", about: "About",
    about_text: "Weather Chart %1 shows the forecast as charts, inspired by the Android app Klara.<br>Weather data by <a href='https://open-meteo.com/'>Open-Meteo.com</a> (CC BY 4.0). Place search by Open-Meteo geocoding, reverse geocoding by OpenStreetMap Nominatim. Weather icons from the Sailfish OS theme.",
    wmo: { 0: "Clear", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
        45: "Fog", 48: "Rime fog", 51: "Light drizzle", 53: "Drizzle", 55: "Dense drizzle",
        56: "Freezing drizzle", 57: "Dense freezing drizzle", 61: "Light rain", 63: "Rain", 65: "Heavy rain",
        66: "Freezing rain", 67: "Heavy freezing rain", 71: "Light snow", 73: "Snow", 75: "Heavy snow",
        77: "Snow grains", 80: "Light showers", 81: "Showers", 82: "Violent showers",
        85: "Snow showers", 86: "Heavy snow showers", 95: "Thunderstorm", 96: "Thunderstorm with hail",
        99: "Severe thunderstorm with hail" },
    beaufort: ["Calm", "Light air", "Light breeze", "Gentle breeze", "Moderate breeze",
        "Fresh breeze", "Strong breeze", "Near gale", "Gale", "Storm"],
    clouds: ["Clear", "Mainly clear", "Partly cloudy", "Cloudy", "Overcast"],
    dirs: ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
},
cs: {
    weather: "Počasí", loading: "Načítání...", feels_like: "Pocitově",
    forecast_3: "Předpověď na 3 dny", forecast_7: "Předpověď na 7 dní",
    change_location: "Změnit lokaci", settings: "Nastavení", refresh: "Obnovit",
    locations: "Lokace", search_place: "Hledat místo", use_current: "Použít aktuální polohu",
    waiting_position: "Čekání na polohu...", position_unavailable: "Poloha není dostupná",
    position_timeout: "Vypršel čas na zjištění polohy", results: "Výsledky", saved_locations: "Uložené lokace",
    no_places: "Nic nenalezeno", no_saved: "Žádné uložené lokace", my_location: "Moje poloha",
    remove: "Odebrat", removing: "Odebírání", could_not_load: "Předpověď se nepodařilo načíst",
    gusts: ", nárazy %1 m/s", forecast_model: "Model předpovědi", model_best: "Nejlepší shoda (auto)",
    model_desc: "Model počasí Open-Meteo. „Best match“ vybere pro místo nejlepší regionální model.",
    default_range: "Výchozí rozsah", range_3: "3 dny", range_7: "7 dní", about: "O aplikaci",
    about_text: "Počasí v grafu %1 zobrazuje předpověď formou grafů, inspirované androidí aplikací Klara.<br>Data o počasí: <a href='https://open-meteo.com/'>Open-Meteo.com</a> (CC BY 4.0). Hledání míst přes geokódování Open-Meteo, reverzní geokódování přes OpenStreetMap Nominatim. Ikony počasí z tématu Sailfish OS.",
    wmo: { 0: "Jasno", 1: "Skoro jasno", 2: "Polojasno", 3: "Zataženo",
        45: "Mlha", 48: "Mrznoucí mlha", 51: "Slabé mrholení", 53: "Mrholení", 55: "Silné mrholení",
        56: "Mrznoucí mrholení", 57: "Silné mrznoucí mrholení", 61: "Slabý déšť", 63: "Déšť", 65: "Silný déšť",
        66: "Mrznoucí déšť", 67: "Silný mrznoucí déšť", 71: "Slabé sněžení", 73: "Sněžení", 75: "Silné sněžení",
        77: "Sněhová zrna", 80: "Slabé přeháňky", 81: "Přeháňky", 82: "Silné přeháňky",
        85: "Sněhové přeháňky", 86: "Silné sněhové přeháňky", 95: "Bouřka", 96: "Bouřka s kroupami",
        99: "Silná bouřka s kroupami" },
    beaufort: ["Bezvětří", "Vánek", "Slabý vítr", "Mírný vítr", "Dosti čerstvý vítr",
        "Čerstvý vítr", "Silný vítr", "Prudký vítr", "Bouřlivý vítr", "Vichřice"],
    clouds: ["Jasno", "Skoro jasno", "Polojasno", "Oblačno", "Zataženo"],
    dirs: ["S", "SV", "V", "JV", "J", "JZ", "Z", "SZ"]
},
sk: {
    weather: "Počasie", loading: "Načítavanie...", feels_like: "Pocitovo",
    forecast_3: "Predpoveď na 3 dni", forecast_7: "Predpoveď na 7 dní",
    change_location: "Zmeniť lokalitu", settings: "Nastavenia", refresh: "Obnoviť",
    locations: "Lokality", search_place: "Hľadať miesto", use_current: "Použiť aktuálnu polohu",
    waiting_position: "Čakanie na polohu...", position_unavailable: "Poloha nie je dostupná",
    position_timeout: "Vypršal čas na zistenie polohy", results: "Výsledky", saved_locations: "Uložené lokality",
    no_places: "Nenašlo sa nič", no_saved: "Žiadne uložené lokality", my_location: "Moja poloha",
    remove: "Odstrániť", removing: "Odstraňovanie", could_not_load: "Predpoveď sa nepodarilo načítať",
    gusts: ", nárazy %1 m/s", forecast_model: "Model predpovede", model_best: "Najlepšia zhoda (auto)",
    model_desc: "Model počasia Open-Meteo. „Best match“ vyberie pre miesto najlepší regionálny model.",
    default_range: "Predvolený rozsah", range_3: "3 dni", range_7: "7 dní", about: "O aplikácii",
    about_text: "Počasie v grafe %1 zobrazuje predpoveď formou grafov, inšpirované androidovou aplikáciou Klara.<br>Údaje o počasí: <a href='https://open-meteo.com/'>Open-Meteo.com</a> (CC BY 4.0). Vyhľadávanie miest cez geokódovanie Open-Meteo, reverzné geokódovanie cez OpenStreetMap Nominatim. Ikony počasia z témy Sailfish OS.",
    wmo: { 0: "Jasno", 1: "Takmer jasno", 2: "Polooblačno", 3: "Zamračené",
        45: "Hmla", 48: "Námrazová hmla", 51: "Slabé mrholenie", 53: "Mrholenie", 55: "Silné mrholenie",
        56: "Mrznúce mrholenie", 57: "Silné mrznúce mrholenie", 61: "Slabý dážď", 63: "Dážď", 65: "Silný dážď",
        66: "Mrznúci dážď", 67: "Silný mrznúci dážď", 71: "Slabé sneženie", 73: "Sneženie", 75: "Silné sneženie",
        77: "Snehové zrná", 80: "Slabé prehánky", 81: "Prehánky", 82: "Silné prehánky",
        85: "Snehové prehánky", 86: "Silné snehové prehánky", 95: "Búrka", 96: "Búrka s krupobitím",
        99: "Silná búrka s krupobitím" },
    beaufort: ["Bezveternie", "Vánok", "Slabý vietor", "Mierny vietor", "Dosť čerstvý vietor",
        "Čerstvý vietor", "Silný vietor", "Prudký vietor", "Búrlivý vietor", "Víchrica"],
    clouds: ["Jasno", "Takmer jasno", "Polooblačno", "Oblačno", "Zamračené"],
    dirs: ["S", "SV", "V", "JV", "J", "JZ", "Z", "SZ"]
},
de: {
    weather: "Wetter", loading: "Laden...", feels_like: "Gefühlt",
    forecast_3: "3-Tage-Vorhersage", forecast_7: "7-Tage-Vorhersage",
    change_location: "Ort ändern", settings: "Einstellungen", refresh: "Aktualisieren",
    locations: "Orte", search_place: "Ort suchen", use_current: "Aktuellen Standort verwenden",
    waiting_position: "Warte auf Standort...", position_unavailable: "Standort nicht verfügbar",
    position_timeout: "Zeitüberschreitung beim Standort", results: "Ergebnisse", saved_locations: "Gespeicherte Orte",
    no_places: "Keine Orte gefunden", no_saved: "Keine gespeicherten Orte", my_location: "Mein Standort",
    remove: "Entfernen", removing: "Wird entfernt", could_not_load: "Vorhersage konnte nicht geladen werden",
    gusts: ", Böen %1 m/s", forecast_model: "Vorhersagemodell", model_best: "Beste Übereinstimmung (auto)",
    model_desc: "Open-Meteo-Wettermodell. „Best match“ wählt das beste regionale Modell für den Ort.",
    default_range: "Standardbereich", range_3: "3 Tage", range_7: "7 Tage", about: "Über",
    about_text: "Weather Chart %1 zeigt die Vorhersage als Diagramme, inspiriert von der Android-App Klara.<br>Wetterdaten von <a href='https://open-meteo.com/'>Open-Meteo.com</a> (CC BY 4.0). Ortssuche über das Geocoding von Open-Meteo, Rückwärtsgeocoding über OpenStreetMap Nominatim. Wettersymbole aus dem Sailfish-OS-Design.",
    wmo: { 0: "Klar", 1: "Überwiegend klar", 2: "Teilweise bewölkt", 3: "Bedeckt",
        45: "Nebel", 48: "Reifnebel", 51: "Leichter Nieselregen", 53: "Nieselregen", 55: "Starker Nieselregen",
        56: "Gefrierender Nieselregen", 57: "Starker gefrierender Nieselregen", 61: "Leichter Regen", 63: "Regen", 65: "Starker Regen",
        66: "Gefrierender Regen", 67: "Starker gefrierender Regen", 71: "Leichter Schneefall", 73: "Schneefall", 75: "Starker Schneefall",
        77: "Schneegriesel", 80: "Leichte Schauer", 81: "Schauer", 82: "Heftige Schauer",
        85: "Schneeschauer", 86: "Starke Schneeschauer", 95: "Gewitter", 96: "Gewitter mit Hagel",
        99: "Starkes Gewitter mit Hagel" },
    beaufort: ["Windstille", "Leiser Zug", "Leichte Brise", "Schwache Brise", "Mäßige Brise",
        "Frische Brise", "Starker Wind", "Steifer Wind", "Stürmischer Wind", "Sturm"],
    clouds: ["Klar", "Überwiegend klar", "Teilweise bewölkt", "Bewölkt", "Bedeckt"],
    dirs: ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]
},
pl: {
    weather: "Pogoda", loading: "Ładowanie...", feels_like: "Odczuwalna",
    forecast_3: "Prognoza na 3 dni", forecast_7: "Prognoza na 7 dni",
    change_location: "Zmień lokalizację", settings: "Ustawienia", refresh: "Odśwież",
    locations: "Lokalizacje", search_place: "Szukaj miejsca", use_current: "Użyj bieżącej lokalizacji",
    waiting_position: "Oczekiwanie na lokalizację...", position_unavailable: "Lokalizacja niedostępna",
    position_timeout: "Przekroczono czas lokalizacji", results: "Wyniki", saved_locations: "Zapisane lokalizacje",
    no_places: "Nie znaleziono miejsc", no_saved: "Brak zapisanych lokalizacji", my_location: "Moja lokalizacja",
    remove: "Usuń", removing: "Usuwanie", could_not_load: "Nie udało się pobrać prognozy",
    gusts: ", porywy %1 m/s", forecast_model: "Model prognozy", model_best: "Najlepsze dopasowanie (auto)",
    model_desc: "Model pogody Open-Meteo. „Best match” wybiera najlepszy model regionalny dla lokalizacji.",
    default_range: "Domyślny zakres", range_3: "3 dni", range_7: "7 dni", about: "Informacje",
    about_text: "Weather Chart %1 przedstawia prognozę w formie wykresów, zainspirowany aplikacją Klara na Androida.<br>Dane pogodowe: <a href='https://open-meteo.com/'>Open-Meteo.com</a> (CC BY 4.0). Wyszukiwanie miejsc przez geokodowanie Open-Meteo, geokodowanie odwrotne przez OpenStreetMap Nominatim. Ikony pogody z motywu Sailfish OS.",
    wmo: { 0: "Bezchmurnie", 1: "Prawie bezchmurnie", 2: "Częściowe zachmurzenie", 3: "Pochmurno",
        45: "Mgła", 48: "Szadź", 51: "Lekka mżawka", 53: "Mżawka", 55: "Gęsta mżawka",
        56: "Marznąca mżawka", 57: "Gęsta marznąca mżawka", 61: "Lekki deszcz", 63: "Deszcz", 65: "Silny deszcz",
        66: "Marznący deszcz", 67: "Silny marznący deszcz", 71: "Lekki śnieg", 73: "Śnieg", 75: "Intensywne opady śniegu",
        77: "Ziarna śniegu", 80: "Lekkie przelotne opady", 81: "Przelotne opady", 82: "Gwałtowne przelotne opady",
        85: "Przelotny śnieg", 86: "Silny przelotny śnieg", 95: "Burza", 96: "Burza z gradem",
        99: "Silna burza z gradem" },
    beaufort: ["Cisza", "Powiew", "Lekki wiatr", "Łagodny wiatr", "Umiarkowany wiatr",
        "Świeży wiatr", "Silny wiatr", "Bardzo silny wiatr", "Wichura", "Silna wichura"],
    clouds: ["Bezchmurnie", "Prawie bezchmurnie", "Częściowe zachmurzenie", "Pochmurno", "Zachmurzenie całkowite"],
    dirs: ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
},
fr: {
    weather: "Météo", loading: "Chargement...", feels_like: "Ressenti",
    forecast_3: "Prévisions sur 3 jours", forecast_7: "Prévisions sur 7 jours",
    change_location: "Changer de lieu", settings: "Paramètres", refresh: "Actualiser",
    locations: "Lieux", search_place: "Rechercher un lieu", use_current: "Utiliser la position actuelle",
    waiting_position: "En attente de la position...", position_unavailable: "Position indisponible",
    position_timeout: "Délai de localisation dépassé", results: "Résultats", saved_locations: "Lieux enregistrés",
    no_places: "Aucun lieu trouvé", no_saved: "Aucun lieu enregistré", my_location: "Ma position",
    remove: "Supprimer", removing: "Suppression", could_not_load: "Impossible de charger les prévisions",
    gusts: ", rafales %1 m/s", forecast_model: "Modèle de prévision", model_best: "Meilleur choix (auto)",
    model_desc: "Modèle météo Open-Meteo. « Best match » choisit le meilleur modèle régional pour le lieu.",
    default_range: "Plage par défaut", range_3: "3 jours", range_7: "7 jours", about: "À propos",
    about_text: "Weather Chart %1 affiche les prévisions sous forme de graphiques, inspiré de l'application Android Klara.<br>Données météo : <a href='https://open-meteo.com/'>Open-Meteo.com</a> (CC BY 4.0). Recherche de lieux via le géocodage Open-Meteo, géocodage inverse via OpenStreetMap Nominatim. Icônes météo du thème Sailfish OS.",
    wmo: { 0: "Dégagé", 1: "Généralement dégagé", 2: "Partiellement nuageux", 3: "Couvert",
        45: "Brouillard", 48: "Brouillard givrant", 51: "Bruine légère", 53: "Bruine", 55: "Bruine dense",
        56: "Bruine verglaçante", 57: "Bruine verglaçante dense", 61: "Pluie faible", 63: "Pluie", 65: "Pluie forte",
        66: "Pluie verglaçante", 67: "Forte pluie verglaçante", 71: "Neige faible", 73: "Neige", 75: "Neige forte",
        77: "Grains de neige", 80: "Averses faibles", 81: "Averses", 82: "Averses violentes",
        85: "Averses de neige", 86: "Fortes averses de neige", 95: "Orage", 96: "Orage avec grêle",
        99: "Orage violent avec grêle" },
    beaufort: ["Calme", "Très légère brise", "Légère brise", "Petite brise", "Jolie brise",
        "Bonne brise", "Vent frais", "Grand frais", "Coup de vent", "Tempête"],
    clouds: ["Dégagé", "Généralement dégagé", "Partiellement nuageux", "Nuageux", "Couvert"],
    dirs: ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
},
es: {
    weather: "Tiempo", loading: "Cargando...", feels_like: "Sensación",
    forecast_3: "Previsión de 3 días", forecast_7: "Previsión de 7 días",
    change_location: "Cambiar ubicación", settings: "Ajustes", refresh: "Actualizar",
    locations: "Ubicaciones", search_place: "Buscar lugar", use_current: "Usar la ubicación actual",
    waiting_position: "Esperando la ubicación...", position_unavailable: "Ubicación no disponible",
    position_timeout: "Tiempo de espera de la ubicación agotado", results: "Resultados", saved_locations: "Ubicaciones guardadas",
    no_places: "No se encontraron lugares", no_saved: "No hay ubicaciones guardadas", my_location: "Mi ubicación",
    remove: "Eliminar", removing: "Eliminando", could_not_load: "No se pudo cargar la previsión",
    gusts: ", rachas %1 m/s", forecast_model: "Modelo de previsión", model_best: "Mejor coincidencia (auto)",
    model_desc: "Modelo meteorológico de Open-Meteo. «Best match» elige el mejor modelo regional para la ubicación.",
    default_range: "Intervalo predeterminado", range_3: "3 días", range_7: "7 días", about: "Acerca de",
    about_text: "Weather Chart %1 muestra la previsión en gráficos, inspirada en la aplicación Android Klara.<br>Datos meteorológicos de <a href='https://open-meteo.com/'>Open-Meteo.com</a> (CC BY 4.0). Búsqueda de lugares con la geocodificación de Open-Meteo, geocodificación inversa con OpenStreetMap Nominatim. Iconos del tema de Sailfish OS.",
    wmo: { 0: "Despejado", 1: "Mayormente despejado", 2: "Parcialmente nublado", 3: "Cubierto",
        45: "Niebla", 48: "Niebla con escarcha", 51: "Llovizna ligera", 53: "Llovizna", 55: "Llovizna densa",
        56: "Llovizna helada", 57: "Llovizna helada densa", 61: "Lluvia débil", 63: "Lluvia", 65: "Lluvia fuerte",
        66: "Lluvia helada", 67: "Lluvia helada fuerte", 71: "Nevada débil", 73: "Nevada", 75: "Nevada fuerte",
        77: "Granos de nieve", 80: "Chubascos débiles", 81: "Chubascos", 82: "Chubascos violentos",
        85: "Chubascos de nieve", 86: "Fuertes chubascos de nieve", 95: "Tormenta", 96: "Tormenta con granizo",
        99: "Tormenta fuerte con granizo" },
    beaufort: ["Calma", "Ventolina", "Brisa muy débil", "Brisa débil", "Brisa moderada",
        "Brisa fresca", "Viento fuerte", "Viento duro", "Temporal", "Borrasca"],
    clouds: ["Despejado", "Mayormente despejado", "Parcialmente nublado", "Nublado", "Cubierto"],
    dirs: ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
},
it: {
    weather: "Meteo", loading: "Caricamento...", feels_like: "Percepita",
    forecast_3: "Previsioni a 3 giorni", forecast_7: "Previsioni a 7 giorni",
    change_location: "Cambia posizione", settings: "Impostazioni", refresh: "Aggiorna",
    locations: "Posizioni", search_place: "Cerca luogo", use_current: "Usa la posizione attuale",
    waiting_position: "In attesa della posizione...", position_unavailable: "Posizione non disponibile",
    position_timeout: "Timeout della posizione", results: "Risultati", saved_locations: "Posizioni salvate",
    no_places: "Nessun luogo trovato", no_saved: "Nessuna posizione salvata", my_location: "La mia posizione",
    remove: "Rimuovi", removing: "Rimozione", could_not_load: "Impossibile caricare le previsioni",
    gusts: ", raffiche %1 m/s", forecast_model: "Modello di previsione", model_best: "Migliore corrispondenza (auto)",
    model_desc: "Modello meteo Open-Meteo. «Best match» sceglie il miglior modello regionale per la posizione.",
    default_range: "Intervallo predefinito", range_3: "3 giorni", range_7: "7 giorni", about: "Info",
    about_text: "Weather Chart %1 mostra le previsioni sotto forma di grafici, ispirato all'app Android Klara.<br>Dati meteo di <a href='https://open-meteo.com/'>Open-Meteo.com</a> (CC BY 4.0). Ricerca dei luoghi tramite il geocoding di Open-Meteo, geocoding inverso tramite OpenStreetMap Nominatim. Icone meteo dal tema di Sailfish OS.",
    wmo: { 0: "Sereno", 1: "Prevalentemente sereno", 2: "Parzialmente nuvoloso", 3: "Coperto",
        45: "Nebbia", 48: "Nebbia con brina", 51: "Pioviggine leggera", 53: "Pioviggine", 55: "Pioviggine intensa",
        56: "Pioviggine gelata", 57: "Pioviggine gelata intensa", 61: "Pioggia debole", 63: "Pioggia", 65: "Pioggia forte",
        66: "Pioggia gelata", 67: "Pioggia gelata forte", 71: "Neve debole", 73: "Neve", 75: "Neve forte",
        77: "Granelli di neve", 80: "Rovesci deboli", 81: "Rovesci", 82: "Rovesci violenti",
        85: "Rovesci di neve", 86: "Forti rovesci di neve", 95: "Temporale", 96: "Temporale con grandine",
        99: "Temporale forte con grandine" },
    beaufort: ["Calma", "Bava di vento", "Brezza leggera", "Brezza tesa", "Vento moderato",
        "Vento fresco", "Vento forte", "Burrasca moderata", "Burrasca forte", "Tempesta"],
    clouds: ["Sereno", "Prevalentemente sereno", "Parzialmente nuvoloso", "Nuvoloso", "Coperto"],
    dirs: ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
},
ru: {
    weather: "Погода", loading: "Загрузка...", feels_like: "Ощущается",
    forecast_3: "Прогноз на 3 дня", forecast_7: "Прогноз на 7 дней",
    change_location: "Сменить место", settings: "Настройки", refresh: "Обновить",
    locations: "Места", search_place: "Поиск места", use_current: "Использовать текущее местоположение",
    waiting_position: "Ожидание местоположения...", position_unavailable: "Местоположение недоступно",
    position_timeout: "Превышено время ожидания местоположения", results: "Результаты", saved_locations: "Сохранённые места",
    no_places: "Места не найдены", no_saved: "Нет сохранённых мест", my_location: "Моё местоположение",
    remove: "Удалить", removing: "Удаление", could_not_load: "Не удалось загрузить прогноз",
    gusts: ", порывы %1 м/с", forecast_model: "Модель прогноза", model_best: "Лучшее совпадение (авто)",
    model_desc: "Метеомодель Open-Meteo. «Best match» выбирает лучшую региональную модель для места.",
    default_range: "Диапазон по умолчанию", range_3: "3 дня", range_7: "7 дней", about: "О программе",
    about_text: "Weather Chart %1 показывает прогноз в виде графиков, вдохновлён Android-приложением Klara.<br>Данные о погоде: <a href='https://open-meteo.com/'>Open-Meteo.com</a> (CC BY 4.0). Поиск мест через геокодирование Open-Meteo, обратное геокодирование через OpenStreetMap Nominatim. Значки погоды из темы Sailfish OS.",
    wmo: { 0: "Ясно", 1: "Преимущественно ясно", 2: "Переменная облачность", 3: "Пасмурно",
        45: "Туман", 48: "Изморозь", 51: "Слабая морось", 53: "Морось", 55: "Сильная морось",
        56: "Ледяная морось", 57: "Сильная ледяная морось", 61: "Слабый дождь", 63: "Дождь", 65: "Сильный дождь",
        66: "Ледяной дождь", 67: "Сильный ледяной дождь", 71: "Слабый снег", 73: "Снег", 75: "Сильный снегопад",
        77: "Снежная крупа", 80: "Слабый ливень", 81: "Ливень", 82: "Сильный ливень",
        85: "Снегопад", 86: "Сильный снегопад", 95: "Гроза", 96: "Гроза с градом",
        99: "Сильная гроза с градом" },
    beaufort: ["Штиль", "Тихий ветер", "Легкий ветер", "Слабый ветер", "Умеренный ветер",
        "Свежий ветер", "Сильный ветер", "Крепкий ветер", "Шторм", "Сильный шторм"],
    clouds: ["Ясно", "Преимущественно ясно", "Переменная облачность", "Облачно", "Пасмурно"],
    dirs: ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"]
}
}
