param(
    [Parameter(Mandatory = $true)][string]$ResourceGroup,
    [Parameter(Mandatory = $true)][string]$SubscriptionId,
    [Parameter(Mandatory = $true)][string]$WorkspaceName,
    [Parameter(Mandatory = $false)][string]$Location = "",
    [Parameter(Mandatory = $false)][string]$PricingTier = "PerGB2018",
    [Parameter(Mandatory = $false)][int]$DataRetention = 90,
    [Parameter(Mandatory = $false)][string[]]$EnableDataConnectors = @(),
    [Parameter(Mandatory = $false)][string[]]$EnableSolutions1P = @(),
    [Parameter(Mandatory = $false)][string[]]$EnableSolutionsEssentials = @(),
    [Parameter(Mandatory = $false)][string[]]$AadStreams = @(),
    [Parameter(Mandatory = $false)][bool]$EnableUeba = $false,
    [Parameter(Mandatory = $false)][string[]]$IdentityProviders = @(),
    [Parameter(Mandatory = $false)][bool]$EnableDiagnostics = $false,
    [Parameter(Mandatory = $false)][bool]$EnableScheduledAlerts = $false,
    [Parameter(Mandatory = $false)][string[]]$SeverityLevels = @(),
    [Parameter(Mandatory = $false)][string[]]$EnableDiagnosticPolicies = @(),
    [Parameter(Mandatory = $false)][bool]$EnableOngoingDiagnostics = $false,
    [Parameter(Mandatory = $false)][string]$ArtifactsLocation = "https://raw.githubusercontent.com/liamsmith-p/secure365-Sentinel-Genesis/dev/"
)

$context = Get-AzContext
if (!$context) {
    Connect-AzAccount
    $context = Get-AzContext
}

Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
Write-Host "Connected to subscription: $SubscriptionId"

$requiredProviders = @("Microsoft.Insights", "Microsoft.ContainerInstance", "Microsoft.Storage")

foreach ($provider in $requiredProviders) {
    $state = (Get-AzResourceProvider -ProviderNamespace $provider).RegistrationState | Select-Object -First 1
    if ($state -ne "Registered") {
        Write-Host "Registering $provider..."
        Register-AzResourceProvider -ProviderNamespace $provider | Out-Null
    } else {
        Write-Host "$provider already registered."
    }
}

Write-Host "Waiting for resource provider registration..."
foreach ($provider in $requiredProviders) {
    $attempts = 0
    do {
        Start-Sleep -Seconds 10
        $state = (Get-AzResourceProvider -ProviderNamespace $provider).RegistrationState | Select-Object -First 1
        $attempts++
        Write-Host "  $provider`: $state"
    } while ($state -ne "Registered" -and $attempts -lt 18)

    if ($state -ne "Registered") {
        Write-Error "$provider failed to register after 3 minutes. Aborting deployment."
        exit 1
    }
}

Write-Host "All resource providers registered. Starting deployment..."

$templateFile = Join-Path $PSScriptRoot "..\azuredeploy.json"

$deploymentParams = @{
    workspaceName            = $WorkspaceName
    pricingTier              = $PricingTier
    dataRetention            = $DataRetention
    enableDataConnectors     = $EnableDataConnectors
    enableSolutions1P        = $EnableSolutions1P
    enableSolutionsEssentials = $EnableSolutionsEssentials
    aadStreams               = $AadStreams
    enableUeba               = $EnableUeba
    identityProviders        = $IdentityProviders
    enableDiagnostics        = $EnableDiagnostics
    enableScheduledAlerts    = $EnableScheduledAlerts
    severityLevels           = $SeverityLevels
    enableDiagnosticPolicies = $EnableDiagnosticPolicies
    enableOngoingDiagnostics = $EnableOngoingDiagnostics
    _artifactsLocation       = $ArtifactsLocation
}

if ($Location -ne "") {
    $deploymentParams["location"] = $Location
}

New-AzResourceGroupDeployment `
    -ResourceGroupName $ResourceGroup `
    -TemplateFile $templateFile `
    -TemplateParameterObject $deploymentParams `
    -Verbose
