from __future__ import annotations

import unittest

from auto_clip.models import JobRequest


class JobRequestTest(unittest.TestCase):
    def test_valid_manifest(self) -> None:
        request = JobRequest.from_dict({
            "job_id": "10001",
            "source": {"frame_dir": "examples/frames/10001", "voice_wav": None},
            "vehicle": {
                "title": "Beispielauto",
                "price_eur": 10000,
                "year": 2022,
                "mileage_km": 25000,
                "fuel": "Benzin",
                "power_hp": 150,
                "color": "Schwarz",
                "transmission": "Automatik",
                "listing_url": "https://beispiel.de/10001",
            },
        })
        self.assertEqual(request.job_id, "10001")
        self.assertEqual(request.vehicle.price_eur, 10000)

    def test_missing_field_raises(self) -> None:
        with self.assertRaises(ValueError):
            JobRequest.from_dict({
                "job_id": "10001",
                "source": {"frame_dir": "examples/frames/10001"},
                "vehicle": {
                    "title": "Beispielauto",
                },
            })


if __name__ == "__main__":
    unittest.main()
