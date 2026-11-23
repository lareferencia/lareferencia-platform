# Mixed validation fixture

This source exercises the distinction between a record's validity, an individual rule's result and the values retained for that rule. Run it in a disposable development installation. The provider serves six fixed Dublin Core records through the OAI-PMH verbs used by a full harvest. [OAI records](oai/ListRecords.xml) · [Importable validator](validator.json)

| OAI identifier suffix | Input of interest | Record | Failed rules |
| --- | --- | --- | --- |
| `clean` | Title, language `es`, type `article` | Valid | None |
| `optional-only` | Language `en`, type `poster` | Valid | Type (optional) |
| `missing-title` | Language `es`, type `dataset`, title absent | Invalid | Title |
| `wrong-language` | Language `xx`, type `article` | Invalid | Language |
| `missing-fields` | Identifier only | Invalid | Title, Language, Type |
| `mixed-values` | Languages `en` and `zz`, type `article` | Valid | None. Language requires one accepted value and retains both outcomes. |

Every identifier starts with `oai:qa-mixed:`. Each rule passes four records and fails two. Of the three invalid records, two fail one mandatory rule and one fails both. There are no transformations.

## Reproduce the snapshots

1. In the test copy, serve the XML files under the name `fixture-oai`, reachable from the harvester. For example, from the platform root, set `TEST_NETWORK` to the name of the copy's Docker network and run the command below.
2. In the admin's validator screen import `validator.json`, or send the file as JSON to `POST /api/v5/validators/import`. Create a new source with acronym `QAMIX`, provider `http://fixture-oai/oai`, metadata prefix `oai_dc`, store format `xoai`, and the imported validator. Leave the schedule empty. Grant the dashboard test account read access to this source.
3. Open the source's **Validation** action configuration and enable `DETAILED_DIAGNOSE`. Through the management API, read `GET /api/v5/networks/{id}/actions/VALIDATION_ACTION`, preserve `enabled`, `scheduleEnabled` and the other configuration fields, set `configuration.DETAILED_DIAGNOSE`, and PUT the updated action to the same URL. Read it back and check `effectiveConfiguration.DETAILED_DIAGNOSE`. An explicit action option takes precedence over the legacy source property.
4. Run a **full harvest**, wait for `HARVESTING_FINISHED_VALID`, then run **Validation** and wait for `VALID`. Record the snapshot ID. Repeat with the action option off to create a second snapshot. Re-enable the option for future runs. Each full harvest and validation uses the same six source records.
5. Run the verifier with a dashboard-role account in the copy. It checks validity, failed rules, filtered cohorts, historical flags, paged frequencies and the visible actions in Chrome. The snapshot IDs are arguments so a fresh database can allocate its own IDs. [Verifier](verify.py)

```sh
docker run -d --name qa-mixed-oai --network "$TEST_NETWORK" --network-alias fixture-oai \
  -v "$PWD/testing/dashboard-validation/oai.conf:/etc/nginx/conf.d/default.conf:ro" \
  -v "$PWD/testing/dashboard-validation/oai:/usr/share/nginx/html:ro" nginx:stable-alpine

# Requires Python Playwright and Chrome. The verifier prompts for the account password.
python3 testing/dashboard-validation/verify.py http://dashboard.localhost:53190 8 \
  --summary-snapshot 10 --screenshots /tmp/qa-mixed-captures
```

## Observed on 21 November 2026

On the local copy, source 460 used validator 6. In snapshot **#8**, title (rule 77) showed **Sin recuento**. Language (78) and Type (79) both offered **Ver ocurrencias**. Language retained four accepted values (`es` twice, `en` twice) and three rejected values (`xx`, `zz` and the missing-field marker, once each). Restricting the report to records that passed Language left exactly one rejected occurrence, `zz`.

In **#9** the legacy source property had been set to false, but the effective validation action still had capture enabled. In **#10** capture was disabled on the action itself. All three rows displayed **Sin recuento** and frequency queries returned zero stored values. Both #8 and #10 showed six records, three valid and three invalid after the action was re-enabled. The verifier checked the record identities and each rule result on both snapshots after this change.

### Verification of the pinned modules

The dashboard (`6c38597`) and harvester (`e7d5a7a`) were built from clean checkouts with core-lib (`474dc14`). In a second disposable copy, the gateway verifier passed on archived snapshots #8 and #10. Importing the committed validator and running the full harvest and validation workers again produced #11 (capture enabled) and #12 (capture disabled). Each snapshot had three valid and three invalid records. The verifier also checked the filtered rule outcomes, the frequency values and the visible actions on both fresh snapshots.
