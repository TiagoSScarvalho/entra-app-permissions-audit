# Read the report before acting

1. **Coverage**: a complete collection is different from a partially returned one. All counts in a partial run are observations, not a tenant-wide conclusion.
2. **Client**: match `ClientObjectId` to Enterprise applications. Display names are not unique; `ClientAppId` is not the tenant-local Object ID.
3. **Resource**: `ResourceObjectId` identifies the API's local service principal. `ResourceAppId` identifies its application. A role name on a custom API must not inherit Microsoft Graph's risk classification.
4. **Kind**: delegated permissions act on behalf of a signed-in user; application assignments allow app-only authorization. Policies and the API's own controls still matter.
5. **Consent scope**: `AllPrincipals` is all-user delegated consent; `Principal` is specific-user delegated consent. The user ID in the latter is not the consent actor. Application assignment data does not provide the original approving administrator.
6. **Resolution**: `Resolved` means a matching enabled permission definition was found. It does not prove that the app exercised it. `DefaultAccess`, `DefinitionDisabled`, missing definitions and incompatible assignments require separate review.
7. **Priority**: `High` starts a business-need conversation. `NotClassified` means the supplied rule set did not classify the permission. Check custom APIs and permissions absent from the rule set too.

The zero app-role GUID represents default access without a specific named app role. The report retains that distinction. Disabled clients also remain visible; their stored grants should not disappear from an inventory merely because sign-in is disabled today.

The tool does not calculate effective access. Preauthorized permissions, API-specific grants/ACLs, Exchange application RBAC, Teams resource-specific consent, selected-site assignments and Entra directory roles need their own review. It does not inspect app owners, credentials or activity. A complete direct-grant inventory can coexist with access granted elsewhere.

## Turn a finding into a decision

For each high-impact or unknown grant, record the application owner, business use, affected API/data, required permission type, proposed narrower scope, change approver and validation plan. Use the separate credential/owner audit for locally registered apps when applicable. Do not revoke a grant just because the report marks it High. Read-only discovery and approved remediation are separate tasks.

## Reconcile the files

`summary.json.PermissionRows` equals the number of rows in `permissions.csv`. `DelegatedRows` counts expanded delegated scopes. `ApplicationAssignments` counts direct application assignments. Neither is a unique application count; use the Applications total for included clients. `IncompleteSections` counts failed/unattempted collection reads, not unresolved definitions. `UnresolvedOrSpecialRows` captures the latter.

CSV string fields with formula-like leading characters are prefixed with an apostrophe. HTML values are escaped. If a spreadsheet displays an extra apostrophe, compare the original identifier in the JSON/portal rather than removing safety handling from the exporter.
