const statusEl = document.getElementById("status");
const katalogEl = document.getElementById("katalog");
const detailEl = document.getElementById("detail");
const playerEl = document.getElementById("player");

const felder = {
  titel: document.getElementById("titel"),
  preis: document.getElementById("preis"),
  jahr: document.getElementById("jahr"),
  km: document.getElementById("km"),
  fuel: document.getElementById("fuel"),
  ps: document.getElementById("ps"),
  farbe: document.getElementById("farbe"),
  getriebe: document.getElementById("getriebe"),
  beschreibung: document.getElementById("beschreibung"),
  listing: document.getElementById("listing"),
};

function geldwert(wert) {
  return new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR", maximumFractionDigits: 0 }).format(wert);
}

function kilometer(wert) {
  return new Intl.NumberFormat("de-DE").format(wert) + " km";
}

function liesJobAusQuery() {
  const params = new URLSearchParams(window.location.search);
  return params.get("job");
}

async function ladeJson(pfad) {
  const antwort = await fetch(pfad, { cache: "no-store" });
  if (!antwort.ok) {
    throw new Error(`HTTP ${antwort.status} fuer ${pfad}`);
  }
  return antwort.json();
}

function setzeAktivenJob(job) {
  detailEl.classList.remove("verborgen");
  statusEl.textContent = "";
  playerEl.src = job.public.video_url;
  playerEl.poster = job.public.poster_url;

  felder.titel.textContent = job.vehicle.title;
  felder.preis.textContent = geldwert(job.vehicle.price_eur);
  felder.jahr.textContent = String(job.vehicle.year);
  felder.km.textContent = kilometer(job.vehicle.mileage_km);
  felder.fuel.textContent = job.vehicle.fuel;
  felder.ps.textContent = `${job.vehicle.power_hp} PS`;
  felder.farbe.textContent = job.vehicle.color;
  felder.getriebe.textContent = job.vehicle.transmission;
  felder.beschreibung.textContent = job.content.summary;
  felder.listing.href = job.vehicle.listing_url;
  felder.listing.textContent = job.vehicle.listing_url;
}

function schreibeKatalog(katalog) {
  katalogEl.innerHTML = "";
  katalog.forEach((eintrag) => {
    const li = document.createElement("li");
    const a = document.createElement("a");
    a.href = `?job=${encodeURIComponent(eintrag.job_id)}`;
    a.textContent = `${eintrag.vehicle.title} - ${geldwert(eintrag.vehicle.price_eur)}`;
    li.appendChild(a);
    katalogEl.appendChild(li);
  });
}

async function start() {
  try {
    const katalog = await ladeJson("./data/catalog.json");
    schreibeKatalog(katalog.items);

    if (!katalog.items.length) {
      statusEl.textContent = "Noch keine Clips veroeffentlicht.";
      return;
    }

    const jobId = liesJobAusQuery() || katalog.items[0].job_id;
    const job = await ladeJson(`./data/${encodeURIComponent(jobId)}.json`);
    setzeAktivenJob(job);
  } catch (fehler) {
    statusEl.textContent = `Fehler: ${fehler.message}`;
  }
}

start();
