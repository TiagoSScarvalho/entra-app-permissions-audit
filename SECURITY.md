# Security and report handling

This tool only sends GET requests to Microsoft Graph in the Global cloud using the caller's delegated session. It neither creates an application nor grants permissions. Directory.Read.All is broad directory read access; approve it through your normal process.

Do not publish raw reports, account details, tenant IDs, object IDs, tokens, consent screenshots or customer data in issues. A reproducible report should contain the version, PowerShell/Graph module versions, operation name and safe error category with synthetic examples. For a sensitive issue, use the contact route on https://www.tiagoscarvalho.com instead of a public issue.

The supplied rules are a review aid, not a malware detector or remediation policy. Never automate revocation from their priority labels.
