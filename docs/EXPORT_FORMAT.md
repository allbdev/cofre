# The `.cofre` export format, version 1

An export file holds every secret, encrypted with a key derived from a passphrase the user types at export time. It is the only way secrets leave the Keychain, and it's meant to be readable by other tools: everything below is standard (PBKDF2, AES-GCM, JSON, base64).

## File

UTF-8 JSON, at most 10 MB:

```json
{
  "format": "cofre-export",
  "version": 1,
  "kdf": {
    "algorithm": "PBKDF2-HMAC-SHA256",
    "iterations": 600000,
    "salt": "<base64, 16 random bytes>"
  },
  "cipher": {
    "algorithm": "AES-256-GCM",
    "nonce": "<base64, 12 random bytes>"
  },
  "ciphertext": "<base64, encrypted payload followed by the 16-byte tag>"
}
```

## Key and encryption

1. `key = PBKDF2-HMAC-SHA256(passphrase as UTF-8, salt, iterations, 32 bytes)`
2. `ciphertext || tag = AES-256-GCM(key, nonce, payload, aad)`
3. `aad` (additional authenticated data) is the UTF-8 string
   `cofre-export/1/PBKDF2-HMAC-SHA256/<iterations>/<salt base64>/AES-256-GCM`,
   so changing any header field makes decryption fail.

A new salt and nonce are generated for every export. Passphrases must be at least 12 characters.

## Payload (after decryption)

```json
{
  "exportedAt": "2026-11-25T14:03:00Z",
  "items": [
    {
      "name": "Stripe secret key (prod)",
      "value": "<base64 of the value's bytes>",
      "createdAt": "2026-11-01T09:00:00Z",
      "updatedAt": "2026-11-20T18:30:00Z"
    }
  ]
}
```

Values are base64 so any bytes survive (they're UTF-8 text in practice).

## Reading rules

An importer must reject, with a clear message:

- a file over 10 MB, not JSON, or with `format` ≠ `cofre-export`;
- a `version` it doesn't know (only `1` exists);
- an unknown KDF or cipher algorithm;
- `iterations` below 100 000 or above 10 000 000 (protects against weak or deliberately slow files);
- a salt that isn't 16 bytes or a nonce that isn't 12;
- a failed decryption: wrong passphrase or a modified file (GCM can't tell them apart, so the message says both);
- a payload with an invalid name (see `PLAN.md` D9).

Duplicate names inside one file are kept as they are and treated as clashes by the import planner.

## Decrypting by hand

With Python and `cryptography`, for an emergency without the app:

```python
import base64, json, hashlib
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

f = json.load(open("backup.cofre"))
salt = base64.b64decode(f["kdf"]["salt"])
key = hashlib.pbkdf2_hmac("sha256", b"your passphrase", salt, f["kdf"]["iterations"], 32)
aad = f'cofre-export/1/PBKDF2-HMAC-SHA256/{f["kdf"]["iterations"]}/{f["kdf"]["salt"]}/AES-256-GCM'.encode()
payload = AESGCM(key).decrypt(base64.b64decode(f["cipher"]["nonce"]), base64.b64decode(f["ciphertext"]), aad)
for item in json.loads(payload)["items"]:
    print(item["name"], base64.b64decode(item["value"]).decode())
```
