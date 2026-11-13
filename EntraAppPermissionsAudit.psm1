#requires -Version 7.4
# Tiago Carvalho | https://www.tiagoscarvalho.com | MIT
Set-StrictMode -Version Latest
$script:Version = '1.0.0'

function Get-Field($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return ,$Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return ,$property.Value }
    return $null
}

function Test-Field($Object, [string]$Name) {
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Get-SafeError($Record) {
    $pending = [System.Collections.Generic.Queue[Exception]]::new()
    $seen = [System.Collections.Generic.HashSet[Exception]]::new()
    $statuses = [System.Collections.Generic.List[int]]::new()
    if ($Record.Exception -is [Exception]) { $pending.Enqueue($Record.Exception) }
    while ($pending.Count -and $seen.Count -lt 32) {
        $exception = $pending.Dequeue()
        if (-not $seen.Add($exception)) { continue }
        foreach ($candidate in @((Get-Field $exception 'ResponseStatusCode'), (Get-Field $exception 'StatusCode'), (Get-Field (Get-Field $exception 'Response') 'StatusCode'))) {
            $code = 0
            if ($null -ne $candidate) { try { $code = [int]$candidate } catch { } }
            if ($code -ge 400 -and $code -le 599) { $statuses.Add($code); break }
        }
        foreach ($inner in @($exception.InnerException, (Get-Field (Get-Field $exception 'ErrorRecord') 'Exception'))) {
            if ($inner -is [Exception]) { $pending.Enqueue($inner) }
        }
        if ($exception -is [AggregateException]) {
            foreach ($inner in $exception.InnerExceptions) { $pending.Enqueue($inner) }
        }
    }
    $status = 0
    foreach ($code in $statuses) {
        if (-not $status) { $status = $code }
        if ($code -eq 429 -or $code -eq 401 -or $code -ge 500) { $status = $code; break }
    }
    $category = switch ($status) {
        401 { 'AuthenticationRequired' } 403 { 'AccessDenied' } 404 { 'NotFound' }
        429 { 'Throttled' } { $_ -ge 500 } { 'ServiceUnavailable' } default { 'QueryFailed' }
    }
    [pscustomobject]@{ HttpStatus = $status; Category = $category }
}

function Read-GraphCollection([string]$Uri, [hashtable]$RunState) {
    $items = [System.Collections.Generic.List[object]]::new()
    $visited = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $initial = [uri]$Uri
    $complete = $true; $errorCategory = ''; $httpStatus = 0; $pageCount = 0
    while ($Uri) {
        if ($RunState.StopRequests) { $complete = $false; $errorCategory = 'NotAttemptedAfterServiceFailure'; break }
        $pageUri = $null
        if (-not [uri]::TryCreate($Uri,[UriKind]::Absolute,[ref]$pageUri) -or $pageUri.Scheme -ne 'https' -or $pageUri.Host -ne 'graph.microsoft.com' -or $pageUri.Port -ne 443 -or $pageUri.UserInfo -or $pageUri.Fragment -or $pageUri.AbsolutePath -ne $initial.AbsolutePath -or -not $visited.Add($Uri)) {
            $complete = $false; $errorCategory = 'InvalidPagination'; break
        }
        try {
            $page = Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType PSObject -ErrorAction Stop
            $values = Get-Field $page 'value'
            if (-not (Test-Field $page 'value') -or $values -isnot [System.Collections.IList]) { throw 'Unexpected collection shape.' }
            foreach ($item in $values) { if ($null -eq $item -or -not (Get-Field $item 'id')) { throw 'Unexpected collection item.' }; $items.Add($item) }
            $pageCount++
            $Uri = [string](Get-Field $page '@odata.nextLink')
        } catch {
            $safe = Get-SafeError $_
            $complete = $false; $errorCategory = $safe.Category; $httpStatus = $safe.HttpStatus
            if ($httpStatus -eq 429 -or $httpStatus -eq 401 -or $httpStatus -ge 500) { $RunState.StopRequests = $true }
            break
        }
    }
    [pscustomobject]@{ Items = $items.ToArray(); Complete = $complete; ErrorCategory = $errorCategory; HttpStatus = $httpStatus; Pages = $pageCount }
}

function ConvertTo-CsvCell($Value) {
    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    if ($Value -is [string] -and $text -match '^[\s\p{Cf}]*[=+@-]') { $text = "'" + $text }
    '"' + $text.Replace('"','""') + '"'
}

function Write-AuditCsv([string]$Path, [object[]]$Rows, [string[]]$Columns) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(($Columns | ForEach-Object { ConvertTo-CsvCell $_ }) -join ',')
    foreach ($row in $Rows) { $lines.Add(($Columns | ForEach-Object { ConvertTo-CsvCell (Get-Field $row $_) }) -join ',') }
    [IO.File]::WriteAllLines($Path, $lines, [Text.UTF8Encoding]::new($true))
}

function ConvertTo-HtmlTable([object[]]$Rows, [string[]]$Columns, [string]$Label) {
    $encode = { param($v) [Net.WebUtility]::HtmlEncode([string]$v) }
    if (-not $Rows.Count) { return '<p>No rows returned for this table. Check coverage before interpreting an empty result.</p>' }
    $head = ($Columns | ForEach-Object { '<th scope="col">' + (& $encode $_) + '</th>' }) -join ''
    $body = foreach ($row in $Rows) { '<tr>' + (($Columns | ForEach-Object { '<td>' + (& $encode (Get-Field $row $_)) + '</td>' }) -join '') + '</tr>' }
    '<div class="table" role="region" tabindex="0" aria-label="' + (& $encode $Label) + '"><table><thead><tr>' + $head + '</tr></thead><tbody>' + ($body -join '') + '</tbody></table></div>'
}

function Test-IncludedClient($Client) {
    $type = [string](Get-Field $Client '@odata.type')
    (($type -eq '' -or $type -eq '#microsoft.graph.servicePrincipal') -and (Get-Field $Client 'servicePrincipalType') -eq 'Application')
}

function Add-Coverage($List, [string]$Operation, [string]$ObjectId, $Result) {
    $List.Add([pscustomobject][ordered]@{ Operation=$Operation; ObjectId=$ObjectId; Status=$(if ($Result.Complete) {'Complete'} else {'Incomplete'}); ReturnedItems=$Result.Items.Count; Pages=$Result.Pages; HttpStatus=$Result.HttpStatus; ErrorCategory=$Result.ErrorCategory })
}

function Read-Resource([string]$Id, [hashtable]$Cache, [hashtable]$State, $Coverage) {
    if ($Cache.ContainsKey($Id)) { return $Cache[$Id] }
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($Id,[ref]$parsed) -or $parsed -eq [guid]::Empty) {
        $result = [pscustomobject]@{Items=@();Complete=$false;Pages=0;HttpStatus=0;ErrorCategory='InvalidResourceId'}
    } else {
        $uri = 'https://graph.microsoft.com/v1.0/servicePrincipals?$filter=id%20eq%20%27' + $Id + '%27&$select=id,appId,displayName,appRoles,oauth2PermissionScopes'
        $result = Read-GraphCollection $uri $State
        if ($result.Complete -and $result.Items.Count -ne 1) { $result.Complete=$false; $result.ErrorCategory='ResourceNotReturned' }
        if ($result.Complete) {
            $resource = $result.Items[0]
            if ((Get-Field $resource 'id') -ne $Id -or -not (Test-Field $resource 'appRoles') -or -not (Test-Field $resource 'oauth2PermissionScopes') -or $null -eq (Get-Field $resource 'appRoles') -or $null -eq (Get-Field $resource 'oauth2PermissionScopes')) {
                $result.Complete=$false; $result.ErrorCategory='ResourceDefinitionIncomplete'
            }
        }
    }
    Add-Coverage $Coverage 'ResourceDefinitions' $Id $result
    $Cache[$Id] = $result
    return $result
}

function Get-ReviewRule([string]$ResourceAppId, [string]$Kind, [string]$Permission, [object[]]$Rules) {
    $match = @($Rules | Where-Object { $_.ResourceAppId -eq $ResourceAppId -and $_.Kind -eq $Kind -and $_.Permission -ceq $Permission })
    if ($match.Count -eq 1) { return $match[0] }
    [pscustomobject]@{Priority='NotClassified';Reason='Not in the selected review rules. This is not a low-risk verdict.'}
}

function ConvertTo-PermissionRow($Client, $Grant, [string]$Kind, [string]$ScopeValue, $ResourceRead, [bool]$CollectionComplete, [object[]]$Rules) {
    $resource = if ($ResourceRead.Complete) { $ResourceRead.Items[0] } else { $null }
    $clientId = [string](Get-Field $Client 'id')
    $resourceAppId = [string](Get-Field $resource 'appId')
    $permissionId = ''; $permission = $ScopeValue; $resolution = 'Unresolved'; $enabled = $null
    $consent = ''; $userId = ''; $grantScope = ''; $created = ''; $validGrant = $true
    if ($Kind -eq 'Delegated') {
        $consent = [string](Get-Field $Grant 'consentType'); $userId = [string](Get-Field $Grant 'principalId')
        $grantScope = switch ($consent) { 'AllPrincipals' {'All users (delegated)'} 'Principal' {'Specific user (delegated)'} default {'Unknown consent scope'} }
        $parsedUser = [guid]::Empty
        $validGrant = (Get-Field $Grant 'clientId') -eq $clientId -and (($consent -eq 'AllPrincipals' -and -not $userId) -or ($consent -eq 'Principal' -and [guid]::TryParse($userId,[ref]$parsedUser) -and $parsedUser -ne [guid]::Empty))
        $definitions = @((Get-Field $resource 'oauth2PermissionScopes') | Where-Object { (Get-Field $_ 'value') -ceq $ScopeValue })
    } else {
        $consent = 'NotAvailableFromAssignment'; $grantScope = 'Application (no signed-in user)'
        $permissionId = [string](Get-Field $Grant 'appRoleId'); $permission = ''
        $created = [string](Get-Field $Grant 'createdDateTime')
        $validGrant = (Get-Field $Grant 'principalId') -eq $clientId -and (Get-Field $Grant 'principalType') -eq 'ServicePrincipal'
        $definitions = @((Get-Field $resource 'appRoles') | Where-Object { (Get-Field $_ 'id') -eq $permissionId })
    }
    if (-not (Get-Field $Grant 'id')) { $validGrant=$false }
    if (-not $validGrant) { $resolution='InvalidGrantMetadata' }
    elseif ($Kind -eq 'Application' -and $permissionId -eq [guid]::Empty.ToString()) { $resolution='DefaultAccess'; $permission='Default access (no named app role)' }
    elseif ($resource -and $definitions.Count -eq 1 -and (Get-Field $definitions[0] 'value')) {
        $definition = $definitions[0]
        $permission = [string](Get-Field $definition 'value'); $permissionId=[string](Get-Field $definition 'id')
        $enabled = Get-Field $definition 'isEnabled'
        $resolution = if ($null -eq $enabled) { 'DefinitionStateUnknown' } elseif (-not $enabled) { 'DefinitionDisabled' } else { 'Resolved' }
        $members=Get-Field $definition 'allowedMemberTypes'
        if ($Kind -eq 'Application' -and 'Application' -notin $members) { $resolution='IncompatibleRoleDefinition' }
    }
    $rule = Get-ReviewRule $resourceAppId $Kind $permission $Rules
    if ($resolution -ne 'Resolved') { $rule=[pscustomobject]@{Priority='Review';Reason='Check grant and resource definition: ' + $resolution + '. No effective access conclusion.'} }
    [pscustomobject][ordered]@{
        ClientObjectId=$clientId; ClientAppId=[string](Get-Field $Client 'appId'); ClientName=[string](Get-Field $Client 'displayName')
        ClientEnabled=(Get-Field $Client 'accountEnabled'); GrantId=[string](Get-Field $Grant 'id'); Kind=$Kind
        ResourceObjectId=[string](Get-Field $Grant 'resourceId'); ResourceAppId=$resourceAppId; ResourceName=[string](Get-Field $resource 'displayName')
        Permission=$permission; PermissionId=$permissionId; ConsentType=$consent; PrincipalUserId=$userId; GrantScope=$grantScope
        AssignmentCreatedUtc=$created; DefinitionEnabled=$enabled; Resolution=$resolution
        CollectionRead=$(if ($CollectionComplete) {'Complete'} else {'Incomplete'}); ReviewPriority=$rule.Priority; ReviewReason=$rule.Reason
    }
}

function Write-PermissionsReport([object[]]$Applications, [object[]]$Permissions, [object[]]$Coverage, [string]$OutputPath, [string]$TenantId, [DateTimeOffset]$AsOf, [string]$Scope) {
    $appColumns=@('ObjectId','AppId','DisplayName','ClientType','Scope','Enabled','DelegatedRead','ApplicationRead','ObservedDelegatedPermissions','ObservedApplicationAssignments','HighPriorityRows','GrantState')
    $permissionColumns=@('ClientObjectId','ClientAppId','ClientName','ClientEnabled','GrantId','Kind','ResourceObjectId','ResourceAppId','ResourceName','Permission','PermissionId','ConsentType','PrincipalUserId','GrantScope','AssignmentCreatedUtc','DefinitionEnabled','Resolution','CollectionRead','ReviewPriority','ReviewReason')
    $coverageColumns=@('Operation','ObjectId','Status','ReturnedItems','Pages','HttpStatus','ErrorCategory')
    Write-AuditCsv (Join-Path $OutputPath 'applications.csv') $Applications $appColumns
    Write-AuditCsv (Join-Path $OutputPath 'permissions.csv') $Permissions $permissionColumns
    Write-AuditCsv (Join-Path $OutputPath 'coverage.csv') $Coverage $coverageColumns
    $incomplete=@($Coverage | Where-Object Status -ne 'Complete').Count
    $unresolved=@($Permissions | Where-Object Resolution -ne 'Resolved').Count
    $included=@($Applications | Where-Object Scope -eq 'Included').Count
    $excluded=@($Applications | Where-Object Scope -ne 'Included').Count
    $high=@($Permissions | Where-Object ReviewPriority -eq 'High').Count
    $status=if ($incomplete) {'PARTIAL - review coverage'} else {'COMPLETE for the stated reads'}
    $summary=[pscustomobject][ordered]@{Version=$script:Version;TenantId=$TenantId;StartedUtc=$AsOf.ToString('o');FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o');Scope=$Scope;ReportStatus=$status;Applications=$included;ExcludedObjects=$excluded;PermissionRows=$Permissions.Count;DelegatedRows=@($Permissions | Where-Object Kind -eq 'Delegated').Count;ApplicationAssignments=@($Permissions | Where-Object Kind -eq 'Application').Count;HighPriorityRows=$high;UnresolvedOrSpecialRows=$unresolved;IncompleteSections=$incomplete;ReportPath=(Join-Path $OutputPath 'report.html')}
    $summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputPath 'summary.json') -Encoding utf8
    $appTable=ConvertTo-HtmlTable $Applications @('DisplayName','Scope','DelegatedRead','ApplicationRead','ObservedDelegatedPermissions','ObservedApplicationAssignments','HighPriorityRows','GrantState') 'Client applications'
    $permissionTable=ConvertTo-HtmlTable $Permissions @('ClientName','ResourceName','Kind','Permission','GrantScope','ReviewPriority','ReviewReason','Resolution','CollectionRead') 'Granted permissions'
    $coverageTable=ConvertTo-HtmlTable $Coverage $coverageColumns 'Query coverage'
    $html=@"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"><title>Entra app permissions audit</title><style>
*{box-sizing:border-box}body{font:16px/1.6 system-ui,Segoe UI,sans-serif;margin:0;background:#f2f6f9;color:#18334b}main{max-width:1500px;margin:auto;padding:32px}h1{font-size:clamp(30px,4vw,44px);line-height:1.15}h2{margin-top:36px}a{color:#075d70}nav{display:flex;gap:20px;flex-wrap:wrap}.status,.note{padding:18px;border-left:5px solid #075d70;background:#e2eef3}.note{background:#fff3d7}.cards{display:flex;gap:16px;flex-wrap:wrap;margin:25px 0}.card{background:#fff;padding:18px;flex:1;min-width:170px;border:1px solid #c8d7df}.card strong{display:block;font-size:34px}.table{overflow:auto;border:1px solid #c8d7df;background:#fff}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;padding:12px;border-bottom:1px solid #d9e3e9;min-width:130px;max-width:420px;overflow-wrap:anywhere;vertical-align:top}th{background:#e6eef4}a:focus-visible,.table:focus-visible{outline:3px solid #b37a00;outline-offset:3px}footer{border-top:1px solid #c8d7df;margin-top:35px;padding-top:20px}@media(max-width:600px){main{padding:16px}.card{min-width:135px}}@media print{.table{overflow:visible}table{font-size:10px}}
</style></head><body><main><p>TIAGO CARVALHO · ADMIN TOOLS · $script:Version</p><h1>Entra app permissions audit</h1><p>Read-only inventory · $($AsOf.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss')) UTC</p><div class="status"><strong>$status</strong><br>Tenant: $TenantId<br>$([Net.WebUtility]::HtmlEncode($Scope))<br>$excluded excluded object(s) · $unresolved unresolved or special permission row(s).</div><div class="cards"><div class="card"><strong>$included</strong>Client applications</div><div class="card"><strong>$($summary.DelegatedRows)</strong>Delegated permission rows</div><div class="card"><strong>$($summary.ApplicationAssignments)</strong>Application assignments</div><div class="card"><strong>$high</strong>High-priority review rows</div></div><nav aria-label="Report sections"><a href="#coverage">Coverage</a><a href="#applications">Applications</a><a href="#permissions">Permissions</a><a href="#limits">Limits</a></nav><p class="note">High priority means review the business need and scope. It does not mean malicious, unused or proven data access. Delegated AllPrincipals is consent for all users, not application access. NotClassified is not a safe verdict.</p><p><a href="applications.csv" download>Applications CSV</a> · <a href="permissions.csv" download>Permissions CSV</a> · <a href="coverage.csv" download>Coverage CSV</a> · <a href="summary.json" download>Run summary</a></p><h2 id="coverage">1. Query coverage</h2><p>Failed or unattempted reads stay incomplete. Counts from partial collections are observed lower bounds. A complete inventory is not a security assessment.</p>$coverageTable<h2 id="applications">2. Application review</h2>$appTable<h2 id="permissions">3. Granted permissions</h2><p>One delegated grant can contain several scopes and becomes several rows. Application assignments remain one row each. PrincipalUserId in the CSV identifies whose behalf the app may act on, not who approved consent. AssignmentCreatedUtc is an assignment timestamp, not evidence of use or the consent actor.</p>$permissionTable<h2 id="limits">Scope and interpretation</h2><p>Ordinary Application-type service principals, including Microsoft and third-party applications, with direct Entra delegated grants and application role assignments. Other client types and explicit derived agent objects are listed as excluded. No preauthorized access, requested-manifest permissions, sign-in activity, data access, directory role assignments, Exchange RBAC, Teams resource-specific consent or selected-site grants are inspected. API policies and user permissions can further constrain access; other authorization paths can also grant access.</p><p>The configurable review rules match a resource application ID, permission type and exact value. Rules shipped here cover selected Microsoft Graph permissions only. A similarly named permission on another API is not automatically classified. Disabled clients and disabled definitions are retained for review. Grants can change during collection; recently changed permissions may take time to replicate. Compare a row in Entra before acting.</p><footer>Tiago Carvalho · <a href="https://www.tiagoscarvalho.com">tiagoscarvalho.com</a> · Keep these reports private. No tokens, secrets, mail or file contents are collected. The source is attributed but not digitally signed.</footer></main></body></html>
"@
    [IO.File]::WriteAllText((Join-Path $OutputPath 'report.html'),$html,[Text.UTF8Encoding]::new($false))
    return $summary
}

function Invoke-EntraAppPermissionsAudit {
    [CmdletBinding(DefaultParameterSetName='Selected')]
    param(
        [Parameter(Mandatory)][guid]$ExpectedTenantId,
        [Parameter(Mandatory,ParameterSetName='Selected')][guid[]]$ServicePrincipalObjectId,
        [Parameter(Mandatory,ParameterSetName='All')][switch]$AllApplications,
        [Parameter(Mandatory)][string]$OutputPath
    )
    $ErrorActionPreference='Stop'
    $context=Get-MgContext
    if ($null -eq $context -or $context.TenantId -ne $ExpectedTenantId.ToString() -or $context.AuthType -ne 'Delegated' -or $context.Environment -ne 'Global') { throw 'Connect to the expected tenant in the Global cloud using delegated authentication first. No tenant query was made.' }
    if (-not @($context.Scopes | Where-Object {$_ -in @('Directory.Read.All','Directory.ReadWrite.All')}).Count) { throw 'Directory.Read.All is needed to read delegated consent. No tenant query was made.' }
    if (-not $AllApplications -and (-not $ServicePrincipalObjectId.Count -or [guid]::Empty -in $ServicePrincipalObjectId)) { throw 'Select valid enterprise application Object IDs.' }
    $target=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    if (Test-Path -LiteralPath $target) { throw 'OutputPath must be a new folder; existing reports are never overwritten.' }
    $rules=@(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'review-rules.json') -Raw | ConvertFrom-Json)
    $asOf=[DateTimeOffset]::UtcNow; $state=@{StopRequests=$false}; $resources=@{}
    $clients=[Collections.Generic.List[object]]::new(); $applications=[Collections.Generic.List[object]]::new(); $permissions=[Collections.Generic.List[object]]::new(); $coverage=[Collections.Generic.List[object]]::new()
    $select='id,appId,displayName,servicePrincipalType,accountEnabled'
    $queries=if ($AllApplications) {@{ObjectId='';Uri='https://graph.microsoft.com/v1.0/servicePrincipals?$select='+$select+'&$top=100'}} else {@($ServicePrincipalObjectId | Select-Object -Unique | ForEach-Object {@{ObjectId=$_.ToString();Uri='https://graph.microsoft.com/v1.0/servicePrincipals?$filter=id%20eq%20%27'+$_.ToString()+'%27&$select='+$select}})}
    foreach ($query in $queries) {
        $result=Read-GraphCollection $query.Uri $state
        if (-not $AllApplications -and $result.Complete -and $result.Items.Count -ne 1) {$result.Complete=$false;$result.ErrorCategory='SelectedClientNotReturned'}
        $unexpected=@($result.Items | Where-Object { -not $AllApplications -and (Get-Field $_ 'id') -ne $query.ObjectId })
        if ($unexpected.Count) {$result.Complete=$false;$result.ErrorCategory='UnexpectedClientReturned'}
        Add-Coverage $coverage 'ClientInventory' $query.ObjectId $result
        foreach ($client in $result.Items) {if ($AllApplications -or (Get-Field $client 'id') -eq $query.ObjectId) {$clients.Add($client)}}
    }
    foreach ($client in @($clients.ToArray() | Sort-Object {Get-Field $_ 'id'} -Unique)) {
        $id=[string](Get-Field $client 'id'); $parsed=[guid]::Empty
        if (-not [guid]::TryParse($id,[ref]$parsed)) {throw 'Invalid service principal ID returned. No report was written.'}
        $included=Test-IncludedClient $client
        if (-not $included) {
            $applications.Add([pscustomobject][ordered]@{ObjectId=$id;AppId=(Get-Field $client 'appId');DisplayName=(Get-Field $client 'displayName');ClientType=([string](Get-Field $client '@odata.type')+' / '+[string](Get-Field $client 'servicePrincipalType'));Scope='ExcludedClientType';Enabled=(Get-Field $client 'accountEnabled');DelegatedRead='NotInScope';ApplicationRead='NotInScope';ObservedDelegatedPermissions=0;ObservedApplicationAssignments=0;HighPriorityRows=0;GrantState='NotInScope'})
            continue
        }
        $delegated=Read-GraphCollection ('https://graph.microsoft.com/v1.0/oauth2PermissionGrants?$filter=clientId%20eq%20%27'+$id+'%27') $state
        Add-Coverage $coverage 'DelegatedGrants' $id $delegated
        $assigned=Read-GraphCollection ('https://graph.microsoft.com/v1.0/servicePrincipals/'+$id+'/appRoleAssignments') $state
        Add-Coverage $coverage 'ApplicationAssignments' $id $assigned
        $clientRows=[Collections.Generic.List[object]]::new()
        foreach ($grant in @($delegated.Items | Sort-Object {Get-Field $_ 'id'} -Unique)) {
            $resource=Read-Resource ([string](Get-Field $grant 'resourceId')) $resources $state $coverage
            $scopes=@(([string](Get-Field $grant 'scope') -split '\s+') | Where-Object {$_} | Sort-Object -Unique -CaseSensitive)
            if (-not $scopes.Count) {$scopes=@('')}
            foreach ($scopeValue in $scopes) {$clientRows.Add((ConvertTo-PermissionRow $client $grant 'Delegated' $scopeValue $resource $delegated.Complete $rules))}
        }
        foreach ($grant in @($assigned.Items | Sort-Object {Get-Field $_ 'id'} -Unique)) {
            $resource=Read-Resource ([string](Get-Field $grant 'resourceId')) $resources $state $coverage
            $clientRows.Add((ConvertTo-PermissionRow $client $grant 'Application' '' $resource $assigned.Complete $rules))
        }
        foreach ($row in $clientRows) {$permissions.Add($row)}
        $applications.Add([pscustomobject][ordered]@{ObjectId=$id;AppId=(Get-Field $client 'appId');DisplayName=(Get-Field $client 'displayName');ClientType='Application';Scope='Included';Enabled=(Get-Field $client 'accountEnabled');DelegatedRead=$(if ($delegated.Complete) {'Complete'} else {'Incomplete'});ApplicationRead=$(if ($assigned.Complete) {'Complete'} else {'Incomplete'});ObservedDelegatedPermissions=@($clientRows | Where-Object Kind -eq 'Delegated').Count;ObservedApplicationAssignments=@($clientRows | Where-Object Kind -eq 'Application').Count;HighPriorityRows=@($clientRows | Where-Object ReviewPriority -eq 'High').Count;GrantState=$(if (-not $delegated.Complete -or -not $assigned.Complete) {'Unknown - incomplete collections'} elseif (-not $clientRows.Count) {'No direct grants returned'} else {'Direct grants returned'})})
    }
    New-Item -ItemType Directory -Path $target -ErrorAction Stop | Out-Null
    $scope=if ($AllApplications) {'All ordinary Application-type service principals returned by Graph'} else {'Selected enterprise application Object IDs: '+($ServicePrincipalObjectId -join ', ')}
    Write-PermissionsReport $applications.ToArray() $permissions.ToArray() $coverage.ToArray() $target $ExpectedTenantId.ToString() $asOf $scope
}
Export-ModuleMember -Function Invoke-EntraAppPermissionsAudit

