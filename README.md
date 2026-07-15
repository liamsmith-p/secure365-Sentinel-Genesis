# secure365-Sentinel-Genesis

Automated Microsoft Sentinel deployment provided by Softwerx. Deploys a fully configured Sentinel workspace including Content Hub solutions, data connectors, analytics rules, and diagnostic settings, all via a single ARM template.

![Sentinel Solution](https://github.com/user-attachments/assets/647bda8b-e007-49a7-a2f7-da93e5570126)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fliamsmith-p%2Fsecure365-Sentinel-Genesis%2Fdev%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fliamsmith-p%2Fsecure365-Sentinel-Genesis%2Fdev%2FcreateUiDefinition.json)

---

## Prerequisites

Complete these steps before deploying or the deployment will fail.

### 1. Required permissions

| Permission | Scope | Required for |
|---|---|---|
| **Owner** | Azure subscription | Creating all resources, subscription-level diagnostic settings, Azure Policy assignments, and role assignments used by deployment scripts |
| **Global Administrator** or **Security Administrator** | Entra ID tenant | Configuring Entra ID diagnostic settings, data connectors, enabling UEBA |

> Contributor alone is not sufficient — the deployment creates role assignments which require Owner or User Access Administrator. Security Administrator is sufficient for most connector operations, but Global Administrator may be required on some tenants for the Entra ID tenant-scoped diagnostic settings resource.

### 2. Register required resource providers

The deployment uses Azure Container Instances and Storage for deployment scripts, and Azure Monitor (Microsoft.Insights) for diagnostic settings. Most of these resource providers will already be registered in the customer's subscription before deploying. In the scenario they are not, either run this once in Azure Cloud Shell (PowerShell):

```powershell
Register-AzResourceProvider -ProviderNamespace Microsoft.Insights
Register-AzResourceProvider -ProviderNamespace Microsoft.ContainerInstance
Register-AzResourceProvider -ProviderNamespace Microsoft.Storage
```

Wait for all three to show `RegistrationState: Registered` before proceeding:

```powershell
Get-AzResourceProvider -ProviderNamespace Microsoft.Insights | Select-Object RegistrationState
Get-AzResourceProvider -ProviderNamespace Microsoft.ContainerInstance | Select-Object RegistrationState
Get-AzResourceProvider -ProviderNamespace Microsoft.Storage | Select-Object RegistrationState
```
**OR**

In the customer's tenant, navigate to Subscriptions > Settings > Resource providers and search for Microsoft.Insights, Microsoft.ContainerInstance and Microsoft.Storage. Click the '...' and register the resource providers.

> If you deploy with `Scripts/Deploy.ps1` instead of the portal button, these three providers are registered automatically before the deployment starts — no manual step needed.

### 3. New tenant checklist

If deploying to a **brand new tenant**, complete these before deploying:

1. **Provision Microsoft Defender XDR** — sign in to [security.microsoft.com](https://security.microsoft.com) as a Global Administrator and let the portal fully load. This initialises the XDR workspace. Without this, enabling UEBA will fail with a misleading permissions error even if your permissions are correct.
2. **Verify your Entra ID roles** — confirm your account has Security Administrator or Global Administrator assigned in [Entra ID](https://entra.microsoft.com) > Roles and administrators, not just Azure RBAC.

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
| Retention (days) | 90 days recommended as a starting point (30–730 supported) |
| Pricing tier | Pay-as-you-go is the only current option |

---

### Settings

**Enable UEBA** — enables User Entity Behavior Analytics.

- Only enable this if Microsoft Defender XDR has already been provisioned (see new tenant checklist)
- Under **Identity Providers**, select **Microsoft Entra ID** for cloud identity sync
- Do **not** select **Active Directory** unless Microsoft Defender for Identity (MDI) is already deployed and fully onboarded — selecting it without MDI will fail with a precondition error

**Enable Sentinel auditing and health monitoring** — creates the full diagnostic setting (`allLogs`) that streams both health (`SentinelHealth`) and audit (`SentinelAudit`) data for all Sentinel resource types — analytics rules, data connectors, automation rules, and playbooks. This is equivalent to clicking **Enable** on the Sentinel **Auditing and health monitoring** settings page.

---

### Content Hub Solutions

Each solution deploys analytics rule templates, workbooks, hunting queries, and parsers for that product or service. Installing a solution does not automatically connect data — data sources must be connected separately in the Data Connectors tab.

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
| Windows Security Events | Analytics rules and workbooks for Windows Security Event data collected via Azure Monitor Agent. **Requires separate agent deployment and Data Collection Rule configuration on target machines — not automated by this template.** |
| Common Event Format (CEF) | Parsers, rules, and workbooks for CEF-formatted syslog data from firewalls, IDS/IPS, and security appliances. **Requires a CEF forwarder or AMA syslog configuration on a Linux collector — not automated by this template.** |

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

Configures which data sources send logs to the Sentinel workspace.

#### Sentinel API connectors

Configured automatically during deployment.

| Connector | Notes |
|---|---|
| **Microsoft Entra ID** | Configures tenant-level diagnostic settings to forward **all** available Entra ID log categories (sign-in, audit, non-interactive, service principal, managed identity, provisioning, ADFS, identity and workload/agent risk, Microsoft Graph activity, Global Secure Access network logs, and custom security attribute audit logs). Requires Global Administrator or Security Administrator; `CustomSecurityAttributeAuditLogs` additionally requires the Attribute Log Administrator role (see Troubleshooting). |
| **Azure Activity** | Configures a subscription-level diagnostic setting to forward all activity log categories (Administrative, Security, ServiceHealth, Alert, Recommendation, Policy, Autoscale, ResourceHealth). Requires Owner on subscription. |
| **Microsoft Defender XDR** | Enables incident and alert sync between XDR and Sentinel. Requires Security Administrator. |
| **Microsoft 365** | Connects Exchange Online, SharePoint Online, and Microsoft Teams audit logs. Requires Security Administrator. |
| **Microsoft Defender for Cloud** | Ingests Defender for Cloud security alerts into Sentinel. Requires Security Reader on subscription. |
| **Dynamics 365** | Ingests Dynamics 365 Common Data Service activity logs. Requires Security Administrator. |
| **Microsoft Entra ID Identity Protection** ⚠️ | Do **not** select if your tenant uses Microsoft Defender XDR — Identity Protection is managed by the XDR portal and enabling it here will cause a conflict error. Configure via the Defender portal instead. |
| **Microsoft Defender for Cloud Apps** ⚠️ | Do **not** select if your tenant manages Defender for Cloud Apps through the Microsoft Defender XDR portal — it will fail with a conflict error. Configure via the Defender portal instead. |

> **Power BI and Project:** These services do not have standalone Sentinel connector kinds. Their audit data flows through the Microsoft 365 audit logs (`OfficeActivity` table) when the Microsoft 365 connector is enabled. Select the Microsoft Power BI and Microsoft Project solutions to install the associated analytics rules and workbooks.

> **Windows Security Events via AMA and CEF:** These are agent-based connectors and cannot be fully automated via ARM deployment. Install the relevant solutions to get the analytics content, then configure Azure Monitor Agent, Data Collection Rules, and any required log forwarders manually post-deployment.

#### Azure Diagnostics (resource-level)

Configures diagnostic settings on existing resources in the subscription at deploy time, forwarding logs to the Sentinel workspace. A deployment script scans the entire subscription and configures any matching resources it finds.

| Option | Resource type | Log categories |
|---|---|---|
| Azure Key Vault | `Microsoft.KeyVault/vaults` | AuditEvent |
| Azure Network Security Groups | `Microsoft.Network/networkSecurityGroups` | NetworkSecurityGroupEvent, NetworkSecurityGroupRuleCounter |
| Azure Storage Accounts | `Microsoft.Storage/storageAccounts` | StorageRead, StorageWrite, StorageDelete (blob, queue, table, file); Transaction metrics |
| Azure SQL Databases | `Microsoft.Sql/servers/databases` | SQLSecurityAuditEvents, SQLInsights, Errors, Timeouts, Blocks, Deadlocks |
| Azure Firewall | `Microsoft.Network/azureFirewalls` | AzureFirewallApplicationRule, AzureFirewallNetworkRule, AzureFirewallDnsProxy, AzureFirewallThreatIntel |
| Azure Application Gateway (WAF) | `Microsoft.Network/applicationGateways` | ApplicationGatewayAccessLog, ApplicationGatewayPerformanceLog, ApplicationGatewayFirewallLog |

> Diagnostic settings are created with the name `sentinel-diagnostics`. Existing settings with a different name are not modified. Resources created after deployment are not automatically configured unless **Enable Azure Policy for ongoing enforcement** is also selected.

**Enable Azure Policy for ongoing enforcement** — when ticked alongside any diagnostic resource type, creates a `deployIfNotExists` Azure Policy assignment at subscription scope for each selected type. New resources matching that type are automatically configured with diagnostic settings. Also triggers a remediation task to catch any existing non-compliant resources. Requires Owner on subscription.

---

### Analytics Rules

**Enable Scheduled alert rules** — automatically creates active analytics rules from the templates included in your selected Content Hub solutions.

- Rules are only created for solutions selected in the Content Hub tab
- Rules are filtered to the severity levels you select — High and Medium are selected by default in most tiers; Enterprise also enables Low
- The deployment checks for existing rules before creating new ones — re-running the deployment will not duplicate rules
- Rules will not generate alerts unless the relevant data source is connected and sending data

---

## What is and isn't automated

| Capability | Automated |
|---|---|
| Workspace and Sentinel creation | ✅ |
| Content Hub solution installation | ✅ |
| Analytics rule creation from templates | ✅ |
| Microsoft Entra ID diagnostic settings | ✅ |
| Azure Activity diagnostic settings | ✅ |
| Defender XDR connector (basic) | ✅ |
| Microsoft 365 connector | ✅ |
| Defender for Cloud connector | ✅ |
| Dynamics 365 connector | ✅ |
| Threat Intelligence (MDTI free tier) connector | ✅ Auto-connected after solution install |
| UEBA configuration | ✅ |
| Resource-level diagnostic settings (KV, NSG, Storage, SQL, Firewall, WAF) | ✅ |
| Azure Policy for ongoing diagnostics enforcement | ✅ |
| Defender XDR unified workspace connection | ❌ Manual — must be done in the Defender portal |
| Windows Security Events via AMA | ❌ Manual — requires agent and DCR configuration |
| CEF / Syslog via AMA | ❌ Manual — requires forwarder and DCR configuration |
| Entra ID IDP / Defender for Cloud Apps (if XDR-managed) | ❌ Not supported — configure via Defender portal |
| Azure Firewall / WAF Solution data connection (via ARM connectors) | ❌ Data flows via Diagnostics tab, not a Sentinel connector |

---

## Post-deployment steps

After the deployment completes:

1. **Connect Defender XDR unified workspace** — in the [Microsoft Defender portal](https://security.microsoft.com), go to **Settings > Microsoft Sentinel**, select the newly created workspace, and click **Connect**. This enables the full XDR-Sentinel integration including the advanced hunting experience. This step cannot be automated.

2. **Verify data connector status** — in the Sentinel workspace, go to **Configuration > Data connectors** and confirm the connectors you selected show as Connected.

3. **Review analytics rules** — go to **Configuration > Analytics** and confirm rules are in Active state. Rules that reference data sources not yet connected will show a warning — this is expected until the data source is live.

4. **Configure agent-based connectors if selected** — if you installed the Windows Security Events or CEF solutions, deploy Azure Monitor Agent and configure the relevant Data Collection Rules on your target machines or log forwarders.

---

## Troubleshooting

**"Changes to connector are disabled" / conflict error**
Affects: Microsoft Entra ID Identity Protection, Microsoft Defender for Cloud Apps
Cause: These connectors are managed by the Microsoft Defender XDR portal when XDR is active. Do not select them in the Data Connectors tab — configure them via the Defender portal instead.

**"Polygon precondition failed" on EntityAnalytics / UEBA**
Cause: The Active Directory identity provider was selected for UEBA without Microsoft Defender for Identity deployed. Re-deploy with only Microsoft Entra ID selected, or deselect UEBA entirely if MDI is not in scope.

**UEBA fails with permissions error on a new tenant**
Cause: Microsoft Defender XDR has not been provisioned yet. Visit [security.microsoft.com](https://security.microsoft.com) as a Global Administrator, let the portal fully load, then re-deploy.

**Deployment fails with "ResourceProviderNotRegistered" for Microsoft.ContainerInstance or Microsoft.Storage**
Cause: These resource providers are not registered in the subscription. Run the registration commands in the prerequisites section above before deploying.

**No analytics rules created after deployment**
Cause: Either the Enable Scheduled alert rules checkbox was not ticked, no severity levels were selected, or no Content Hub solutions were selected. Re-deploy with these options configured.

**Threat Intelligence connector shows as not connected**
Cause: The MDTI free connector is auto-connected by the deployment script after the solution installs, but it requires a short wait. If it still shows as disconnected after 10 minutes, check the `deployRules` deployment script logs in the Azure portal under the resource group > Deployments > deployRules > Logs.

**Diagnostic settings not appearing on existing resources**
Cause: The deployment script may have run before the managed identity received its Contributor role assignment. The template includes a sleep period to handle this, but on slow tenants it can still occasionally fail. Re-running the deployment will retry the diagnostic settings script.

**Deployment times out at approximately 1200 seconds ("Action sequencer job exceeded max allowed time")**
Cause: Each deployment script runs in a separate Azure Container Instance which takes 30–60 seconds to start. On a large first-time deployment, cumulative startup time across all containers can approach the ARM 1200-second limit. Re-deploying is faster on subsequent runs as existing rules and settings are detected and skipped.

**Entra ID diagnostic settings fail with an authorization or "category not supported" error**
Affects: the Microsoft Entra ID connector. The deployment enables every available Entra ID log category. Two are conditional:
- `CustomSecurityAttributeAuditLogs` requires the **Attribute Log Administrator** role (in addition to Security Administrator) to route. If the deploying account lacks it, the diagnostic settings resource fails.
- `RiskyAgents` / `AgentRiskEvents` are newer ID Protection for agents categories and may be rejected in tenants that don't have that feature.
Fix: assign the Attribute Log Administrator role and redeploy, or remove the offending category from the `logs` array in `LinkedTemplates/dataConnectors.json` (the `-entraIdDiagnosticSettings` resource) if you don't need it.
