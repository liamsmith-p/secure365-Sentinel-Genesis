<#
.SYNOPSIS
    Grants Microsoft Sentinel permission to run playbooks (Logic Apps) that live in
    the selected resource groups.

.DESCRIPTION
    Mirrors the Sentinel "Settings > Playbook permissions > Configure permissions"
    panel: assigns the Azure Security Insights first-party app the
    "Microsoft Sentinel Automation Contributor" role on each chosen resource group.
    Once granted, any Sentinel automation rule can run any playbook in that group.

    Run this in the SAME user context you use in the portal (your home tenant). No
    extra permissions are required beyond what you already have there:
      - Owner (or User Access Administrator) on the target resource groups, to
        create the role assignment.
      - The default directory read that lets you resolve a service principal.

    The app ID and role ID below are Microsoft universal constants (identical in
    every tenant) - not customer-specific values.

.PARAMETER PlaybookResourceGroups
    Names of the resource groups containing the playbooks. If omitted, the script
    lists the resource groups in the current subscription and lets you pick.

.PARAMETER SubscriptionId
    Optional. Home-tenant subscription that holds the playbook resource groups.
    Defaults to the current Az context subscription.

.EXAMPLE
    ./Configure-PlaybookPermissions.ps1 -PlaybookResourceGroups 'rg-soar-prod','rg-playbooks'

.EXAMPLE
    # Interactive: pick the resource groups from a list / grid.
    ./Configure-PlaybookPermissions.ps1
#>
param(
    [Parameter(Mandatory = $false)][string[]]$PlaybookResourceGroups = @(),
    [Parameter(Mandatory = $false)][string]$SubscriptionId
)

# Azure Security Insights (Microsoft Sentinel) first-party app - universal appId, same in every tenant
$sentinelAppId = "98785600-1bb7-4fb9-b9fa-19afe2c8a360"
# Microsoft Sentinel Automation Contributor - fixed built-in role definition GUID
$automationContributorRoleId = "f4c81013-99ee-4d62-a7ee-b3f1f648599a"

$context = Get-AzContext
if (!$context) {
    Connect-AzAccount | Out-Null
    $context = Get-AzContext
}

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    $context = Get-AzContext
}

Write-Host "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
Write-Host "Tenant:       $($context.Tenant.Id)"

# Resolve the Azure Security Insights service principal object ID in this tenant
$sp = Get-AzADServicePrincipal -ApplicationId $sentinelAppId
if (!$sp) {
    Write-Error "Could not find the 'Azure Security Insights' service principal (appId $sentinelAppId) in this tenant. Ensure Microsoft Sentinel has been enabled at least once in the tenant."
    exit 1
}
$principalId = $sp.Id
Write-Host "Azure Security Insights object ID: $principalId"

# If no resource groups were supplied, discover and let the user select
if (-not $PlaybookResourceGroups -or $PlaybookResourceGroups.Count -eq 0) {
    $allGroups = Get-AzResourceGroup | Sort-Object ResourceGroupName
    if (-not $allGroups) {
        Write-Error "No resource groups found in subscription $($context.Subscription.Id)."
        exit 1
    }

    $gridCmd = Get-Command Out-GridView -ErrorAction SilentlyContinue
    if ($gridCmd) {
        $picked = $allGroups |
            Select-Object ResourceGroupName, Location |
            Out-GridView -Title "Select the resource groups containing playbooks (Ctrl+click for multiple)" -PassThru
        $PlaybookResourceGroups = @($picked.ResourceGroupName)
    }
    else {
        Write-Host ""
        Write-Host "Resource groups in this subscription:"
        for ($i = 0; $i -lt $allGroups.Count; $i++) {
            Write-Host ("  [{0}] {1} ({2})" -f ($i + 1), $allGroups[$i].ResourceGroupName, $allGroups[$i].Location)
        }
        Write-Host ""
        $selection = Read-Host "Enter the numbers to grant (comma-separated), or 'all'"

        if ($selection -eq 'all') {
            $PlaybookResourceGroups = @($allGroups.ResourceGroupName)
        }
        else {
            $indices = $selection -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
            $PlaybookResourceGroups = @(foreach ($idx in $indices) {
                    $n = [int]$idx - 1
                    if ($n -ge 0 -and $n -lt $allGroups.Count) { $allGroups[$n].ResourceGroupName }
                })
        }
    }
}

if (-not $PlaybookResourceGroups -or $PlaybookResourceGroups.Count -eq 0) {
    Write-Error "No resource groups selected. Nothing to do."
    exit 1
}

Write-Host ""
Write-Host "Granting 'Microsoft Sentinel Automation Contributor' to Azure Security Insights on:"
$PlaybookResourceGroups | ForEach-Object { Write-Host "  - $_" }
Write-Host ""

foreach ($rg in $PlaybookResourceGroups) {
    $rgObj = Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue
    if (-not $rgObj) {
        Write-Warning "Resource group '$rg' not found in this subscription - skipping."
        continue
    }

    $scope = $rgObj.ResourceId
    $existing = Get-AzRoleAssignment -ObjectId $principalId -RoleDefinitionId $automationContributorRoleId -Scope $scope -ErrorAction SilentlyContinue |
        Where-Object { $_.Scope -eq $scope }
    if ($existing) {
        Write-Host "  ${rg}: already granted - skipping."
        continue
    }

    try {
        New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionId $automationContributorRoleId -Scope $scope -ErrorAction Stop | Out-Null
        Write-Host "  ${rg}: granted."
    }
    catch {
        Write-Warning "  ${rg}: failed to grant - $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "Playbook permissions configuration complete."
