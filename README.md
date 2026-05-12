# secure365-Sentinel-Genesis

Repository for the Microsoft Sentinel solution provided by Softwerx.

![Sentinel Solution](https://github.com/user-attachments/assets/647bda8b-e007-49a7-a2f7-da93e5570126)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fliamsmith-p%2Fsecure365-Sentinel-Genesis%2Fmain%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fliamsmith-p%2Fsecure365-Sentinel-Genesis%2Fmain%2FcreateUiDefinition.json)

---

## Prerequisites

Before clicking Deploy to Azure, ensure the following are in place.

### Required permissions

| Permission | Scope | Required for |
|---|---|---|
| **Owner** | Azure subscription | Creating all resources, subscription-level diagnostic settings, and role assignments used by deployment scripts |
| **Security Administrator** | Entra ID tenant | Configuring M365, Defender XDR, and Threat Intelligence data connectors; enabling UEBA |

> Contributor alone is not sufficient — the deployment creates role assignments which require Owner or User Access Administrator.

### New tenant checklist

If deploying to a **brand new tenant**, complete these steps before deploying or certain features will fail:

1. **Provision Microsoft Defender XDR** — sign in to [security.microsoft.com](https://security.microsoft.com) as a Global Administrator and let the portal fully load. This initialises the XDR workspace. Without this, enabling UEBA will fail with a misleading permissions error even if your permissions are correct.
2. **Verify your Entra ID roles** — confirm your account has Security Administrator assigned in [Entra ID](https://entra.microsoft.com) > Roles and administrators, not just Azure RBAC.

---

## Deployment walkthrough

Click **Deploy to Azure** above and work through each tab.

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

**Enable UEBA** — tick this to enable User Entity Behavior Analytics.

- Only tick this if you have already provisioned Microsoft Defender XDR (see new tenant checklist above)
- Under **Identity Providers**, select **Microsoft Entra ID** for cloud identity sync
- Do **not** select **Active Directory** unless Microsoft Defender for Identity (MDI) is already deployed and onboarded to your tenant — selecting it without MDI will fail with a precondition error

**Enable Sentinel health diagnostics** — optional, enables diagnostic logging for analytics rules, data connectors, and automation rules.

---

### Content Hub Solutions

Select the Microsoft solutions and Essentials packs to install. Each solution deploys analytics rule templates, workbooks, hunting queries, and parsers relevant to that product.

**Microsoft solutions available:**

| Solution | What it covers |
|---|---|
| Microsoft Entra ID | Sign-in and audit log analytics |
| Azure Activity | Subscription-level administrative and security events |
| Microsoft Defender for Cloud | Cloud workload protection alerts |
| Microsoft Defender XDR | Unified XDR incident and alert analytics |
| Microsoft Defender for Cloud Apps | Cloud app security and shadow IT |
| Microsoft 365 | Exchange, SharePoint, and Teams activity |
| Azure Key Vault | Key Vault audit and access analytics |
| Azure Network Security Groups | NSG event and rule counter analytics |
| Azure Storage | Storage account read/write/delete analytics |
| Azure SQL Database | SQL audit, error, and security analytics |
| Threat Intelligence | TI indicator matching rules and workbooks |

**Essentials packs** provide cross-product detection content and are recommended for all deployments.

> Installing a solution only deploys the analytics templates and workbooks — it does not automatically connect data. Data connectors must be configured separately in the Data Connectors tab.

---

### Data Connectors

Configures which data sources are connected to the Sentinel workspace.

#### Sentinel API connectors

These are configured automatically by the deployment:

| Connector | Notes |
|---|---|
| **Microsoft Entra ID** | Configures tenant-level diagnostic settings to forward sign-in, audit, service principal, managed identity, and identity risk logs. Deployed via a tenant-scope nested deployment using your credentials. Requires Global Administrator or Security Administrator. |
| **Azure Activity** | Configures a subscription-level diagnostic setting to forward all activity log categories. Requires Owner on subscription. |
| **Microsoft Defender XDR** | Enables incident and alert sync between XDR and Sentinel. Requires Security Administrator. |
| **Microsoft 365** | Connects Exchange Online, SharePoint, and Teams activity logs. Requires Security Administrator. |
| **Microsoft Defender for Cloud** | Ingests MDfC security alerts. Requires Security Reader on subscription. |
| **Threat Intelligence** | Imports threat indicators for use in analytics rules. |
| **Microsoft Entra ID Identity Protection** ⚠️ | Do **not** select if your tenant uses Microsoft Defender XDR — Identity Protection is managed by the XDR portal and enabling it here will cause a conflict error. Configure via the Defender portal instead. |
| **Microsoft Defender for Cloud Apps** ⚠️ | Do **not** select if your tenant manages Defender for Cloud Apps through the Microsoft Defender XDR portal — it will fail with a conflict error. Configure via the Defender portal instead. |

#### Azure Diagnostics (resource-level)

These configure diagnostic settings on existing resources in your subscription, forwarding logs to the Sentinel workspace. The deployment script scans the entire subscription at deploy time and configures any matching resources it finds.

| Option | Log categories enabled |
|---|---|
| Azure Key Vault | AuditEvent |
| Azure Network Security Groups | NetworkSecurityGroupEvent, NetworkSecurityGroupRuleCounter |
| Azure Storage Accounts | StorageRead, StorageWrite, StorageDelete (blob service) |
| Azure SQL Databases | SQLSecurityAuditEvents, SQLInsights, Errors, Timeouts, Blocks, Deadlocks |

> These settings use the name `sentinel-diagnostics`. Any existing diagnostic settings with a different name are untouched. Resources created after deployment will need diagnostics configured manually or via Azure Policy.

---

### Analytics Rules

**Enable Scheduled alert rules** — tick this to automatically create active analytics rules from the templates included in your selected Content Hub solutions.

- Rules are filtered to the severity levels you select — **High** and **Medium** are selected by default
- Rules are only created for solutions you selected in the Content Hub tab
- Rules will not generate alerts at runtime unless the relevant data connector is also connected and sending data

---

## Post-deployment steps

After the deployment completes, complete these manual steps:

1. **Configure Defender for Cloud Apps and Identity Protection** (if needed) — if you need these connectors, configure them via the **Microsoft Defender XDR portal** under Settings > Microsoft Sentinel, not from Sentinel directly.

3. **Configure diagnostics for future resources** — the deployment only configures diagnostics on resources that exist at deploy time. For resources created afterwards, either re-run the deployment or configure Azure Policy to automate this going forward.

4. **Verify analytics rules** — go to Sentinel > Analytics and confirm rules were created. If none appear, check that you ticked "Enable Scheduled alert rules" and selected at least one severity level during deployment.

---

## Troubleshooting

**"Changes to connector are disabled" / conflict error**
Affects: Microsoft Entra ID Identity Protection, Microsoft Defender for Cloud Apps
Cause: These connectors are managed by the Microsoft Defender XDR portal when XDR is active. Do not select them in the Data Connectors tab.

**"Polygon precondition failed" on EntityAnalytics**
Cause: The Active Directory identity provider was selected for UEBA without Microsoft Defender for Identity deployed. Re-deploy with only Microsoft Entra ID selected as the identity provider.

**UEBA fails with permissions error on new tenant**
Cause: Microsoft Defender XDR has not been provisioned yet. Visit [security.microsoft.com](https://security.microsoft.com), let the portal fully load, then re-deploy.

**No analytics rules created after deployment**
Cause: The "Enable Scheduled alert rules" checkbox was not ticked, or no severity levels were selected. Re-deploy with these options set.

**Deployment fails at diagnostic settings script**
Cause: The managed identity did not receive its subscription Contributor role in time. The template includes a 2-minute sleep to handle this, but on slow tenants it can occasionally still fail. Re-running the deployment resolves it.

**Deployment times out at exactly 1200 seconds ("Action sequencer job exceeded max allowed time")**
Cause: The deployment scripts (solution install, rule creation, diagnostic settings) each run in separate Azure Container Instance containers, and each container takes 30–60 seconds to start. On a large fresh deployment, the cumulative time across all containers can approach or exceed the 1200-second ARM limit. Re-deploying should be faster on subsequent runs as existing rules are skipped.
