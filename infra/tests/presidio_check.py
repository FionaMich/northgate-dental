"""Runs inside the presidio-analyzer container (stdlib only): analyse a message built from the canary record, anonymise it,
and print the result. test_presidio.sh then runs the canary scan over that output, which must come back clean.

Northgate's own identifiers are added as ad hoc recognizers, the way later services will call Presidio:
record numbers (NG and seven digits) and member IDs on coverage cards."""
import json
import urllib.request

TEXT = (
    "Patient Zyxwq Canary (record NG0000099, member ID CANARY-7F3A9) called from 617-555-0110 "
    "and asked us to email zyxwq.canary@canary.northgate.synthetic about the crown."
)
RECOGNIZERS = [
    {"name": "northgate_record", "supported_language": "en", "supported_entity": "NG_RECORD",
     "patterns": [{"name": "record", "regex": r"\bNG\d{7}\b", "score": 0.9}]},
    {"name": "member_id", "supported_language": "en", "supported_entity": "MEMBER_ID",
     "patterns": [{"name": "member", "regex": r"\b[A-Z]{3,10}-[A-Z0-9]{4,12}\b", "score": 0.6}],
     "context": ["member", "insurance", "policy"]},
    # Presidio's own email recognizer only accepts real top-level domains, so synthetic addresses (.synthetic) slip past it.
    {"name": "any_email", "supported_language": "en", "supported_entity": "EMAIL_ADDRESS",
     "patterns": [{"name": "email", "regex": r"\b[\w.+-]+@[\w-]+(\.[\w-]+)+\b", "score": 1.0}]},
    # Names this rare are missed by the language model, so known patient names are passed in by the caller.
    {"name": "known_names", "supported_language": "en", "supported_entity": "PERSON", "deny_list": ["Zyxwq", "Canary"]},
]


def post(url: str, body: dict):
    req = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


# Only the entity types a US practice handles: without this list, URL and UK recognizers compete with the email
# and phone recognizers and leave fragments of an email address outside the redaction.
ENTITIES = ["PERSON", "PHONE_NUMBER", "EMAIL_ADDRESS", "US_SSN", "US_DRIVER_LICENSE", "US_PASSPORT", "US_BANK_NUMBER",
            "CREDIT_CARD", "IP_ADDRESS", "LOCATION", "DATE_TIME", "NG_RECORD", "MEMBER_ID"]
found = post("http://127.0.0.1:3000/analyze",
             {"text": TEXT, "language": "en", "entities": ENTITIES, "ad_hoc_recognizers": RECOGNIZERS})
clean = post("http://presidio-anonymizer:3000/anonymize", {"text": TEXT, "analyzer_results": found})
print("entities:", ",".join(sorted({f["entity_type"] for f in found})))
print("redacted:", clean["text"])
