from __future__ import annotations

from auto_clip.models import JobRequest


def build_content(request: JobRequest) -> dict[str, str]:
    vehicle = request.vehicle

    headline = f"{vehicle.title} fuer {vehicle.price_eur:,} EUR".replace(",", ".")
    summary = (
        f"{vehicle.title} in {vehicle.color} mit {vehicle.power_hp} PS, "
        f"{vehicle.transmission}, Baujahr {vehicle.year} und {vehicle.mileage_km:,} km."
    ).replace(",", ".")

    narration = (
        f"Hier kommt {vehicle.title}. "
        f"Baujahr {vehicle.year}, {vehicle.mileage_km:,} Kilometer, "
        f"{vehicle.fuel}, {vehicle.power_hp} PS und {vehicle.transmission}. "
        f"Der Preis liegt bei {vehicle.price_eur:,} Euro. "
        f"Mehr Informationen findest du in der Anzeige."
    ).replace(",", ".")

    return {
        "headline": headline,
        "summary": summary,
        "narration": narration,
    }
