# CloudKit Container Schema

- Team: `ZRY7UHFY75`
- Container: `iCloud.com.lyonzhu.NutritionDiary`
- Private custom zone: `NutritionDiary`
- Record type: `NutritionSyncRecord`

## Required fields

| Field | CloudKit type |
| --- | --- |
| `recordKind` | String |
| `businessRecordID` | String |
| `schemaVersion` | Int64 |
| `payload` | Bytes |
| `updatedAt` | Date |
| `deletedAt` | Date |
| `deviceID` | String |

## Authentication

CloudKit management tokens are saved only in the login Keychain:

```sh
make cloudkit-auth
```

The token must come from CloudKit Console and must not be passed on the command line, written to this directory, committed, logged, or included in backups.

## Development workflow

1. Build and install the Development-signed iOS app.
2. Create or modify one local diary record and wait for sync.
3. Confirm the custom zone and `NutritionSyncRecord` exist in CloudKit Console.
4. Export and validate the schema:

```sh
make cloudkit-schema
./Scripts/cloudkit-schema.sh validate-development
```

`NutritionDiary-development.ckdb` is the versioned source of truth after export.

## Production deployment

1. Confirm all required fields and indexes in Development.
2. Open CloudKit Console for the production environment and deploy the validated Development schema.
3. Save a short-lived user token for record verification:

```sh
./Scripts/cloudkit-schema.sh auth-user
```

4. Export Production and compare:

```sh
./Scripts/cloudkit-schema.sh export-production
./Scripts/cloudkit-schema.sh validate-production
./Scripts/cloudkit-schema.sh compare
```

Production deployment status on 2026-10-17:

- iPhone and Mac Development sync passed with 6 active records, 0 pending uploads, and 0 conflicts.
- CloudKit Console deployed the Development schema to Production successfully.
- `NutritionDiary-production.ckdb` is the deployed schema snapshot; its SHA256 matches the Development export.
- The schema contains `NutritionSyncRecord`, `Users`, the custom `businessRecordID` field, and 17 indexes for `NutritionSyncRecord`.
