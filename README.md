# secure365-Sentinel-Genesis

Automated Microsoft Sentinel deployment provided by Softwerx. Deploys a fully configured Sentinel workspace including Content Hub solutions, data connectors, analytics rules, and diagnostic settings, all via a single ARM template.

![Sentinel Solution](https://github.com/user-attachments/assets/647bda8b-e007-49a7-a2f7-da93e5570126)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fliamsmith-p%2Fsecure365-Sentinel-Genesis%2Fmain%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fliamsmith-p%2Fsecure365-Sentinel-Genesis%2Fmain%2FcreateUiDefinition.json)

---

## Prerequisites

Complete these steps before deploying or the deployment will fail.

### 1. Required permissions

| Permission | Scope | Required for |
|---|---|---|
| **Owner** | Azure subscription | Creating all resources, subscription-level diagnostic settings, Azure Policy assignments, and role assignments used by deployment scripts |
| **Global Administrator** or **Security Administrator** | Entra ID tenant | Configuring Entra ID diagnostic settings, data connectors, enabling UEBA |

> Contributor alone is not sufficient - the deployment creates role assignments which require Owner or User Access Administrator. Security Administrator is sufficient for most connector operations, but Global Administrator may be required on some tenants for the Entra ID tenant-scoped diagnostic settings resource.

### 2. Required resource providers

The deployment uses Azure Container Instances and Storage for its deployment scripts, and Azure Monitor (Microsoft.Insights) for diagnostic settings. These three resource providers (Microsoft.Insights, Microsoft.ContainerInstance and Microsoft.Storage) are registered automatically. The very first step of the template registers all three and waits until they report Registered before anything else runs, so there is no manual step to complete here.

### 3. New tenant checklist

If deploying to a **brand new tenant**, complete these before deploying:

1. **Provision Microsoft Defender XDR** - sign in to [security.microsoft.com](https://security.microsoft.com) as a Global Administrator and let the portal fully load. This initialises the XDR workspace. Without this, enabling UEBA will fail with a misleading permissions error even if your permissions are correct.
2. **Verify your Entra ID roles** - confirm your account has Security Administrator or Global Administrator assigned in [Entra ID](https://entra.microsoft.com) > Roles and administrators, not just Azure RBAC.

---

## Deployment walkthrough

Click the relevant **Deploy to Azure** button above and work through each tab.

### Basics

| Field | Guidance |
|---|---|
| Subscription | Select the subscription where Sentinel will be deployed |
| Resource group | Create new or select existing |
| Region | Select your preferred Azure region |
| Workspace Name | Name for the new Log Analytics / Sentinel workspace |
| Retention (days) | 90 days recommended as a starting point (30–730 supported). The `SecurityIncident` table is pinned to 365 days regardless of this value, so incident history is kept for a year even on a shorter workspace retention. |
| Pricing tier | Pay-as-you-go is the only current option |

Example:
<img width="859" height="567" alt="image" src="https://github.com/user-attachments/assets/9dbfeed2-666c-48d3-afd8-d6269c76a304" />

---

### Settings

**Enable UEBA** - enables User Entity Behavior Analytics.

- Only enable this if Microsoft Defender XDR has already been provisioned (see new tenant checklist)
- Under **Identity Providers**, select **Microsoft Entra ID** for cloud identity sync
- Do **not** select **Active Directory** unless Microsoft Defender for Identity (MDI) is already deployed and fully onboarded - selecting it without MDI will fail with a precondition error

**Enable Sentinel auditing and health monitoring** - creates the full diagnostic setting (`allLogs`) that streams both health (`SentinelHealth`) and audit (`SentinelAudit`) data for all Sentinel resource types: analytics rules, data connectors, automation rules, and playbooks. This is equivalent to clicking **Enable** on the Sentinel **Auditing and health monitoring** settings page.

Example:
<img width="857" height="299" alt="image" src="https://github.com/user-attachments/assets/89d833c2-19bf-47ee-a291-986ce9d3ecc9" />


---

### Content Hub Solutions

Each solution installs analytics rule templates, workbooks, hunting queries, and parsers for that product or service. Installing a solution does not automatically connect data, data sources must be connected separately in the Data Connectors tab.

#### Microsoft solutions

| Solution | What it covers |
|---|---|
| Microsoft Entra ID | Sign-in logs, audit logs, identity risk events |
| Azure Activity | Subscription-level administrative, security, and service health events |
| Microsoft Defender for Cloud | Cloud workload protection alerts |
| Microsoft Defender XDR | Unified XDR incident and alert analytics |
| Microsoft Defender for Cloud Apps | Cloud app security, shadow IT, anomalous behaviour |
| Microsoft 365 | Exchange, SharePoint, and Teams activity |
| Azure Key Vault | Key Vault audit, access, and secret operation analytics |
| Azure Network Security Groups | NSG flow event and rule counter analytics |
| Azure Storage | Storage account read, write, and delete analytics |
| Azure SQL Database | SQL audit, error, timeout, and security analytics |
| Threat Intelligence (NEW) | TI indicator ingestion via MDTI free tier; matching rules and workbooks using the `ThreatIntelIndicatorsV2` table |
| Azure Kubernetes Service | AKS audit log and diagnostic analytics for Kubernetes workloads |
| Azure Firewall | Application rule, network rule, DNS proxy, and threat intelligence log analytics |
| Azure Web Application Firewall | WAF event analytics across Application Gateway, Front Door, and CDN |
| Dynamics 365 | Dynamics 365 activity, audit, and configuration change analytics |
| Microsoft Power BI | Power BI audit activity analytics (dashboard views, dataset access, sharing) |
| Microsoft Project | Project activity log and access analytics |
| Windows Security Events | Analytics rules and workbooks for Windows Security Event data collected via Azure Monitor Agent. **Requires separate agent deployment and Data Collection Rule configuration on target machines - not automated by this template.** |
| Common Event Format (CEF) | Parsers, rules, and workbooks for CEF-formatted syslog data from firewalls, IDS/IPS, and security appliances. **Requires a CEF forwarder or AMA syslog configuration on a Linux collector - not automated by this template.** |

#### Essentials packs

Cross-product detection content recommended for all deployments regardless of which solutions are selected.

| Pack | What it covers |
|---|---|
| Attacker Tools Threat Protection Essentials | Detection of attacker tooling commonly seen across campaigns |
| Cloud Identity Threat Protection Essentials | Suspicious sign-ins, privilege grants, MFA disable, and other cloud identity attacks |
| Cloud Service Threat Protection Essentials | Attacks against cloud services including Key Vault, Storage, and compute |
| Endpoint Threat Protection Essentials | Windows endpoint threat detection and investigation content |
| Network Session Essentials | Cross-source network correlation using ASIM across 15+ data sources |
| Network Threat Protection Essentials | Suspicious network behaviour detection across ingested data sources |
| SOC Handbook | SOC analyst resources for understanding point-in-time security posture |
| UEBA Essentials | UEBA table-based hunting queries for targeted threat scenarios |

---

### Data Connectors

Configures which data sources send logs to the Sentinel workspace. The tab offers six connectors, all configured automatically during deployment.

| Connector | Notes |
|---|---|
| **Microsoft Entra ID** | Configures tenant-level diagnostic settings to forward the standard Entra ID log categories that are available in every tenant: sign-in, audit, non-interactive user sign-in, service principal sign-in, managed identity sign-in, provisioning, ADFS sign-in, risky users, user risk events, risky service principals, service principal risk events, Microsoft Graph activity, network access traffic, enriched Office 365 audit, and remote network health. Requires Global Administrator or Security Administrator. Some newer and role-gated categories are left out on purpose so the deployment does not fail (see Troubleshooting). |
| **Azure Activity** | Configures a subscription-level diagnostic setting to forward all activity log categories (Administrative, Security, ServiceHealth, Alert, Recommendation, Policy, Autoscale, ResourceHealth). Requires Owner on subscription. |
| **Microsoft 365** | Connects Exchange Online, SharePoint Online, and Microsoft Teams audit logs (`OfficeActivity` table). Requires Security Administrator. |
| **Microsoft Power BI** | Ingests Power BI audit activity. Also select the Microsoft Power BI Content Hub solution for the matching analytics rules and workbooks. Requires Security Administrator. |
| **Microsoft Project** | Ingests Microsoft Project activity logs. Also select the Microsoft Project Content Hub solution for the matching content. Requires Security Administrator. |
| **Dynamics 365** | Ingests Dynamics 365 Common Data Service activity logs. Also select the Dynamics 365 Content Hub solution. Requires Security Administrator. |

> **Defender connectors are not offered here.** Microsoft Defender XDR, Defender for Cloud, Entra ID Identity Protection, and Defender for Cloud Apps are managed from the Microsoft Defender portal when XDR is active, and configuring them through ARM conflicts with that. Install their Content Hub solutions for the analytics content, then connect the data in the Defender portal (see Post-deployment steps).

> **Windows Security Events via AMA and CEF:** These are agent-based connectors and cannot be fully automated via ARM deployment. Install the relevant solutions to get the analytics content, then configure Azure Monitor Agent, Data Collection Rules, and any required log forwarders manually post-deployment.

Example:
<img width="868" height="742" alt="image" src="https://github.com/user-attachments/assets/41b3390b-efef-4d79-85ff-635e33733893" />

---

### Policy

Key Vault, NSG, Storage, SQL Database, Azure Firewall, and Application Gateway WAF have no Sentinel API connector: their logs are collected through Azure Diagnostics instead. This tab configures diagnostic settings on those resource types and, optionally, keeps them enforced with Azure Policy. All logs stream to the workspace selected on the Basics tab.

| Option | Resource type | Log categories |
|---|---|---|
| Azure Key Vault | `Microsoft.KeyVault/vaults` | AuditEvent |
| Azure Network Security Groups | `Microsoft.Network/networkSecurityGroups` | NetworkSecurityGroupEvent, NetworkSecurityGroupRuleCounter |
| Azure Storage Accounts | `Microsoft.Storage/storageAccounts` | StorageRead, StorageWrite, StorageDelete (blob service) |
| Azure SQL Databases | `Microsoft.Sql/servers/databases` | SQLSecurityAuditEvents, SQLInsights, Errors, Timeouts, Blocks, Deadlocks |
| Azure Firewall | `Microsoft.Network/azureFirewalls` | AzureFirewallApplicationRule, AzureFirewallNetworkRule, AzureFirewallDnsProxy, AzureFirewallThreatIntel |
| Azure Application Gateway (WAF) | `Microsoft.Network/applicationGateways` | ApplicationGatewayAccessLog, ApplicationGatewayPerformanceLog, ApplicationGatewayFirewallLog |

**Resource types to configure** - for each type you select, a deployment script scans the workspace subscription and applies a diagnostic setting named `sentinel-diagnostics` to every existing resource of that type. Existing settings with a different name are not modified.

**Enable Azure Policy for ongoing diagnostic settings enforcement** - when ticked, creates a `deployIfNotExists` policy assignment plus a remediation task in each subscription you select under **Subscriptions to apply the diagnostic policy to**. This covers resources created after deployment and, through the selected-subscriptions list, resources outside the workspace subscription. Requires Owner on each selected subscription. Without this box ticked, only existing resources in the workspace subscription are configured, once, at deploy time.

Example:
<img width="859" height="432" alt="image" src="https://github.com/user-attachments/assets/2abe0e97-6907-4065-a3ac-102d3f83e91b" />

---

### Analytics Rules (optional)

**Enable Scheduled alert rules** - automatically creates active analytics rules from the templates included in your selected Content Hub solutions.

- Rules are only created for solutions selected in the Content Hub tab
- Rules are filtered to the severity levels you select - High and Medium are selected by default in most tiers; Enterprise also enables Low
- The deployment checks for existing rules before creating new ones - re-running the deployment will not duplicate rules
- Rules will not generate alerts unless the relevant data source is connected and sending data

Example:
<img width="863" height="398" alt="image" src="https://github.com/user-attachments/assets/2f9ace58-824d-4577-b21c-a2ef27053991" />

---

### Service Provider (optional)

Delegates this subscription to a managing service provider through Azure Lighthouse, so they can operate Sentinel from their own tenant without a guest account. Enabling it creates a registration definition and a subscription-scoped assignment. Requires Owner on the subscription.

| Field | Guidance |
|---|---|
| Enable Azure Lighthouse delegation | Leave unticked to skip this entirely |
| Managing Tenant ID | The Entra tenant ID (GUID) of the service provider |
| Offer Name | Display name for the delegation, used as the registration definition name |
| Offer Description | Optional free text |
| Authorizations | One row per principal and role pair, up to 20. Each row takes a **Principal Object ID** (a user, group, or service principal in the managing tenant), a **Display Name**, and a **Role** chosen from a fixed list (Sentinel Contributor/Reader, Log Analytics Contributor/Reader, Monitoring Contributor/Reader, Security Admin/Reader, Resource Policy Contributor, Reader, Contributor, User Access Administrator, Owner). Prefer least privilege: Sentinel Contributor plus Reader covers most SOC operations. |

---

## What is and isn't automated

| Capability | Automated |
|---|---|
| Resource provider registration (Insights, ContainerInstance, Storage) | ✅ |
| Workspace and Sentinel creation | ✅ |
| Content Hub solution installation | ✅ |
| Analytics rule creation from templates | ✅ |
| Microsoft Entra ID diagnostic settings | ✅ |
| Azure Activity diagnostic settings | ✅ |
| Microsoft 365 connector | ✅ |
| Microsoft Power BI connector | ✅ |
| Microsoft Project connector | ✅ |
| Dynamics 365 connector | ✅ |
| Threat Intelligence (MDTI free tier) connector | ✅ Auto-connected after solution install |
| UEBA configuration | ✅ |
| Sentinel auditing and health diagnostic setting | ✅ |
| Resource-level diagnostic settings (KV, NSG, Storage, SQL, Firewall, WAF) | ✅ |
| Azure Policy for ongoing diagnostics enforcement, across selected subscriptions | ✅ |
| Azure Lighthouse delegation to a managing service provider | ✅ Optional, via the Service Provider tab |
| Defender XDR, Defender for Cloud, Entra ID Identity Protection, Defender for Cloud Apps connectors | ❌ Not offered - XDR-managed, configure in the Defender portal |
| Defender XDR unified workspace connection | ❌ Manual, must be done in the Defender portal |
| Windows Security Events via AMA | ❌ Manual, requires agent and DCR configuration |
| CEF / Syslog via AMA | ❌ Manual, requires forwarder and DCR configuration |
| Playbook (Logic App) permissions for automation | ⚠️ Scripted, run `Scripts/Configure-PlaybookPermissions.ps1` in your own user context (not part of the ARM deployment) |

---

## Post-deployment steps

After the deployment completes:

1. **Connect Defender XDR unified workspace** - in the [Microsoft Defender portal](https://security.microsoft.com), go to **Settings > Microsoft Sentinel**, select the newly created workspace, and click **Connect**. This enables the full XDR-Sentinel integration including the advanced hunting experience. This step cannot be automated.

2. **Verify data connector status** - in the Sentinel workspace, go to **Configuration > Data connectors** and confirm the connectors you selected show as Connected.

3. **Review analytics rules** - go to **Configuration > Analytics** and confirm rules are in Active state. Rules that reference data sources not yet connected will show a warning - this is expected until the data source is live.

4. **Configure agent-based connectors if selected** - if you installed the Windows Security Events or CEF solutions, deploy Azure Monitor Agent and configure the relevant Data Collection Rules on your target machines or log forwarders.

5. **Configure playbook permissions (optional)** - if Sentinel automation rules need to run playbooks (Logic Apps), grant Sentinel permission on the resource groups that contain those playbooks. This is the scripted equivalent of the Sentinel **Settings > Playbook permissions > Configure permissions** panel - it assigns the Azure Security Insights app the **Microsoft Sentinel Automation Contributor** role on each selected resource group.

   Run it **in your own user context** (the same context you'd use in the portal) - not as part of the ARM deployment, and no extra permissions beyond Owner on the target resource groups:

   ```powershell
   # Interactive - lists the resource groups in the current subscription and lets you pick
   ./Scripts/Configure-PlaybookPermissions.ps1

   # Or specify them directly
   ./Scripts/Configure-PlaybookPermissions.ps1 -PlaybookResourceGroups 'rg-soar-prod','rg-playbooks' -SubscriptionId <home-sub-id>
   ```

   The script resolves the per-tenant Azure Security Insights object ID automatically (via the well-known Microsoft app ID), so nothing tenant-specific is hardcoded. The grant applies to the subscription/tenant you run it against - for playbooks in your home tenant, run it while signed into your home tenant. It's safe to re-run; existing grants are detected and skipped.

---

## Troubleshooting

**Where are the Defender connectors?**
Microsoft Defender XDR, Defender for Cloud, Entra ID Identity Protection, and Defender for Cloud Apps are deliberately not offered on the Data connectors tab. When XDR is active these are managed from the Microsoft Defender portal, and configuring them through ARM returns a "changes to connector are disabled" conflict. Install their Content Hub solutions here for the analytics content, then connect the data in the Defender portal.

**"Polygon precondition failed" on EntityAnalytics / UEBA**
Cause: The Active Directory identity provider was selected for UEBA without Microsoft Defender for Identity deployed. Re-deploy with only Microsoft Entra ID selected, or deselect UEBA entirely if MDI is not in scope.

**UEBA fails with permissions error on a new tenant**
Cause: Microsoft Defender XDR has not been provisioned yet. Visit [security.microsoft.com](https://security.microsoft.com) as a Global Administrator, let the portal fully load, then re-deploy.

**Deployment fails with "ResourceProviderNotRegistered" for Microsoft.ContainerInstance or Microsoft.Storage**
Cause: The required resource providers were not registered in time. The first step of the deployment (`registerProviders`) registers Microsoft.Insights, Microsoft.ContainerInstance and Microsoft.Storage and waits for them, so this should not normally happen. If it does, re-running the deployment resolves it because the providers are registered by then.

**No analytics rules created after deployment**
Cause: Either the Enable Scheduled alert rules checkbox was not ticked, no severity levels were selected, or no Content Hub solutions were selected. Re-deploy with these options configured.

**Threat Intelligence connector shows as not connected**
Cause: The MDTI free connector is auto-connected by the deployment script after the solution installs, but it requires a short wait. If it still shows as disconnected after 10 minutes, check the `deployRules` deployment script logs in the Azure portal under the resource group > Deployments > deployRules > Logs.

**Diagnostic settings not appearing on existing resources**
Cause: The deployment script may have run before the managed identity received its Contributor role assignment. The template includes a sleep period to handle this, but on slow tenants it can still occasionally fail. Re-running the deployment will retry the diagnostic settings script.

**Deployment times out at approximately 1200 seconds ("Action sequencer job exceeded max allowed time")**
Cause: Each deployment script runs in a separate Azure Container Instance which takes 30–60 seconds to start. On a large first-time deployment, cumulative startup time across all containers can approach the ARM 1200-second limit. Re-deploying is faster on subsequent runs as existing rules and settings are detected and skipped.

**Entra ID diagnostic settings fail with a "category not supported" (BadRequest) error**
Affects: the Microsoft Entra ID connector. All categories are routed through a single `microsoft.aadiam/diagnosticSettings` resource, which is all or nothing. If the tenant does not support one category, the whole resource fails and none of the Entra logs are routed. The template therefore only includes the standard categories that are available in every tenant.

To see exactly which categories your tenant supports, open the portal at **Entra ID > Monitoring & health > Diagnostic settings > Add diagnostic setting** (or **Sentinel > Data connectors > Microsoft Entra ID**). Only add a category to the `logs` array in `LinkedTemplates/dataConnectors.json` (the `-entraIdDiagnosticSettings` resource) if it appears there for the tenants you deploy to.

The following categories are left out on purpose because they are newer, in preview, or need an extra role, and are rejected in tenants that do not have the feature:
- `CustomSecurityAttributeAuditLogs`: set up in a separate "Custom security attributes" section. Microsoft recommends keeping it in its own diagnostic setting and it needs the **Attribute Log Administrator** role to route. If you need it, create a separate diagnostic setting for it by hand after assigning that role. Do not add it back to the shared `logs` array.
- `RiskyAgents` and `AgentRiskEvents`: ID Protection for agents categories, rejected where that feature is not present.
- `MicrosoftServicePrincipalSignInLogs`: preview first-party service-to-service sign-in logs. High volume and not present in all tenants.
