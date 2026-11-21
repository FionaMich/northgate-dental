# Trusted certificates

`supabase-root-2021.crt` is Supabase's public root CA (valid to 2031-04-26), which signs the database and pooler
certificates. n8n trusts it through `NODE_EXTRA_CA_CERTS`, so its Postgres connections verify the server instead of
skipping the check.

SHA-256 fingerprint, checked on 2026-11-21 against both the copy Supabase publishes
(`https://supabase-downloads.s3-ap-southeast-1.amazonaws.com/prod/ssl/prod-ca-2021.crt`) and the chain the pooler
presents:

```
80:70:25:AD:50:D4:ED:21:9D:2C:9C:7D:29:9C:00:4F:82:4E:B0:0C:F7:F6:5A:FE:F6:07:D0:7B:72:E6:CA:FA
```

Check it again with `openssl x509 -in infra/certs/supabase-root-2021.crt -noout -fingerprint -sha256`.
