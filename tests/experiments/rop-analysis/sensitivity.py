"""Post-review sensitivity analysis; preserve frozen inputs and raw blind scores.

Six claims were rejected because extraction evidence was hidden
from reviewers. Verify the exact evidence exists in producer prompts, remove only those
claims, and recompute the unchanged adoption gate. This was NOT preregistered.
"""
import copy
import hashlib
import json
from statistics import mean
from experiment import WORK, save, verify
from evaluate import qualifies

CHECKS = {
    "run-008": ("pub(crate) fn index(&self) -> usize", False),
    "run-036": ("pub(crate) fn index(&self) -> usize", False),
    "run-031": ("Effect.Effect<ClientRequest.HttpClientRequest, any, any>", True),
    "run-041": ("Fx.Effect<string, Failed, never>", False),
    "run-050": ("Fx.Effect<string, Failed, never>", False),
    "run-068": ("Fx.Effect<string, Failed, never>", False),
}


def main():
    manifest = json.loads((WORK / "manifest.json").read_text())
    verify(manifest)
    original = json.loads((WORK / "summary.json").read_text())
    result = copy.deepcopy(original)
    corrections = []
    for row in result["observations"]:
        if row["id"] not in CHECKS:
            continue
        needle, critical = CHECKS[row["id"]]
        prompt = WORK / "runs" / row["id"] / "prompt.txt"
        assert needle in prompt.read_text(), "Expected producer evidence is absent"
        review = json.loads((WORK / "reviews" / row["case"] / "review.json").read_text())
        score = next(s for s in review["scores"] if s["id"] == row["id"])
        claims = score["false_assertions"]
        assert len(claims) == 1 and claims[0]["critical"] == critical
        assert row["false"] == 1 and row["critical"] == int(critical)
        corrections.append({
            "id": row["id"], "original_claim": claims[0], "producer_evidence": needle,
            "prompt_sha256": hashlib.sha256(prompt.read_bytes()).hexdigest(),
            "reason": "The evidence was supplied to the producer, but hidden from the blind reviewer. No source semantics or gold requirement was changed.",
        })
        row["false"] = 0
        row["critical"] = 0
        if row["id"] in {"run-008", "run-036"}:
            requirement = next(r for r in score["requirements"] if r["id"] == "search-dispatch-and-propagation")
            assert not requirement["fulfilled"]
            corrections[-1]["restored_requirement"] = requirement
            corrections[-1]["reason"] = "Producer evidence resolves index() to usize. For this unsigned type, the failed > 0 guard is equivalent to == 0. The gold requirement is unchanged."
            row["fulfilled"] += 1
            row["missing"] -= 1
    assert len(corrections) == len(CHECKS)
    language = {c["id"]: c["language"] for c in manifest["cases"]}
    for lang, conditions in result["aggregate"].items():
        for condition, aggregate in conditions.items():
            rows = [r for r in result["observations"]
                    if language[r["case"]] == lang and r["condition"] == condition]
            aggregate["fulfilled_mean"] = mean(r["fulfilled"] for r in rows)
            aggregate["false_mean"] = mean(r["false"] for r in rows)
            aggregate["critical"] = sum(r["critical"] for r in rows)
            for case, metrics in aggregate["by_case"].items():
                metrics["fulfilled_mean"] = mean(r["fulfilled"] for r in rows if r["case"] == case)
                metrics["false_mean"] = mean(r["false"] for r in rows if r["case"] == case)
        burden = {"ast-grep": 0, "ts-morph": 1, "syn": 1, "rust-analyzer": 2}
        candidates = [c for c in conditions if c != "baseline" and qualifies(conditions[c], conditions["baseline"])]
        candidates.sort(key=lambda c: (conditions[c]["false_mean"], -conditions[c]["fulfilled_mean"], burden[c]))
        result["decisions"][lang] = {"qualifying": candidates, "recommendation": candidates[0] if candidates else "retain baseline"}
    result["post_review_corrections"] = corrections
    result["interpretation"] = "Post-review sensitivity analysis, not preregistered; compare with unchanged summary.json."
    save(WORK / "sensitivity.json", result)
    print(json.dumps(result["decisions"], indent=2))


if __name__ == "__main__":
    main()
