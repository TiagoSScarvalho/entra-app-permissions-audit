#requires -Version 7.4
# Tiago Carvalho | https://www.tiagoscarvalho.com | MIT
<#
.SYNOPSIS
Reports granted Entra application permissions and delegated consent. Read-only.
.EXAMPLE
./Get-EntraAppPermissionsAudit.ps1 -ExpectedTenantId '<tenant-guid>' -ServicePrincipalObjectId '<enterprise-app-object-guid>' -OutputPath ./Pilot
.EXAMPLE
./Get-EntraAppPermissionsAudit.ps1 -ExpectedTenantId '<tenant-guid>' -AllApplications -OutputPath ./Audit
#>
[CmdletBinding(DefaultParameterSetName='Selected')]
param(
    [Parameter(Mandatory)][guid]$ExpectedTenantId,
    [Parameter(Mandatory,ParameterSetName='Selected')][guid[]]$ServicePrincipalObjectId,
    [Parameter(Mandatory,ParameterSetName='All')][switch]$AllApplications,
    [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.Graph.Authentication -MinimumVersion 2.37.0 -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'EntraAppPermissionsAudit.psm1') -Force
Invoke-EntraAppPermissionsAudit @PSBoundParameters
