param()

$ErrorActionPreference = 'Stop'

# Providers this deployment relies on:
#   Microsoft.Insights          - diagnostic settings (Entra ID, Azure Activity, resource-level)
#   Microsoft.ContainerInstance - runs the deployment scripts
#   Microsoft.Storage           - backs the deployment scripts
$providers = @('Microsoft.Insights', 'Microsoft.ContainerInstance', 'Microsoft.Storage')

# The managed identity's Contributor role assignment can take a short while to
# propagate, so retry the registration call until it is accepted.
foreach ($provider in $providers) {
    $requested = $false
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        try {
            Register-AzResourceProvider -ProviderNamespace $provider -ErrorAction Stop | Out-Null
            Write-Host "Registration requested for $provider."
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
}

# Registration is asynchronous and completes per region, so wait until each
# provider reports Registered before the rest of the deployment continues.
foreach ($provider in $providers) {
    $state = $null
    $deadline = (Get-Date).AddMinutes(10)
    do {
        $state = (Get-AzResourceProvider -ListAvailable | Where-Object { $_.ProviderNamespace -eq $provider }).RegistrationState | Select-Object -First 1
        Write-Host "$provider : $state"
        if ($state -eq 'Registered') { break }
        Start-Sleep -Seconds 15
    } while ((Get-Date) -lt $deadline)

    if ($state -ne 'Registered') {
        throw "$provider did not reach the Registered state within the timeout."
    }
}

Write-Host "All required resource providers are registered."
