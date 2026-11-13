# Release review record

Release: 1.0.0. Reviewed: 13 November 2026. The live pilot used 1.0.0-rc.1; the stable release changes the version label and documentation, with no collection or reporting logic changes.

## Offline validation

51 assertions passed, zero failed. Covered: wrong-tenant/scope preflight, type exclusions, delegated consent semantics, resource-specific app-role resolution, disabled/unknown/default roles, CSV formula and HTML injection handling, pagination boundaries, malformed results, wrapped 401/429/503 errors, 403 partial results, output preservation, complete empty collections, selected-object validation and HTML/CSV/summary reconciliation.

These checks use synthetic fixtures. They are not tenant evidence. Run `tests/Run-Tests.ps1` to reproduce them without authentication or a Graph dependency.

## Tenant validation

The portal was inspected in read-only mode. Microsoft Graph Command Line Tools has an existing delegated Directory.Read.All grant. A selected enterprise application has both delegated and application Mail.Send grants; the portal's permission details were captured separately. No grant was added or removed for those checks.

The four-application pilot completed on 13 November 2026, 09:24:48–09:24:51 UTC, in interactive PowerShell 7.7.0 with Microsoft.Graph.Authentication 2.39.0 and the Directory.Read.All connection requested by the helper. No code changes were needed after this live run.

| Measure | Observed result |
|---|---:|
| Included clients | 4 |
| Complete collection reads | 13 |
| Incomplete sections | 0 |
| Delegated permission rows | 76 |
| Application assignments | 2 |
| Total permission rows | 78 |
| High-priority rows | 5 |
| Unresolved rows | 2 |

18 reconciliation checks passed. Per-client totals match the exported rows. The two mail-sending samples match the portal: one has Mail.Send in both kinds plus delegated User.Read; the other has application Mail.Send and delegated User.Read. The profile-reader control has complete empty collections and both portal consent tabs are empty. Microsoft Graph Command Line Tools has 46 all-user and 27 specific-user delegated rows, matching the Admin consent and User consent tabs.

The two unresolved rows are stored delegated Device.ReadWrite.All values in separate consent scopes. The portal shows the claim with blank display name/description. The current Microsoft Graph permission reference has an application entry and no delegated entry for this value. Both rows remain Review; no effective-access conclusion or remediation was performed.

This is a selected-client validation, not a tenant-wide scale test or a least-privilege directory-role test. The portal check used an existing administrative session. Raw reports, identifiers and private screenshots are excluded from the public package.
