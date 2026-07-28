from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    docs_offer = json.loads((ROOT / "docs/service-offer.json").read_text(encoding="utf-8"))
    site_offer = json.loads((ROOT / "site/service-offer.json").read_text(encoding="utf-8"))
    assert docs_offer == site_offer
    assert docs_offer["commerce"]["lane_id"] == "private-ai-readiness-sprint"
    assert docs_offer["delivery_boundary"] == {
        "runtime_owner": "customer",
        "control_plane": "customer cloud account, cluster, registry, KMS, secrets, and logs",
        "vendor_access": "time-bounded and customer-approved when required",
        "data_path": "no vendor-hosted prompts, model weights, vector data, or runtime telemetry",
    }
    assert docs_offer["pilot_deliverables"]
    assert docs_offer["production_exclusions"]
    assert "#private-inquiry" in docs_offer["lead_capture_url"]

    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    prohibited = (
        "Production-quality modules",
        "production-safe defaults",
        "OPA sidecars evaluate request-level policy",
        "Secrets never rest on disk",
        "every inference request",
    )
    for phrase in prohibited:
        assert phrase not in readme, phrase

    print("commercial boundary ok")


if __name__ == "__main__":
    main()
