# Entra App Permissions Audit

A read-only PowerShell inventory of direct OAuth delegated consent and application permission assignments on ordinary enterprise applications. Produces a local HTML report, three CSV files and a JSON run summary.

**Version:** `1.0.0` · **Author:** [Tiago Carvalho](https://www.tiagoscarvalho.com) · MIT licence.

[Download v1.0.0](https://github.com/TiagoSScarvalho/entra-app-permissions-audit/releases/download/v1.0.0/entra-app-permissions-audit-v1.0.0.zip) · [ZIP checksum](https://github.com/TiagoSScarvalho/entra-app-permissions-audit/releases/download/v1.0.0/entra-app-permissions-audit-v1.0.0.zip.sha256.txt) · [Release notes](https://github.com/TiagoSScarvalho/entra-app-permissions-audit/releases/tag/v1.0.0) · [Report a bug](https://github.com/TiagoSScarvalho/entra-app-permissions-audit/issues)

The collector makes Microsoft Graph GET requests only. It does not install software, sign in, consent, revoke permissions or change applications. The author header is attribution, not an Authenticode signature. Reports are never uploaded to GitHub.

[Read the practical guide with tenant screenshots](https://www.tiagoscarvalho.com/azure-entra-id/entra-oauth-permissions-audit-powershell)

## Start here

1. Read the scope below and extract the complete package.
2. Review the launcher, companion module and `review-rules.json`.
3. Connect with the read permission, then select one enterprise application by Object ID.
4. Check coverage before interpreting findings; compare the rows with Entra.
5. Expand to all ordinary Application-type service principals only when the pilot agrees.

## Scope

| Included | Outside this release |
|---|---|
| Local service principals of type `Application`, both Microsoft and third-party | Managed identities and explicit derived agent objects |
| Direct `oauth2PermissionGrants`, one row per scope | Requested permissions in app-registration manifests and preauthorized access |
| Client service principal `appRoleAssignments` | Directory roles, Exchange application RBAC, Teams resource-specific consent and selected-site assignments |
| Permission definitions resolved on the resource service principal | Usage, last activity, consent actor, credentials, owners and proof of effective data access |

`AllPrincipals` means delegated consent for all users. It does not turn a delegated grant into an application permission. `PrincipalUserId` identifies the user on whose behalf the client may act; it is not the approving administrator. One delegated grant can contain several scopes, so permission rows are not a count of grant objects.

`High` means a documented review rule matched, not that an application is malicious. Rules cover selected Microsoft Graph permissions by resource application ID, permission kind and exact value. Unknown/custom API permissions remain `NotClassified`; unresolved or special cases become `Review`. Neither is a safe verdict. See [interpretation](docs/INTERPRETATION.md).

## Requirements

- PowerShell 7.4+ and official `Microsoft.Graph.Authentication` 2.37.0+.
- Global cloud, delegated work/school sign-in in the same PowerShell process as the audit.
- `Directory.Read.All` with appropriate admin consent. This is the documented least privileged read scope for delegated grant inventory, and also supports service principal and app-role assignment reads.
- A supported directory role for these endpoints. `Directory Readers` is listed by Microsoft for the required delegated reads. Role eligibility alone is not activation. Global Administrator is not required to run the collector.

This scope reads directory-wide metadata even when the script selects a small pilot. Selection limits the collector's queries, not the permission granted to the Graph client. Obtain consent through your organisation's approved process. Do not add write permissions to perform an audit. The collector accepts an existing `Directory.ReadWrite.All` context but never requests it or uses write operations.

```powershell
# Install only if needed, from the official PowerShell Gallery package.
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -MinimumVersion 2.37.0
Import-Module Microsoft.Graph.Authentication

$tenantId = '<your-tenant-guid>'
Connect-MgGraph -TenantId $tenantId -Scopes 'Directory.Read.All' -ContextScope Process -NoWelcome
Get-MgContext | Select-Object TenantId, Account, AuthType, Environment
```

Review unexpected consent prompts instead of accepting them to clear an error. If WAM reports that a window handle must be configured, use a normal interactive PowerShell 7 window. Do not bypass Conditional Access or execution policy to fix an authentication-window problem.

## Pilot one enterprise application

Open **Entra ID → Enterprise apps → All applications → your application → Overview**. Copy its **Object ID**. Do not use the Application (client) ID or the app registration's Object ID.

Open PowerShell in the extracted package folder, which contains the launcher, `.psm1` module and JSON rules. Replace the placeholders:

```powershell
$clientObjectId = '<enterprise-application-object-guid>'
./Get-EntraAppPermissionsAudit.ps1 -ExpectedTenantId $tenantId `
    -ServicePrincipalObjectId $clientObjectId -OutputPath ./PilotAudit
```

Multiple selected Object IDs can be supplied as an array. Existing output folders are refused. Use a new folder for each run to preserve evidence. No local administrator elevation is required by this collector.

## All ordinary application service principals

```powershell
./Get-EntraAppPermissionsAudit.ps1 -ExpectedTenantId $tenantId `
    -AllApplications -OutputPath ./TenantAudit
Disconnect-MgGraph
```

The portal's default Enterprise Applications filter and this Graph collection may not show the same population. Compare by Object ID and the declared scope, not the portal's headline count. Each included client needs two grant reads; resource definitions are cached, and paging is followed. Large tenants take longer. This is an interactive audit, not an unattended scheduler.

## Output and verification

| File | Meaning |
|---|---|
| `report.html` | Self-contained human-readable report; no external scripts, fonts or telemetry |
| `applications.csv` | Client scope, enabled state, collection status and observed counts |
| `permissions.csv` | Grant/resource identifiers, type, scope, resolution and review reason |
| `coverage.csv` | Every collection read, completeness, pages and safe error category |
| `summary.json` | Version, UTC start/end, scope and reconciled counts |

Open `report.html` in a browser. Confirm **Coverage** first. A failed read produces `PARTIAL`, not a successful empty inventory. After a final 401, 429 or 5xx response, remaining requests stop and are marked unattempted; the Graph SDK handles its normal retries. Do not repeatedly rerun a throttled tenant.

In Entra, open the same enterprise application → **Permissions**, inspect **Admin consent** and **User consent**, and select a permission for its details. Match resource API, claim value, type and consent scope. A row under Admin consent can still be delegated. A separate **Preauthorized access** tab, when present, is outside this collector's direct-grant inventory. Recently changed grants can take time to replicate.

`COMPLETE for the stated reads` means the selected collection reads succeeded. It is not a complete effective-access review or a security certification. Special/unresolved rows remain a separate count. No direct grants returned is not proof of no possible access.

## Integrity and privacy

Follow your organisation's script review/signing process; this version is unsigned. Compare the downloaded ZIP with its release checksum before extraction. Inside the ZIP, `SHA256SUMS.txt` lists the individual file hashes. Use `Get-FileHash -Algorithm SHA256` to compare files. A checksum delivered with the package detects changes but does not independently authenticate the publisher.

Reports contain internal app names, tenant and service-principal IDs and potentially user object IDs. Keep them private; `.gitignore` is only a safeguard, not a data-loss control. Do not attach raw reports to public issues. The collector does not read mail, files, tokens, credential values or raw server-error messages. See [SECURITY.md](SECURITY.md).

## Validation

Run `./tests/Run-Tests.ps1`. The offline suite uses synthetic data and mocked Graph calls; it does not connect to a tenant. The release review record distinguishes these checks from live validation: [VALIDATION.md](docs/VALIDATION.md).

The four-client pilot on 13 November 2026 completed all 13 reads and returned 78 permission rows. CSV counts and sampled portal permissions were reconciled. Two unresolved stored delegated claims were retained for investigation. This validates the stated pilot, not tenant-wide scale or effective access.

## Microsoft references

- [List delegated permission grants](https://learn.microsoft.com/en-us/graph/api/oauth2permissiongrant-list?view=graph-rest-1.0)
- [List application assignments for a client service principal](https://learn.microsoft.com/en-us/graph/api/serviceprincipal-list-approleassignments?view=graph-rest-1.0)
- [List service principals](https://learn.microsoft.com/en-us/graph/api/serviceprincipal-list?view=graph-rest-1.0)
- [Delegated grant properties](https://learn.microsoft.com/en-us/graph/api/resources/oauth2permissiongrant?view=graph-rest-1.0)
- [App-role assignment properties](https://learn.microsoft.com/en-us/graph/api/resources/approleassignment?view=graph-rest-1.0)
- [Review enterprise application permissions](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/manage-application-permissions)
- [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference)
- [Microsoft Graph throttling](https://learn.microsoft.com/en-us/graph/throttling)

