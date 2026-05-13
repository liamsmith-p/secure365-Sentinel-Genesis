param(
    [Parameter(Mandatory = $true)][string]$WorkspaceName,
    [Parameter(Mandatory = $true)][string]$ResourceGroup,
    [Parameter(Mandatory = $true)][string]$SubscriptionId,
    [Parameter(Mandatory = $false)][string[]]$ResourceTypes = @()
)

$context = Get-AzContext
if (!$context) {
    Connect-AzAccount
    $context = Get-AzContext
}

Write-Host "Connected to Azure with subscription: $($context.Subscription)"

$instanceProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($instanceProfile)
$token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)
$authHeader = @{
    'Content-Type'  = 'application/json'
    'Authorization' = 'Bearer ' + $token.AccessToken
}

$workspaceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"
$settingName  = "sentinel-diagnostics"

function Set-SentinelDiagnosticSetting {
    param([string]$ResourceId, [array]$Logs, [array]$Metrics = @())
    $body = @{
        properties = @{
            workspaceId = $workspaceId
            logs        = $Logs
            metrics     = $Metrics
        }
    } | ConvertTo-Json -Depth 10
    $uri = "https://management.azure.com$ResourceId/providers/microsoft.insights/diagnosticSettings/${settingName}?api-version=2021-05-01-preview"
    try {
        Invoke-RestMethod -Uri $uri -Method Put -Headers $authHeader -Body $body | Out-Null
        return $true
    } catch {
        Write-Warning "  Failed: $_"
        return $false
    }
}

function Get-SubscriptionResources {
    param([string]$ResourceType)
    $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resources?`$filter=resourceType eq '$ResourceType'&api-version=2021-04-01"
    return (Invoke-RestMethod -Uri $uri -Method Get -Headers $authHeader).value
}

foreach ($resourceType in $ResourceTypes) {
    switch ($resourceType) {

        "AzureKeyVault" {
            Write-Host "Configuring diagnostics for Azure Key Vaults..."
            $resources = Get-SubscriptionResources -ResourceType "Microsoft.KeyVault/vaults"
            Write-Host "  Found $($resources.Count) Key Vault(s)"
            foreach ($r in $resources) {
                $logs = @(
                    @{ category = "AuditEvent"; enabled = $true; retentionPolicy = @{ enabled = $false; days = 0 } }
                )
                if (Set-SentinelDiagnosticSetting -ResourceId $r.id -Logs $logs) {
                    Write-Host "  Configured: $($r.name)"
                }
            }
        }

        "AzureNetworkSecurityGroup" {
            Write-Host "Configuring diagnostics for Network Security Groups..."
            $resources = Get-SubscriptionResources -ResourceType "Microsoft.Network/networkSecurityGroups"
            Write-Host "  Found $($resources.Count) NSG(s)"
            foreach ($r in $resources) {
                $logs = @(
                    @{ category = "NetworkSecurityGroupEvent";       enabled = $true; retentionPolicy = @{ enabled = $false; days = 0 } },
                    @{ category = "NetworkSecurityGroupRuleCounter"; enabled = $true; retentionPolicy = @{ enabled = $false; days = 0 } }
                )
                if (Set-SentinelDiagnosticSetting -ResourceId $r.id -Logs $logs) {
                    Write-Host "  Configured: $($r.name)"
                }
            }
        }

        "AzureStorageAccount" {
            Write-Host "Configuring diagnostics for Storage Accounts..."
            $resources = Get-SubscriptionResources -ResourceType "Microsoft.Storage/storageAccounts"
            Write-Host "  Found $($resources.Count) Storage Account(s)"
            $storageLogs = @(
                @{ category = "StorageRead";   enabled = $true; retentionPolicy = @{ enabled = $false; days = 0 } },
                @{ category = "StorageWrite";  enabled = $true; retentionPolicy = @{ enabled = $false; days = 0 } },
                @{ category = "StorageDelete"; enabled = $true; retentionPolicy = @{ enabled = $false; days = 0 } }
            )
            $storageMetrics = @(
                @{ category = "Transaction"; enabled = $true; retentionPolicy = @{ enabled = $false; days = 0 } }
            )
            foreach ($r in $resources) {
                # Account-level metrics (feeds AzureMetrics table)
                Set-SentinelDiagnosticSetting -ResourceId $r.id -Logs @() -Metrics $storageMetrics | Out-Null
                # Sub-service logs (feeds StorageBlobLogs, StorageQueueLogs, StorageTableLogs, StorageFileLogs)
                foreach ($service in @("blobServices/default", "queueServices/default", "tableServices/default", "fileServices/default")) {
                    Set-SentinelDiagnosticSetting -ResourceId "$($r.id)/$service" -Logs $storageLogs | Out-Null
                }
                Write-Host "  Configured: $($r.name)"
            }
        }

        "AzureSqlDatabase" {
            Write-Host "Configuring diagnostics for Azure SQL Databases..."
            $resources = Get-SubscriptionResources -ResourceType "Microsoft.Sql/servers/databases"
            Write-Host "  Found $($resources.Count) SQL Database(s)"
            foreach ($r in $resources) {
                if ($r.name -notlike "*/master") {
                    $logs = @(
                        @{ category = "SQLSecurityAuditEvents"; enabled = $true; retentionPolicy = @{ enabled = $false; days = 0 } },
                        @{ category = "SQLInsights";            enabled = $true; retentionPolicy = @{ enabled = $false; days = 0 } },
                        @{ category = "Errors";                 enabled = $true; retentionPolicy = @{ enabled = $false; days = 0 } },
                        @{ category = "Timeouts";               enabled = $true; retentionPolicy = @{ enabled = $false; days = 0 } },
                        @{ category = "Blocks";                 enabled = $true; retentionPolicy = @{ enabled = $false; days = 0 } },
                        @{ category = "Deadlocks";              enabled = $true; retentionPolicy = @{ enabled = $false; days = 0 } }
                    )
                    if (Set-SentinelDiagnosticSetting -ResourceId $r.id -Logs $logs) {
                        Write-Host "  Configured: $($r.name)"
                    }
                }
            }
        }
    }
}

Write-Host "Diagnostic settings configuration complete."
