#requires -Version 7.4
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot '../EntraAppPermissionsAudit.psm1') -Force -PassThru
& $module {
    $script:Checks=0
    function Assert($Condition,[string]$Label) { if (-not $Condition) { throw "FAIL: $Label" }; $script:Checks++; Write-Host "PASS: $Label" }
    $clientId='11111111-1111-4111-8111-111111111111'; $resourceId='22222222-2222-4222-8222-222222222222'; $userId='33333333-3333-4333-8333-333333333333'; $roleId='44444444-4444-4444-8444-444444444444'; $scopeId='55555555-5555-4555-8555-555555555555'; $tenant='66666666-6666-4666-8666-666666666666'
    $client=@{id=$clientId;appId='77777777-7777-4777-8777-777777777777';displayName='<script>alert(1)</script>';servicePrincipalType='Application';accountEnabled=$false}
    $resource=@{id=$resourceId;appId='00000003-0000-0000-c000-000000000000';displayName='Microsoft Graph';appRoles=@(@{id=$roleId;value='Mail.ReadWrite';isEnabled=$true;allowedMemberTypes=@('Application')});oauth2PermissionScopes=@(@{id=$scopeId;value='Mail.ReadWrite';isEnabled=$true})}
    $read=[pscustomobject]@{Items=@($resource);Complete=$true;Pages=1;HttpStatus=0;ErrorCategory=''}
    $grant=@{id='grant-one';clientId=$clientId;resourceId=$resourceId;consentType='AllPrincipals';principalId=$null;scope='Mail.ReadWrite'}
    $role=@{id='assignment-one';principalId=$clientId;principalType='ServicePrincipal';resourceId=$resourceId;appRoleId=$roleId;createdDateTime='2026-01-01T00:00:00Z'}
    $rules=@(Get-Content -LiteralPath (Join-Path $PSScriptRoot '../review-rules.json') -Raw | ConvertFrom-Json)
    Assert (Test-IncludedClient $client) 'Ordinary application client included'
    $derived=$client.Clone();$derived.id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';$derived['@odata.type']='#microsoft.graph.agentIdentityBlueprintPrincipal'
    Assert (-not (Test-IncludedClient $derived)) 'Derived agent principal explicitly excluded'
    $managed=$client.Clone();$managed.id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';$managed.servicePrincipalType='ManagedIdentity'
    Assert (-not (Test-IncludedClient $managed)) 'Managed identity client explicitly excluded'
    $row=ConvertTo-PermissionRow $client $grant 'Delegated' 'Mail.ReadWrite' $read $true $rules
    Assert ($row.Kind -eq 'Delegated' -and $row.GrantScope -eq 'All users (delegated)') 'AllPrincipals remains delegated'
    Assert ($row.ReviewPriority -eq 'High' -and $row.Resolution -eq 'Resolved') 'Known Graph permission classified by exact resource/type/value'
    Assert ($row.ClientEnabled -eq $false) 'Disabled clients retained'
    $grant.principalId=$userId;$grant.consentType='Principal'
    $row=ConvertTo-PermissionRow $client $grant 'Delegated' 'Mail.ReadWrite' $read $false $rules
    Assert ($row.PrincipalUserId -eq $userId -and $row.CollectionRead -eq 'Incomplete') 'Specific user ID and incomplete collection retained'
    Assert ($row.ConsentType -eq 'Principal') 'No invented approving actor'
    $grant.principalId=$null
    Assert ((ConvertTo-PermissionRow $client $grant 'Delegated' 'Mail.ReadWrite' $read $true $rules).Resolution -eq 'InvalidGrantMetadata') 'Missing Principal user flagged'
    $grant.consentType='AllPrincipals'
    $row=ConvertTo-PermissionRow $client $role 'Application' '' $read $true $rules
    Assert ($row.Permission -eq 'Mail.ReadWrite' -and $row.Kind -eq 'Application') 'App role ID resolved against resource definition'
    Assert ($row.ConsentType -eq 'NotAvailableFromAssignment') 'Assignment does not fabricate consent history'
    $resource.appId='88888888-8888-4888-8888-888888888888'
    Assert ((ConvertTo-PermissionRow $client $role 'Application' '' $read $true $rules).ReviewPriority -eq 'NotClassified') 'Same permission name on another API not classified as Graph'
    $resource.appId='00000003-0000-0000-c000-000000000000'
    $resource.appRoles[0].isEnabled=$false
    Assert ((ConvertTo-PermissionRow $client $role 'Application' '' $read $true $rules).Resolution -eq 'DefinitionDisabled') 'Disabled definitions flagged'
    $resource.appRoles[0].isEnabled=$true
    $role.appRoleId='99999999-9999-4999-8999-999999999999'
    Assert ((ConvertTo-PermissionRow $client $role 'Application' '' $read $true $rules).Resolution -eq 'Unresolved') 'Deleted or unknown role preserved'
    $role.appRoleId=[guid]::Empty.ToString()
    Assert ((ConvertTo-PermissionRow $client $role 'Application' '' $read $true $rules).Resolution -eq 'DefaultAccess') 'Zero role ID is default access, not a named API permission'
    $role.appRoleId=$roleId;$role.principalId=$userId
    Assert ((ConvertTo-PermissionRow $client $role 'Application' '' $read $true $rules).Resolution -eq 'InvalidGrantMetadata') 'Unexpected assigned principal detected'
    $role.principalId=$clientId
    Assert ((ConvertTo-PermissionRow $client $grant 'Delegated' 'mail.readwrite' $read $true $rules).Resolution -eq 'Unresolved') 'Scope value is matched case sensitively'
    $missing=[pscustomobject]@{Items=@();Complete=$false;Pages=0;HttpStatus=403;ErrorCategory='AccessDenied'}
    Assert ((ConvertTo-PermissionRow $client $grant 'Delegated' 'Mail.ReadWrite' $missing $true $rules).ReviewPriority -eq 'Review') 'Unreadable resource cannot become safe'
    Assert ((ConvertTo-CsvCell '=1+1') -eq '"''=1+1"') 'CSV formula injection escaped'
    Assert ((ConvertTo-CsvCell " `t@SUM(1)").StartsWith('"''')) 'Whitespace formula prefix escaped'
    Assert ((ConvertTo-HtmlTable @([pscustomobject]@{Name='<img src=x onerror=alert(1)>'}) @('Name') 'Table').Contains('&lt;img')) 'HTML content encoded'
    $script:Calls=[Collections.Generic.List[string]]::new();$script:Responses=[Collections.Generic.Queue[object]]::new()
    function Invoke-MgGraphRequest { param($Method,$Uri,$OutputType,$ErrorAction)
        if ($Method -ne 'GET') {throw 'Write method forbidden in tests'}
        $script:Calls.Add($Uri)
        $next=$script:Responses.Dequeue()
        if ($next -is [Exception]) {throw $next}
        return $next
    }
    $base='https://graph.microsoft.com/v1.0/servicePrincipals'
    $script:Responses.Enqueue(@{value=@($client);'@odata.nextLink'=$base+'?$skiptoken=second'})
    $script:Responses.Enqueue(@{value=@($resource)})
    $result=Read-GraphCollection $base @{StopRequests=$false}
    Assert ($result.Complete -and $result.Pages -eq 2 -and $result.Items.Count -eq 2) 'Collection pagination followed'
    $script:Responses.Enqueue(@{value=@($client);'@odata.nextLink'='https://example.com/leak'})
    $before=$script:Calls.Count;$result=Read-GraphCollection $base @{StopRequests=$false}
    Assert (-not $result.Complete -and $result.ErrorCategory -eq 'InvalidPagination' -and $script:Calls.Count -eq ($before+1)) 'Foreign nextLink rejected before request'
    $script:Responses.Enqueue(@{value=@($client);'@odata.nextLink'=$base})
    Assert ((Read-GraphCollection $base @{StopRequests=$false}).ErrorCategory -eq 'InvalidPagination') 'Pagination loops rejected'
    $script:Responses.Enqueue(@{unexpected='data'})
    Assert (-not (Read-GraphCollection $base @{StopRequests=$false}).Complete) 'Malformed response not treated as empty success'
    $script:Responses.Enqueue(@{value='unexpected'})
    Assert (-not (Read-GraphCollection $base @{StopRequests=$false}).Complete) 'Scalar collection rejected'
    $script:Responses.Enqueue(@{value=@(@{name='no ID'})})
    Assert (-not (Read-GraphCollection $base @{StopRequests=$false}).Complete) 'Malformed item makes collection incomplete'
    $script:Responses.Enqueue(@{value=@($client);'@odata.nextLink'='http://['})
    Assert ((Read-GraphCollection $base @{StopRequests=$false}).ErrorCategory -eq 'InvalidPagination') 'Malformed pagination URL preserved as partial result'
    foreach($code in @(401,429,503)) {
        $error=[Net.Http.HttpRequestException]::new('do not export this sensitive message',$null,[Net.HttpStatusCode]$code)
        $script:Responses.Enqueue([AggregateException]::new('wrapped',$error));$state=@{StopRequests=$false}
        $result=Read-GraphCollection $base $state
        Assert ($result.HttpStatus -eq $code -and $state.StopRequests) "Nested HTTP $code halts remaining requests"
        $before=$script:Calls.Count;$result=Read-GraphCollection $base $state
        Assert ($result.ErrorCategory -eq 'NotAttemptedAfterServiceFailure' -and $script:Calls.Count -eq $before) "No request after HTTP $code"
    }
    $script:Responses.Enqueue([Net.Http.HttpRequestException]::new('private',$null,[Net.HttpStatusCode]403));$state=@{StopRequests=$false}
    Assert ((Read-GraphCollection $base $state).ErrorCategory -eq 'AccessDenied' -and -not $state.StopRequests) '403 records a read gap without halting independent reads'
    $script:Context=[pscustomobject]@{TenantId=$tenant;AuthType='Delegated';Environment='Global';Scopes=@('Directory.Read.All')}
    function Get-MgContext {$script:Context}
    $testRoot=Join-Path ([IO.Path]::GetTempPath()) ('entra-permission-tests-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $script:Context.TenantId=$userId;$before=$script:Calls.Count;$caught=$false
    try {Invoke-EntraAppPermissionsAudit -ExpectedTenantId $tenant -AllApplications -OutputPath (Join-Path $testRoot 'wrong')} catch {$caught=$true}
    Assert ($caught -and $script:Calls.Count -eq $before) 'Wrong tenant stops before query'
    $script:Context.TenantId=$tenant;$script:Context.Scopes=@('Application.Read.All');$caught=$false
    try {Invoke-EntraAppPermissionsAudit -ExpectedTenantId $tenant -AllApplications -OutputPath (Join-Path $testRoot 'scope')} catch {$caught=$true}
    Assert ($caught -and $script:Calls.Count -eq $before) 'Insufficient scope stops before query'
    $script:Context.Scopes=@('Directory.Read.All');$caught=$false
    try {Invoke-EntraAppPermissionsAudit -ExpectedTenantId $tenant -AllApplications -OutputPath $testRoot} catch {$caught=$true}
    Assert ($caught -and $script:Calls.Count -eq $before) 'Existing output directory preserved'
    $script:Responses.Enqueue(@{value=@($client,$managed,$derived)})
    $script:Responses.Enqueue(@{value=@($grant)})
    $script:Responses.Enqueue(@{value=@($role)})
    $script:Responses.Enqueue(@{value=@($resource)})
    $output=Join-Path $testRoot 'complete'
    $result=Invoke-EntraAppPermissionsAudit -ExpectedTenantId $tenant -AllApplications -OutputPath $output
    Assert ($result.IncompleteSections -eq 0 -and $result.PermissionRows -eq 2) 'End-to-end audit exports two granted permission rows'
    Assert ($result.Applications -eq 1 -and $result.ExcludedObjects -eq 2) 'Scope exclusions explicit in summary'
    Assert ((Import-Csv -LiteralPath (Join-Path $output 'permissions.csv')).Count -eq 2) 'CSV reconciles with summary'
    Assert ((Get-Content -LiteralPath (Join-Path $output 'report.html') -Raw).Contains('&lt;script&gt;')) 'Report encodes actual collected names'
    $script:Responses.Enqueue(@{value=@($client)})
    $script:Responses.Enqueue([Net.Http.HttpRequestException]::new('private',$null,[Net.HttpStatusCode]403))
    $script:Responses.Enqueue(@{value=@()})
    $partial=Join-Path $testRoot 'partial'
    $result=Invoke-EntraAppPermissionsAudit -ExpectedTenantId $tenant -ServicePrincipalObjectId $clientId -OutputPath $partial
    Assert ($result.IncompleteSections -eq 1 -and $result.ReportStatus.StartsWith('PARTIAL')) 'Denied delegated query makes partial report'
    Assert ((Import-Csv -LiteralPath (Join-Path $partial 'applications.csv')).GrantState -like 'Unknown*') 'Failed permission read is not no grants'
    $script:Responses.Enqueue(@{value=@($client)})
    $script:Responses.Enqueue(@{value=@()});$script:Responses.Enqueue(@{value=@()})
    $empty=Join-Path $testRoot 'empty'
    $result=Invoke-EntraAppPermissionsAudit -ExpectedTenantId $tenant -ServicePrincipalObjectId $clientId -OutputPath $empty
    Assert ($result.PermissionRows -eq 0 -and $result.IncompleteSections -eq 0) 'Complete empty collection distinguished from failure'
    Assert ((Import-Csv -LiteralPath (Join-Path $empty 'applications.csv')).GrantState -eq 'No direct grants returned') 'Empty scope label bounded to direct grants'
    Assert ((Get-Content -LiteralPath (Join-Path $empty 'permissions.csv')).StartsWith('"ClientObjectId"')) 'Empty CSV keeps headers'
    $script:Responses.Enqueue(@{value=@()})
    $result=Invoke-EntraAppPermissionsAudit -ExpectedTenantId $tenant -ServicePrincipalObjectId $clientId -OutputPath (Join-Path $testRoot 'missing')
    Assert ($result.IncompleteSections -eq 1) 'Missing selected client is incomplete'
    Assert ((Import-Csv -LiteralPath (Join-Path $testRoot 'missing/coverage.csv')).ObjectId -eq $clientId) 'Selected inventory failure identifies its requested object'
    $script:Responses.Enqueue(@{value=@($resource)})
    $result=Invoke-EntraAppPermissionsAudit -ExpectedTenantId $tenant -ServicePrincipalObjectId $clientId -OutputPath (Join-Path $testRoot 'unexpected')
    Assert ($result.IncompleteSections -eq 1 -and $result.Applications -eq 0) 'Unexpected selected object is not queried as a client'
    Assert ($script:Responses.Count -eq 0) 'All expected request responses consumed'
    [pscustomobject]@{Passed=$script:Checks;Failed=0;Output=$testRoot} | ConvertTo-Json
}
