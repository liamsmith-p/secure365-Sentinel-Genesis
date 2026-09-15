param(
    [Parameter(Mandatory = $true)][string]$ResourceGroupName,
    [Parameter(Mandatory = $false)][string]$SubscriptionId,
    [Parameter(Mandatory = $false)][string]$DeploymentName,
    [Parameter(Mandatory = $false)][string]$OutputPath
)

# Run this yourself, in your own context, after a deployment has finished (and ideally
# a few minutes after, so policy remediation and connector status have settled) - it is
# not part of the ARM deployment. It re-derives what was requested from Azure's own
# deployment history, so you never have to re-type what you ticked in the wizard, then
# checks live Azure state and reports where the two agree or disagree.

$ErrorActionPreference = 'Stop'

$context = Get-AzContext
if (!$context) {
    Connect-AzAccount | Out-Null
    $context = Get-AzContext
}
if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    $context = Get-AzContext
}
$SubscriptionId = $context.Subscription.Id
Write-Host "Connected to subscription $SubscriptionId."

# ---------------------------------------------------------------------------
# Result collection
# ---------------------------------------------------------------------------
$results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param(
        [string]$Area,
        [string]$Item,
        [ValidateSet('OK', 'PARTIAL', 'FAIL', 'SKIP', 'UNKNOWN')][string]$Status,
        [string]$Detail = ''
    )
    $results.Add([pscustomobject]@{ Area = $Area; Item = $Item; Status = $Status; Detail = $Detail })
    $colour = switch ($Status) {
        'OK'      { 'Green' }
        'PARTIAL' { 'Yellow' }
        'UNKNOWN' { 'Yellow' }
        'FAIL'    { 'Red' }
        default   { 'Gray' }
    }
    Write-Host ("  [{0,-7}] {1} - {2}" -f $Status, $Item, $Detail) -ForegroundColor $colour
}

# Safe REST GET: never throws, always reports what happened.
function Invoke-SafeGet {
    param([string]$Path, [string]$ApiVersion)
    try {
        $resp = Invoke-AzRestMethod -Path "$Path`?api-version=$ApiVersion" -Method GET
        if ($resp.StatusCode -eq 200) {
            return [pscustomobject]@{ Found = $true; Data = ($resp.Content | ConvertFrom-Json); Status = 200 }
        } elseif ($resp.StatusCode -eq 404) {
            return [pscustomobject]@{ Found = $false; Data = $null; Status = 404 }
        } else {
            return [pscustomobject]@{ Found = $false; Data = $null; Status = $resp.StatusCode; Error = $resp.Content }
        }
    } catch {
        return [pscustomobject]@{ Found = $false; Data = $null; Status = 'exception'; Error = $_.Exception.Message }
    }
}

function ConvertTo-Bool {
    param($Value)
    if ($Value -is [bool]) { return $Value }
    return [bool]::Parse([string]$Value)
}

# ---------------------------------------------------------------------------
# 1. Find the deployment and recover what was requested - straight from Azure's
#    own deployment history, so nothing has to be re-typed.
# ---------------------------------------------------------------------------
Write-Host "`nLocating the Sentinel deployment in resource group '$ResourceGroupName'..."

if ($DeploymentName) {
    $deployment = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $DeploymentName -ErrorAction Stop
} else {
    $deployment = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -ErrorAction Stop |
        Where-Object { $_.Parameters -and $_.Parameters.ContainsKey('workspaceName') -and $_.Parameters.ContainsKey('enableDataConnectors') } |
        Sort-Object Timestamp -Descending |
        Select-Object -First 1
    if (-not $deployment) {
        throw "Could not find a Sentinel deployment in resource group '$ResourceGroupName'. Pass -DeploymentName explicitly if it isn't the most recent matching one."
    }
}
Write-Host "Using deployment '$($deployment.DeploymentName)' from $($deployment.Timestamp)."

$p = $deployment.Parameters
function Get-ParamValue {
    param([string]$Name, $Default)
    if ($p -and $p.ContainsKey($Name)) { return $p[$Name].Value }
    return $Default
}

$workspaceName = Get-ParamValue 'workspaceName' $null
if (-not $workspaceName) {
    throw "Deployment '$($deployment.DeploymentName)' has no workspaceName parameter - is this the right deployment? Pass -DeploymentName explicitly."
}

$dataConnectors           = @(Get-ParamValue 'enableDataConnectors' @())
$solutions1P              = @(Get-ParamValue 'enableSolutions1P' @())
$solutionsEssentials      = @(Get-ParamValue 'enableSolutionsEssentials' @())
$enableUeba               = ConvertTo-Bool (Get-ParamValue 'enableUeba' $false)
$identityProviders        = @(Get-ParamValue 'identityProviders' @())
$enableDiagnostics        = ConvertTo-Bool (Get-ParamValue 'enableDiagnostics' $false)
$diagnosticPolicies       = @(Get-ParamValue 'enableDiagnosticPolicies' @())
$enableOngoingDiagnostics = ConvertTo-Bool (Get-ParamValue 'enableOngoingDiagnostics' $false)
$policySubscriptions      = @(Get-ParamValue 'policySubscriptions' @())
if ($policySubscriptions.Count -eq 0) { $policySubscriptions = @($SubscriptionId) }
$enableScheduledAlerts    = ConvertTo-Bool (Get-ParamValue 'enableScheduledAlerts' $false)
$severityLevels           = @(Get-ParamValue 'severityLevels' @())
$enableLighthouse         = ConvertTo-Bool (Get-ParamValue 'enableLighthouse' $false)
$lighthouseOfferName      = Get-ParamValue 'lighthouseOfferName' ''
$mspTenantId              = Get-ParamValue 'mspTenantId' ''
$lighthouseAuthorizations = @(Get-ParamValue 'lighthouseAuthorizations' @())

$workspaceResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName"

# ---------------------------------------------------------------------------
# 2. Data connectors
# ---------------------------------------------------------------------------
Write-Host "`nData Connectors"

if ($dataConnectors -contains 'MicrosoftEntraID') {
    $expected = @('SignInLogs', 'AuditLogs', 'NonInteractiveUserSignInLogs', 'ServicePrincipalSignInLogs',
        'ManagedIdentitySignInLogs', 'ProvisioningLogs', 'ADFSSignInLogs', 'RiskyUsers', 'UserRiskEvents',
        'RiskyServicePrincipals', 'ServicePrincipalRiskEvents', 'MicrosoftGraphActivityLogs',
        'NetworkAccessTrafficLogs', 'EnrichedOffice365AuditLogs', 'RemoteNetworkHealthLogs')
    $r = Invoke-SafeGet -Path "/providers/microsoft.aadiam/diagnosticSettings/$workspaceName-entraIdDiagnosticSettings" -ApiVersion '2017-04-01'
    if ($r.Found) {
        $actual = @($r.Data.properties.logs | Where-Object { $_.enabled } | ForEach-Object { $_.category })
        $missing = $expected | Where-Object { $_ -notin $actual }
        if ($missing.Count -eq 0) {
            Add-Result 'Data Connectors' 'Microsoft Entra ID' 'OK' "$($actual.Count)/$($expected.Count) expected log categories enabled"
        } else {
            Add-Result 'Data Connectors' 'Microsoft Entra ID' 'PARTIAL' "Missing categories: $($missing -join ', ')"
        }
    } else {
        Add-Result 'Data Connectors' 'Microsoft Entra ID' 'FAIL' "Diagnostic setting not found (HTTP $($r.Status))"
    }
} else {
    Add-Result 'Data Connectors' 'Microsoft Entra ID' 'SKIP' 'Not requested'
}

if ($dataConnectors -contains 'AzureActivity') {
    $expected = @('Administrative', 'Security', 'ServiceHealth', 'Alert', 'Recommendation', 'Policy', 'Autoscale', 'ResourceHealth')
    $r = Invoke-SafeGet -Path "/subscriptions/$SubscriptionId/providers/microsoft.insights/diagnosticSettings/sentinel-azure-activity" -ApiVersion '2021-05-01-preview'
    if ($r.Found) {
        $actual = @($r.Data.properties.logs | Where-Object { $_.enabled } | ForEach-Object { $_.category })
        $missing = $expected | Where-Object { $_ -notin $actual }
        if ($missing.Count -eq 0) {
            Add-Result 'Data Connectors' 'Azure Activity' 'OK' "$($actual.Count)/$($expected.Count) expected log categories enabled"
        } else {
            Add-Result 'Data Connectors' 'Azure Activity' 'PARTIAL' "Missing categories: $($missing -join ', ')"
        }
    } else {
        Add-Result 'Data Connectors' 'Azure Activity' 'FAIL' "Diagnostic setting not found (HTTP $($r.Status))"
    }
} else {
    Add-Result 'Data Connectors' 'Azure Activity' 'SKIP' 'Not requested'
}

# Office365 / Power BI / Project / Dynamics 365 all live in the same list.
$sentinelConnectors = $null
$connectorMap = @(
    @{ Value = 'Office365'; Kind = 'Office365'; Label = 'Microsoft 365' }
    @{ Value = 'MicrosoftPowerBI'; Kind = 'OfficePowerBI'; Label = 'Microsoft Power BI' }
    @{ Value = 'MicrosoftProject'; Kind = 'Office365Project'; Label = 'Microsoft Project' }
    @{ Value = 'Dynamics365'; Kind = 'Dynamics365'; Label = 'Dynamics 365' }
)
if ($dataConnectors | Where-Object { $connectorMap.Value -contains $_ }) {
    $r = Invoke-SafeGet -Path "$workspaceResourceId/providers/Microsoft.SecurityInsights/dataConnectors" -ApiVersion '2023-02-01-preview'
    if ($r.Found) { $sentinelConnectors = @($r.Data.value) }
}
foreach ($c in $connectorMap) {
    if ($dataConnectors -notcontains $c.Value) {
        Add-Result 'Data Connectors' $c.Label 'SKIP' 'Not requested'
        continue
    }
    if ($null -eq $sentinelConnectors) {
        Add-Result 'Data Connectors' $c.Label 'UNKNOWN' 'Could not list data connectors to verify'
        continue
    }
    $match = $sentinelConnectors | Where-Object { $_.kind -eq $c.Kind } | Select-Object -First 1
    if ($match) {
        Add-Result 'Data Connectors' $c.Label 'OK' 'Connector present'
    } else {
        Add-Result 'Data Connectors' $c.Label 'FAIL' 'Connector not found'
    }
}

# ---------------------------------------------------------------------------
# 3. Settings: UEBA and Sentinel auditing/health
# ---------------------------------------------------------------------------
Write-Host "`nSettings"

if ($enableUeba) {
    $r = Invoke-SafeGet -Path "$workspaceResourceId/providers/Microsoft.SecurityInsights/settings/EntityAnalytics" -ApiVersion '2022-12-01-preview'
    if ($r.Found) {
        $actual = @($r.Data.properties.entityProviders)
        $missing = $identityProviders | Where-Object { $_ -notin $actual }
        if ($missing.Count -eq 0) {
            Add-Result 'Settings' 'UEBA' 'OK' "Identity providers: $($actual -join ', ')"
        } else {
            Add-Result 'Settings' 'UEBA' 'PARTIAL' "Missing identity providers: $($missing -join ', ')"
        }
    } else {
        Add-Result 'Settings' 'UEBA' 'FAIL' "EntityAnalytics setting not found (HTTP $($r.Status))"
    }
} else {
    Add-Result 'Settings' 'UEBA' 'SKIP' 'Not requested'
}

if ($enableDiagnostics) {
    $r = Invoke-SafeGet -Path "$workspaceResourceId/providers/Microsoft.SecurityInsights/SentinelHealth/providers/microsoft.insights/diagnosticSettings/HealthSettings" -ApiVersion '2021-05-01-preview'
    if ($r.Found) {
        Add-Result 'Settings' 'Sentinel auditing and health monitoring' 'OK' 'allLogs diagnostic setting present'
    } else {
        Add-Result 'Settings' 'Sentinel auditing and health monitoring' 'FAIL' "Diagnostic setting not found (HTTP $($r.Status))"
    }
} else {
    Add-Result 'Settings' 'Sentinel auditing and health monitoring' 'SKIP' 'Not requested'
}

# ---------------------------------------------------------------------------
# 4. Content Hub solutions
# ---------------------------------------------------------------------------
Write-Host "`nContent Hub Solutions"

$requestedSolutions = @($solutions1P) + @($solutionsEssentials) | Where-Object { $_ }
if ($requestedSolutions.Count -gt 0) {
    $candidateVersions = @('2024-09-01', '2024-04-01-preview', '2024-03-01', '2024-01-01-preview')
    $catalog = $null
    foreach ($v in $candidateVersions) {
        $r = Invoke-SafeGet -Path "$workspaceResourceId/providers/Microsoft.SecurityInsights/contentProductPackages" -ApiVersion $v
        if ($r.Found) { $catalog = @($r.Data.value); break }
    }
    foreach ($name in $requestedSolutions) {
        if ($null -eq $catalog) {
            Add-Result 'Content Hub Solutions' $name 'UNKNOWN' 'Could not list installed solutions to verify'
            continue
        }
        $match = $catalog | Where-Object { $_.properties.displayName -eq $name } | Select-Object -First 1
        if (-not $match) {
            Add-Result 'Content Hub Solutions' $name 'UNKNOWN' 'Not found in Content Hub catalog under this name'
        } elseif ($match.properties.installedVersion) {
            Add-Result 'Content Hub Solutions' $name 'OK' "Installed (version $($match.properties.installedVersion))"
        } else {
            Add-Result 'Content Hub Solutions' $name 'FAIL' 'Present in catalog but not installed'
        }
    }
} else {
    Add-Result 'Content Hub Solutions' '(none)' 'SKIP' 'No solutions requested'
}

# ---------------------------------------------------------------------------
# 5. Analytics rules
# ---------------------------------------------------------------------------
Write-Host "`nAnalytics Rules"

if ($enableScheduledAlerts) {
    $r = Invoke-SafeGet -Path "$workspaceResourceId/providers/Microsoft.SecurityInsights/alertRules" -ApiVersion '2024-01-01-preview'
    if ($r.Found) {
        $rules = @($r.Data.value)
        $active = @($rules | Where-Object { $_.properties.enabled })
        foreach ($sev in $severityLevels) {
            $count = @($active | Where-Object { $_.properties.severity -eq $sev }).Count
            $status = if ($count -gt 0) { 'OK' } else { 'PARTIAL' }
            Add-Result 'Analytics Rules' "Severity: $sev" $status "$count active rule(s)"
        }
        Add-Result 'Analytics Rules' 'Total active rules' 'OK' "$($active.Count) of $($rules.Count) rule(s) enabled"
    } else {
        Add-Result 'Analytics Rules' 'Scheduled alert rules' 'FAIL' "Could not list alert rules (HTTP $($r.Status))"
    }
} else {
    Add-Result 'Analytics Rules' 'Scheduled alert rules' 'SKIP' 'Not requested'
}

# ---------------------------------------------------------------------------
# 6. Policy tab: resource-level diagnostic settings (immediate script and/or
#    ongoing deployIfNotExists policy both converge on the same end state - a
#    'sentinel-diagnostics' setting on the resource - so one check covers both).
# ---------------------------------------------------------------------------
Write-Host "`nPolicy - Resource-Level Diagnostic Settings"

$policyTypeMap = @{
    'AzureKeyVault'             = @{ ResourceType = 'Microsoft.KeyVault/vaults'; Label = 'Azure Key Vault'; AssignName = 'Sentinel - Key Vault diagnostic settings' }
    'AzureNetworkSecurityGroup' = @{ ResourceType = 'Microsoft.Network/networkSecurityGroups'; Label = 'Azure Network Security Group'; AssignName = 'Sentinel - NSG diagnostic settings' }
    'AzureStorageAccount'       = @{ ResourceType = 'Microsoft.Storage/storageAccounts'; Label = 'Azure Storage Account'; AssignName = 'Sentinel - Storage Account diagnostic settings' }
    'AzureSqlDatabase'          = @{ ResourceType = 'Microsoft.Sql/servers/databases'; Label = 'Azure SQL Database'; AssignName = 'Sentinel - SQL Database diagnostic settings' }
    'AzureFirewall'             = @{ ResourceType = 'Microsoft.Network/azureFirewalls'; Label = 'Azure Firewall'; AssignName = 'Sentinel - Azure Firewall diagnostic settings' }
    'AzureApplicationGateway'   = @{ ResourceType = 'Microsoft.Network/applicationGateways'; Label = 'Azure Application Gateway'; AssignName = 'Sentinel - Application Gateway diagnostic settings' }
}
$storageSubServices = @('blobServices/default', 'queueServices/default', 'tableServices/default', 'fileServices/default')

function Test-SentinelDiagnosticSetting {
    param([string]$ResourceId)
    $r = Invoke-SafeGet -Path "$ResourceId/providers/microsoft.insights/diagnosticSettings/sentinel-diagnostics" -ApiVersion '2021-05-01-preview'
    return $r.Found -and $r.Data.properties.workspaceId -eq $workspaceResourceId
}

foreach ($key in $policyTypeMap.Keys) {
    $meta = $policyTypeMap[$key]
    if ($diagnosticPolicies -notcontains $key) {
        Add-Result 'Policy' $meta.Label 'SKIP' 'Not requested'
        continue
    }

    try {
        $resources = @((Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId/resources?`$filter=resourceType eq '$($meta.ResourceType)'&api-version=2021-04-01" -Method GET).Content | ConvertFrom-Json).value
    } catch {
        $resources = $null
    }

    if ($null -eq $resources) {
        Add-Result 'Policy' $meta.Label 'UNKNOWN' 'Could not enumerate resources of this type'
        continue
    }
    if ($resources.Count -eq 0) {
        Add-Result 'Policy' $meta.Label 'SKIP' 'Requested, but no resources of this type exist'
        continue
    }

    $okCount = 0
    foreach ($res in $resources) {
        if ($key -eq 'AzureStorageAccount') {
            $subOk = @($storageSubServices | ForEach-Object { Test-SentinelDiagnosticSetting -ResourceId "$($res.id)/$_" })
            $configured = ($subOk -notcontains $false)
        } else {
            $configured = Test-SentinelDiagnosticSetting -ResourceId $res.id
        }
        if ($configured) {
            $okCount++
            Add-Result 'Policy' "$($meta.Label): $($res.name)" 'OK' 'sentinel-diagnostics present'
        } else {
            Add-Result 'Policy' "$($meta.Label): $($res.name)" 'FAIL' 'sentinel-diagnostics missing or incomplete (check for a resource lock)'
        }
    }
    Add-Result 'Policy' "$($meta.Label) (summary)" $(if ($okCount -eq $resources.Count) { 'OK' } else { 'PARTIAL' }) "$okCount of $($resources.Count) resource(s) configured"

    if ($enableOngoingDiagnostics) {
        foreach ($sub in $policySubscriptions) {
            try {
                $assignments = @((Invoke-AzRestMethod -Path "/subscriptions/$sub/providers/Microsoft.Authorization/policyAssignments?api-version=2022-06-01" -Method GET).Content | ConvertFrom-Json).value
                $match = $assignments | Where-Object { $_.properties.displayName -like "$($meta.AssignName)*" } | Select-Object -First 1
                if ($match) {
                    Add-Result 'Policy' "$($meta.Label) assignment ($sub)" 'OK' 'Policy assignment exists for ongoing enforcement'
                } else {
                    Add-Result 'Policy' "$($meta.Label) assignment ($sub)" 'FAIL' 'Policy assignment not found'
                }
            } catch {
                Add-Result 'Policy' "$($meta.Label) assignment ($sub)" 'UNKNOWN' "Could not list policy assignments: $($_.Exception.Message)"
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 7. Azure Lighthouse
# ---------------------------------------------------------------------------
Write-Host "`nService Provider (Azure Lighthouse)"

if ($enableLighthouse) {
    try {
        $definitions = @((Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId/providers/Microsoft.ManagedServices/registrationDefinitions?api-version=2022-10-01" -Method GET).Content | ConvertFrom-Json).value
        $def = $definitions | Where-Object { $_.properties.registrationDefinitionName -eq $lighthouseOfferName } | Select-Object -First 1
        if (-not $def) {
            Add-Result 'Service Provider' 'Lighthouse registration definition' 'FAIL' "No definition named '$lighthouseOfferName' found"
        } else {
            $tenantOk = $def.properties.managedByTenantId -eq $mspTenantId
            $authCount = @($def.properties.authorizations).Count
            if ($tenantOk -and $authCount -eq $lighthouseAuthorizations.Count) {
                Add-Result 'Service Provider' 'Lighthouse registration definition' 'OK' "Tenant matches, $authCount/$($lighthouseAuthorizations.Count) authorizations present"
            } else {
                Add-Result 'Service Provider' 'Lighthouse registration definition' 'PARTIAL' "Tenant match: $tenantOk; authorizations: $authCount/$($lighthouseAuthorizations.Count)"
            }

            $assignments = @((Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId/providers/Microsoft.ManagedServices/registrationAssignments?api-version=2022-10-01" -Method GET).Content | ConvertFrom-Json).value
            $assigned = $assignments | Where-Object { $_.properties.registrationDefinitionId -like "*$($def.name)" }
            if ($assigned) {
                Add-Result 'Service Provider' 'Lighthouse registration assignment' 'OK' 'Assignment active'
            } else {
                Add-Result 'Service Provider' 'Lighthouse registration assignment' 'FAIL' 'No matching assignment found'
            }
        }
    } catch {
        Add-Result 'Service Provider' 'Lighthouse' 'UNKNOWN' "Could not verify: $($_.Exception.Message)"
    }
} else {
    Add-Result 'Service Provider' 'Lighthouse' 'SKIP' 'Not requested'
}

# ---------------------------------------------------------------------------
# 8. Write the report
# ---------------------------------------------------------------------------
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $OutputPath) { $OutputPath = "./sentinel-verification-$workspaceName-$timestamp" }
$mdPath = "$OutputPath.md"
$jsonPath = "$OutputPath.json"

$summary = $results | Group-Object Status | Sort-Object Name | ForEach-Object { "$($_.Name): $($_.Count)" }

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# Sentinel Deployment Verification Report")
[void]$md.AppendLine("")
[void]$md.AppendLine("Workspace: **$workspaceName**  ")
[void]$md.AppendLine("Resource group: **$ResourceGroupName**  ")
[void]$md.AppendLine("Source deployment: **$($deployment.DeploymentName)** ($($deployment.Timestamp))  ")
[void]$md.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  ")
[void]$md.AppendLine("")
[void]$md.AppendLine("Summary: $($summary -join ', ')")
[void]$md.AppendLine("")
foreach ($area in ($results | Select-Object -ExpandProperty Area -Unique)) {
    [void]$md.AppendLine("## $area")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("| Status | Item | Detail |")
    [void]$md.AppendLine("|---|---|---|")
    foreach ($row in ($results | Where-Object { $_.Area -eq $area })) {
        [void]$md.AppendLine("| $($row.Status) | $($row.Item) | $($row.Detail) |")
    }
    [void]$md.AppendLine("")
}
Set-Content -Path $mdPath -Value $md.ToString() -Encoding UTF8
$results | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonPath -Encoding UTF8

Write-Host "`n----------------------------------------"
Write-Host "Summary: $($summary -join ', ')"
Write-Host "Report written to: $mdPath"
Write-Host "Raw data written to: $jsonPath"

if ($results | Where-Object { $_.Status -eq 'FAIL' }) {
    exit 1
}
