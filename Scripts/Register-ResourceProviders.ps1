param(
    [Parameter(Mandatory = $true)][string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'

# Providers this deployment relies on:
#   Microsoft.Insights          - diagnostic settings (Entra ID, Azure Activity, resource-level)
#   Microsoft.ContainerInstance - runs the deployment scripts
#   Microsoft.Storage           - backs the deployment scripts
$providers = @('Microsoft.Insights', 'Microsoft.ContainerInstance', 'Microsoft.Storage')

# ---------------------------------------------------------------------------
# 1. Pin the Azure context to the target subscription.
#
# The deployment-script container authenticates as the user-assigned managed
# identity at start-up. If that identity's Contributor role assignment has not
# finished propagating yet, the session has no subscription in context and
# every ARM call fails with "'this.Client.SubscriptionId' cannot be null".
# dependsOn only waits for the assignment to be created, not replicated, so
# re-select the context on a loop until it sticks.
# ---------------------------------------------------------------------------
$contextDeadline = (Get-Date).AddMinutes(20)
$context = $null
do {
    try {
        $context = Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop
    }
    catch {
        Write-Host "Waiting for the managed identity to gain access to $SubscriptionId : $($_.Exception.Message)"
        $context = $null
    }
    if ($context -and $context.Subscription.Id -eq $SubscriptionId) { break }
    Start-Sleep -Seconds 30
} while ((Get-Date) -lt $contextDeadline)

if (-not $context -or $context.Subscription.Id -ne $SubscriptionId) {
    throw "Managed identity never gained access to subscription $SubscriptionId within the timeout."
}

Write-Host "Azure context set to subscription $SubscriptionId."

# Current registration state of a single provider, or $null if it cannot be read.
# Note: -ProviderNamespace and -ListAvailable are separate parameter sets on the
# Az module shipped in the deployment-script container, so they cannot be
# combined. Pull the full list and filter it, the way this script always has.
function Get-ProviderRegistrationState {
    param([string]$Namespace)
    try {
        return (Get-AzResourceProvider -ListAvailable -ErrorAction Stop |
            Where-Object { $_.ProviderNamespace -eq $Namespace } |
            Select-Object -First 1).RegistrationState
    }
    catch {
        Write-Host "Could not read registration state for $Namespace : $($_.Exception.Message)"
        return $null
    }
}

# ---------------------------------------------------------------------------
# 2. Request registration only for providers that are not already registered.
#    Registering an already-registered provider is a no-op, but skipping it
#    avoids an unnecessary call and, more usefully, lets us skip the wait in
#    step 3 for the common case where every provider is already there.
# ---------------------------------------------------------------------------
$needsWait = @()
foreach ($provider in $providers) {
    $state = Get-ProviderRegistrationState -Namespace $provider
    if ($state -eq 'Registered') {
        Write-Host "$provider is already registered, skipping."
        continue
    }

    $requested = $false
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        try {
            Register-AzResourceProvider -ProviderNamespace $provider -ErrorAction Stop | Out-Null
            Write-Host "Registration requested for $provider (was '$state')."
            $requested = $true
            break
        }
        catch {
            Write-Host "Attempt $attempt to register $provider failed: $($_.Exception.Message)"
            Start-Sleep -Seconds 15
        }
    }
    if (-not $requested) {
        throw "Could not request registration for $provider after multiple attempts."
    }
    $needsWait += $provider
}

# ---------------------------------------------------------------------------
# 3. Registration is asynchronous and completes per region, so wait until each
#    provider we just requested reports Registered before the deployment
#    continues. Providers that were already registered are not re-checked.
# ---------------------------------------------------------------------------
foreach ($provider in $needsWait) {
    $state = $null
    $deadline = (Get-Date).AddMinutes(10)
    do {
        $state = Get-ProviderRegistrationState -Namespace $provider
        Write-Host "$provider : $state"
        if ($state -eq 'Registered') { break }
        Start-Sleep -Seconds 15
    } while ((Get-Date) -lt $deadline)

    if ($state -ne 'Registered') {
        throw "$provider did not reach the Registered state within the timeout."
    }
}

Write-Host "All required resource providers are registered."
