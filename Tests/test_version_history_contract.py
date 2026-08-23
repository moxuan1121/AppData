import json
import re
import unittest


VERSION_ID_KEYS = ("external_identifier", "versionId", "version_id", "id")
VERSION_KEYS = ("bundle_version", "version", "bundleShortVersionString")
DATE_KEYS = ("created_at", "createTime", "updateTime", "date", "time", "release_date")
SIZE_KEYS = ("size", "fileSize", "fileSizeBytes")
CONTAINER_KEYS = ("data", "versions", "result", "results", "list", "items")


def safe_string(value, limit=128):
    if not isinstance(value, (str, int, float)) or isinstance(value, bool):
        return None
    value = str(value).strip()
    return value if value and len(value) <= limit else None


def records(value, depth=0):
    if depth > 4:
        return []
    if isinstance(value, list):
        return [item for item in value if isinstance(item, dict)]
    if isinstance(value, dict):
        for key in CONTAINER_KEYS:
            found = records(value.get(key), depth + 1)
            if found:
                return found
    return []


def normalize(payload, app_id, source):
    output = []
    for item in records(payload):
        first = lambda keys: next((v for k in keys if (v := safe_string(item.get(k)))), None)
        version_id, version = first(VERSION_ID_KEYS), first(VERSION_KEYS)
        if not version_id or not re.fullmatch(r"[0-9]{1,32}", version_id) or int(version_id) <= 0:
            continue
        if not version or len(version) > 64 or not re.fullmatch(r"[A-Za-z0-9._+() -]+", version):
            continue
        output.append({"appId": app_id, "version": version, "versionId": version_id,
                       "date": first(DATE_KEYS) or "", "size": first(SIZE_KEYS) or "", "source": source})
    return output


def merge(provider_payloads, app_id="414478124"):
    merged, seen, errors = [], set(), []
    for source, payload in provider_payloads:
        try:
            parsed = json.loads(payload) if isinstance(payload, str) else payload
            versions = normalize(parsed, app_id, source)
        except (ValueError, TypeError):
            versions = []
        if not versions:
            errors.append(source)
            continue
        for version in versions:
            key = version["versionId"], version["version"]
            if key not in seen:
                seen.add(key)
                merged.append(version)
            else:
                existing = next(item for item in merged if (item["versionId"], item["version"]) == key)
                existing["date"] = existing["date"] or version["date"]
                existing["size"] = existing["size"] or version["size"]
    return merged, errors


class VersionHistoryContractTests(unittest.TestCase):
    def test_all_field_aliases_are_normalized(self):
        payload = {"data": [{"external_identifier": 123, "bundle_version": "8.0", "created_at": "2020", "fileSize": 42}]}
        self.assertEqual(normalize(payload, "414478124", "timbrd")[0]["versionId"], "123")

    def test_fallback_survives_malformed_and_empty_sources(self):
        versions, errors = merge([("timbrd", "{"), ("agzy", {"data": []}),
                                  ("bilin", {"data": [{"version_id": "9", "version": "1.0"}]})])
        self.assertEqual([v["source"] for v in versions], ["bilin"])
        self.assertEqual(errors, ["timbrd", "agzy"])

    def test_mixed_sources_fill_gaps_and_deduplicate(self):
        versions, _ = merge([("timbrd", {"data": [{"id": "1", "version": "1.0", "size": None}]}),
                             ("agzy", {"result": [{"versionId": 1, "bundleShortVersionString": "1.0"},
                                                    {"versionId": 2, "version": "2.0", "fileSize": "2 MB"}]})])
        self.assertEqual([(v["versionId"], v["version"]) for v in versions], [("1", "1.0"), ("2", "2.0")])

    def test_later_provider_fills_missing_metadata_without_changing_primary_source(self):
        versions, _ = merge([("timbrd", [{"id": 1, "version": "1.0"}]),
                             ("agzy", {"data": [{"versionId": 1, "version": "1.0", "size": "10 MB"}]})])
        self.assertEqual(versions[0]["source"], "timbrd")
        self.assertEqual(versions[0]["size"], "10 MB")

    def test_rejects_missing_or_untrusted_fields(self):
        payload = {"versions": [{"id": "abc", "version": "1.0"}, {"id": 2},
                                {"id": 3, "version": "<script>"}, {"id": 4, "version": "x" * 65}]}
        self.assertEqual(normalize(payload, "414478124", "agzy"), [])


if __name__ == "__main__":
    unittest.main()
