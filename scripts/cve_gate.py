#!/usr/bin/env python3
"""Fails when Trivy or Grype reports a critical vulnerability.

A finding counts as critical when a scanner rates it CRITICAL or when any source
scores it CVSS 9.0 or higher, with or without an available fix. Scanners disagree on
severity and use different data, so the gate takes the strictest reading of both.
"""

import json
import pathlib
import sys

CRITICAL_SCORE = 9.0
ALLOWLIST = pathlib.Path(__file__).with_name("cve-allowlist.txt")


def trivy_findings(path):
    with open(path, encoding="utf-8") as handle:
        report = json.load(handle)
    for result in report.get("Results") or []:
        for vulnerability in result.get("Vulnerabilities") or []:
            scores = []
            for source in (vulnerability.get("CVSS") or {}).values():
                scores += [source.get("V3Score") or 0, source.get("V40Score") or 0]
            yield {
                "id": vulnerability["VulnerabilityID"],
                "package": vulnerability.get("PkgName", "?"),
                "version": vulnerability.get("InstalledVersion", "?"),
                "fixed": vulnerability.get("FixedVersion") or "",
                "severity": vulnerability.get("Severity", "UNKNOWN").upper(),
                "score": max(scores, default=0),
                "where": vulnerability.get("PkgPath") or result.get("Target", ""),
                "scanner": "trivy",
            }


def grype_findings(path):
    with open(path, encoding="utf-8") as handle:
        report = json.load(handle)
    for match in report.get("matches") or []:
        vulnerability = match["vulnerability"]
        records = [vulnerability] + (match.get("relatedVulnerabilities") or [])
        scores = [
            (cvss.get("metrics") or {}).get("baseScore") or 0
            for record in records
            for cvss in record.get("cvss") or []
            if not str(cvss.get("version", "")).startswith("2")
        ]
        severities = [(record.get("severity") or "").upper() for record in records]
        artifact = match["artifact"]
        locations = artifact.get("locations") or [{}]
        yield {
            "id": vulnerability["id"],
            "package": artifact.get("name", "?"),
            "version": artifact.get("version", "?"),
            "fixed": ",".join((vulnerability.get("fix") or {}).get("versions") or []),
            "severity": "CRITICAL" if "CRITICAL" in severities else (severities[0] or "UNKNOWN"),
            "score": max(scores, default=0),
            "where": locations[0].get("path", ""),
            "scanner": "grype",
        }


def is_critical(finding):
    return finding["severity"] == "CRITICAL" or finding["score"] >= CRITICAL_SCORE


def load_allowlist():
    allowed = {}
    for line in ALLOWLIST.read_text(encoding="utf-8").splitlines():
        entry, _, reason = line.partition("#")
        if entry.strip():
            vulnerability, package = entry.split()
            allowed[(vulnerability, package)] = reason.strip()
    return allowed


def main():
    trivy_path, grype_path = sys.argv[1:3]
    findings = list(trivy_findings(trivy_path)) + list(grype_findings(grype_path))
    allowed = load_allowlist()

    merged = {}
    for finding in filter(is_critical, findings):
        if (finding["id"], finding["package"]) in allowed:
            print(f"allowed: {finding['id']} {finding['package']} ({finding['scanner']})")
            continue
        key = (finding["id"], finding["package"], finding["version"], finding["where"])
        entry = merged.setdefault(key, {**finding, "scanners": set()})
        entry["scanners"].add(finding["scanner"])
        entry["score"] = max(entry["score"], finding["score"])
        entry["fixed"] = entry["fixed"] or finding["fixed"]

    totals = {"trivy": 0, "grype": 0}
    for finding in findings:
        totals[finding["scanner"]] += 1
    print(f"findings of any severity: trivy={totals['trivy']} grype={totals['grype']}")

    if not merged:
        print("gate passed: no finding rated CRITICAL or scored CVSS 9.0+")
        return 0

    print(f"gate FAILED: {len(merged)} critical finding(s)")
    for entry in sorted(merged.values(), key=lambda item: (item["package"], item["id"])):
        fixed = f"fixed in {entry['fixed']}" if entry["fixed"] else "no fix"
        print(
            f"  {entry['id']:<22} {entry['severity']:<9} cvss={entry['score']:<4} "
            f"{entry['package']} {entry['version']} ({fixed}) "
            f"[{'+'.join(sorted(entry['scanners']))}] {entry['where']}"
        )
    return 1


if __name__ == "__main__":
    sys.exit(main())
