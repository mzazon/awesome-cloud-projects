# Infrastructure as Code for Immutable Audit Trails with Blockchain Technology

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Immutable Audit Trails with Blockchain Technology".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.50.0 or later)
- Azure subscription with Owner or Contributor permissions
- Basic understanding of blockchain concepts and audit logging requirements
- Familiarity with Azure Logic Apps workflow design
- Estimated cost: ~$150-200/month for moderate usage (10,000 transactions/day)

> **Note**: Azure Confidential Ledger requires a minimum of 3 nodes for consensus, which contributes to the base cost regardless of transaction volume.

## Architecture Overview

The solution deploys:
- **Azure Confidential Ledger**: Blockchain-based immutable audit trail storage
- **Azure Logic Apps**: Automated event capture and workflow orchestration  
- **Azure Key Vault**: Secure credential and certificate management
- **Azure Event Hub**: High-volume event ingestion and streaming
- **Azure Storage Account**: Long-term audit archive with immutable policies
- **RBAC Configuration**: Least privilege access controls

## Quick Start

### Using Bicep (Recommended)
```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-audit-trail \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json

# Monitor deployment status
az deployment group show \
    --resource-group rg-audit-trail \
    --name main \
    --query properties.provisioningState
```

### Using Terraform
```bash
# Initialize Terraform
cd terraform/
terraform init

# Review deployment plan
terraform plan

# Deploy infrastructure
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
az group show --name rg-audit-trail --query properties.provisioningState
```

## Configuration Parameters

### Bicep Parameters
Edit `bicep/parameters.json` to customize:
- `location`: Azure region for deployment (default: eastus)
- `environment`: Environment tag (default: demo)
- `ledgerType`: Confidential Ledger type (Public/Private)
- `eventHubCapacity`: Event Hub throughput units
- `storageSkuName`: Storage account SKU

### Terraform Variables
Edit `terraform/terraform.tfvars` to customize:
- `resource_group_name`: Name of the resource group
- `location`: Azure region for deployment
- `environment`: Environment designation
- `ledger_type`: Confidential Ledger configuration
- `event_hub_partition_count`: Event Hub partitions

### Script Environment Variables
The bash scripts use these environment variables:
- `RESOURCE_GROUP`: Target resource group name
- `LOCATION`: Azure region
- `ENVIRONMENT`: Environment tag
- `LEDGER_TYPE`: Confidential Ledger type

## Post-Deployment Configuration

### 1. Logic App Workflow Setup
After infrastructure deployment, configure the Logic App workflow:

```bash
# Get Logic App details
LOGIC_APP_NAME=$(az logic workflow list \
    --resource-group rg-audit-trail \
    --query "[0].name" --output tsv)

# Configure Event Hub trigger and Confidential Ledger actions
# (This requires manual configuration in the Azure portal)
```

### 2. Event Hub Connection
Configure event sources to send audit events:

```bash
# Get Event Hub connection string
az eventhubs namespace authorization-rule keys list \
    --resource-group rg-audit-trail \
    --namespace-name <event-hub-namespace> \
    --name RootManageSharedAccessKey \
    --query primaryConnectionString --output tsv
```

### 3. Test Audit Entry
Validate the system with a test audit entry:

```bash
# Create test audit entry
AUDIT_ENTRY='{
  "eventType": "SystemConfiguration",
  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
  "actor": "admin@company.com",
  "action": "CreateAuditTrailSystem",
  "resource": "AzureConfidentialLedger",
  "result": "Success",
  "details": "Initial audit trail system deployment"
}'

# Send to Event Hub (requires additional configuration)
```

## Validation & Testing

### Infrastructure Validation
```bash
# Check Confidential Ledger status
az confidentialledger show \
    --name <ledger-name> \
    --resource-group rg-audit-trail \
    --query "{Name:name, State:properties.provisioningState}"

# Verify Key Vault access
az keyvault secret list \
    --vault-name <keyvault-name> \
    --query "[].name"

# Test Event Hub connectivity
az eventhubs eventhub show \
    --name audit-events \
    --namespace-name <event-hub-namespace> \
    --resource-group rg-audit-trail
```

### Security Validation
```bash
# Check RBAC assignments
az role assignment list \
    --resource-group rg-audit-trail \
    --output table

# Verify Key Vault access policies
az keyvault show \
    --name <keyvault-name> \
    --resource-group rg-audit-trail \
    --query properties.accessPolicies
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group and all resources
az group delete \
    --name rg-audit-trail \
    --yes \
    --no-wait

# Verify deletion
az group exists --name rg-audit-trail
```

### Using Terraform
```bash
cd terraform/
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
az group exists --name rg-audit-trail
```

## Security Considerations

### Key Vault Configuration
- Soft delete and purge protection enabled
- Access policies configured for least privilege
- Audit logging enabled for all operations
- 90-day retention period for compliance

### Confidential Ledger Security
- Hardware-backed secure enclaves (Intel SGX)
- Cryptographic verification of all transactions
- Immutable blockchain storage
- Public ledger type for audit transparency

### Network Security
- Event Hub with managed identity authentication
- Storage account with hierarchical namespace
- Logic Apps with system-assigned managed identity
- RBAC-based access control throughout

## Cost Optimization

### Estimated Monthly Costs (10,000 transactions/day)
- Azure Confidential Ledger: ~$120-150
- Logic Apps: ~$10-15
- Event Hub Standard: ~$20-25
- Key Vault: ~$2-3
- Storage Account: ~$5-10

### Cost Reduction Strategies
1. **Archive Policy**: Move old audit data to cheaper storage tiers
2. **Event Hub Scaling**: Adjust throughput units based on actual usage
3. **Logic Apps Optimization**: Use consumption plan for variable workloads
4. **Storage Lifecycle**: Implement automated archiving policies

## Troubleshooting

### Common Issues

1. **Confidential Ledger Deployment Timeout**
   - Deployment can take 5-10 minutes
   - Check deployment status with `az deployment group show`
   - Verify subscription quotas for Confidential Ledger

2. **Logic Apps Authentication Errors**
   - Ensure managed identity is properly configured
   - Verify RBAC assignments are complete
   - Check Key Vault access policies

3. **Event Hub Connection Issues**
   - Validate connection string format
   - Check Event Hub namespace status
   - Verify consumer group configuration

### Diagnostic Commands
```bash
# Check deployment status
az deployment group list \
    --resource-group rg-audit-trail \
    --query "[].{Name:name, State:properties.provisioningState}"

# Review activity logs
az monitor activity-log list \
    --resource-group rg-audit-trail \
    --max-events 50

# Validate resource health
az resource list \
    --resource-group rg-audit-trail \
    --query "[].{Name:name, Type:type, Status:properties.provisioningState}"
```

## Integration Examples

### Connecting Business Applications
```bash
# Example: Send audit event from application
curl -X POST \
  https://<event-hub-namespace>.servicebus.windows.net/audit-events/messages \
  -H "Authorization: SharedAccessSignature sr=..." \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "UserLogin",
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "actor": "user@company.com",
    "action": "Login",
    "resource": "WebApplication",
    "result": "Success"
  }'
```

### Audit Trail Verification
```bash
# Retrieve audit receipts for verification
# (Requires custom application using Confidential Ledger SDK)
```

## Extensions and Enhancements

### Additional Features to Consider
1. **Multi-region Deployment**: Replicate across Azure regions
2. **Advanced Analytics**: Integrate with Azure Synapse Analytics
3. **Compliance Reporting**: Automated SOC 2 and ISO 27001 reports
4. **Real-time Monitoring**: Azure Monitor dashboards and alerts
5. **Batch Processing**: Optimize for high-volume scenarios

### Integration Opportunities
- Azure Sentinel for security analytics
- Power BI for audit visualization
- Azure Cognitive Services for event classification
- Microsoft Defender for threat detection

## Support and Documentation

### Azure Documentation
- [Azure Confidential Ledger](https://docs.microsoft.com/en-us/azure/confidential-ledger/overview)
- [Azure Logic Apps](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Azure Event Hubs](https://docs.microsoft.com/en-us/azure/event-hubs/)
- [Azure Key Vault](https://docs.microsoft.com/en-us/azure/key-vault/)

### Best Practices
- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)
- [Azure Security Baseline](https://docs.microsoft.com/en-us/security/benchmark/azure/)
- [Logic Apps Security](https://docs.microsoft.com/en-us/azure/logic-apps/logic-apps-securing-a-logic-app)

For issues with this infrastructure code, refer to the original recipe documentation or the Azure provider's documentation.