# Infrastructure as Code for AI Agent Governance Framework with Entra Agent ID and Logic Apps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI Agent Governance Framework with Entra Agent ID and Logic Apps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with Global Administrator or Security Administrator permissions
- PowerShell 7.0+ or Bash shell
- Appropriate permissions for resource creation including:
  - Resource Group creation
  - Logic Apps deployment
  - Azure Monitor workspace creation
  - Key Vault creation and management
  - Azure Entra permissions for agent identity management

## Quick Start

### Using Bicep (Recommended)

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription <your-subscription-id>

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-ai-governance \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters environmentName=production
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure deployment creates the following Azure resources:

- **Resource Group**: Container for all governance resources
- **Log Analytics Workspace**: Centralized logging for AI agent activities
- **Key Vault**: Secure storage for governance credentials and secrets
- **Logic Apps**: Automated workflows for agent lifecycle management
  - Agent Discovery and Registration
  - Compliance Monitoring
  - Access Control Automation
  - Audit and Reporting
  - Performance Monitoring
- **Azure Monitor**: Performance and health monitoring integration
- **Storage Account**: Report storage and audit trail persistence

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for resource deployment | `eastus` | Yes |
| `environmentName` | Environment identifier (dev/staging/prod) | `production` | Yes |
| `logAnalyticsRetentionDays` | Log retention period in days | `90` | No |
| `keyVaultRetentionDays` | Key Vault soft-delete retention | `90` | No |
| `enableMonitoring` | Enable Azure Monitor integration | `true` | No |

### Terraform Variables

```hcl
# terraform.tfvars example
location = "eastus"
environment_name = "production"
log_analytics_retention_days = 90
key_vault_retention_days = 90
enable_monitoring = true
```

## Deployment Process

### Pre-Deployment Checklist

1. **Azure Subscription**: Ensure you have appropriate permissions
2. **Entra Agent ID Preview**: Verify preview features are enabled
3. **Resource Quotas**: Check subscription limits for Logic Apps and Log Analytics
4. **Cost Estimation**: Review estimated monthly costs ($50-100 for monitoring infrastructure)

### Step-by-Step Deployment

1. **Clone and Navigate**:
   ```bash
   git clone <repository-url>
   cd azure/implementing-autonomous-ai-agent-governance-with-azure-entra-agent-id-and-logic-apps/code/
   ```

2. **Choose Deployment Method**:
   - **Bicep**: Best for Azure-native deployments
   - **Terraform**: Good for multi-cloud or existing Terraform workflows
   - **Bash Scripts**: Manual deployment with full control

3. **Configure Parameters**:
   ```bash
   # For Bicep
   cp bicep/parameters.example.json bicep/parameters.json
   # Edit parameters.json with your values
   
   # For Terraform
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

4. **Deploy Infrastructure**:
   ```bash
   # Bicep deployment
   az deployment group create \
       --resource-group rg-ai-governance \
       --template-file bicep/main.bicep \
       --parameters @bicep/parameters.json
   
   # Terraform deployment
   cd terraform/
   terraform init
   terraform apply
   
   # Bash script deployment
   ./scripts/deploy.sh
   ```

5. **Verify Deployment**:
   ```bash
   # Check resource group contents
   az resource list \
       --resource-group rg-ai-governance \
       --output table
   
   # Verify Logic Apps are running
   az logic workflow list \
       --resource-group rg-ai-governance \
       --query "[].{Name:name,State:state}" \
       --output table
   ```

## Post-Deployment Configuration

### Enable Agent Identity Discovery

```bash
# Register for Entra Agent ID preview (if not already done)
az feature register \
    --namespace Microsoft.EntraAgentID \
    --name AgentIdentityPreview

# Check registration status
az feature show \
    --namespace Microsoft.EntraAgentID \
    --name AgentIdentityPreview
```

### Configure Logic Apps Triggers

```bash
# Get Logic App callback URLs for webhook configuration
az logic workflow show \
    --resource-group rg-ai-governance \
    --name la-compliance-monitor \
    --query "accessEndpoint" \
    --output tsv
```

### Set Up Monitoring Alerts

```bash
# Create action group for notifications
az monitor action-group create \
    --resource-group rg-ai-governance \
    --name ag-ai-governance-alerts \
    --short-name aigovern \
    --action email admin your-email@domain.com
```

## Validation and Testing

### Verify Agent Discovery

```bash
# Check that agents are discoverable
az ad app list \
    --filter "applicationtype eq 'AgentID'" \
    --query "[].{Name:displayName,ID:appId}" \
    --output table
```

### Test Compliance Workflows

```bash
# Trigger compliance check manually
COMPLIANCE_URL=$(az logic workflow show \
    --resource-group rg-ai-governance \
    --name la-compliance-monitor \
    --query "accessEndpoint" \
    --output tsv)

curl -X POST "${COMPLIANCE_URL}" \
    -H "Content-Type: application/json" \
    -d '{
      "objectId": "test-agent-id",
      "eventType": "permissionChange",
      "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'"
    }'
```

### Validate Logging

```bash
# Query Log Analytics for governance events
az monitor log-analytics query \
    --workspace "law-aigovernance" \
    --analytics-query "
        AuditLogs_CL 
        | where TimeGenerated > ago(1h) 
        | where Message_s contains 'Agent' 
        | order by TimeGenerated desc
    " \
    --output table
```

## Monitoring and Maintenance

### Dashboard Access

- **Azure Portal**: Navigate to Resource Group → Logic Apps for workflow monitoring
- **Log Analytics**: Access centralized logging and query interface
- **Azure Monitor**: View performance metrics and health status

### Regular Maintenance Tasks

1. **Weekly**: Review agent compliance reports
2. **Monthly**: Analyze agent permission changes and access patterns
3. **Quarterly**: Update governance policies and Logic App workflows
4. **Annually**: Review and update security configurations

### Troubleshooting

#### Common Issues

1. **Logic Apps Not Triggering**:
   ```bash
   # Check Logic App run history
   az logic workflow run list \
       --resource-group rg-ai-governance \
       --name la-ai-governance \
       --query "[].{Status:status,StartTime:startTime}" \
       --output table
   ```

2. **Agent Discovery Issues**:
   ```bash
   # Verify Entra Agent ID feature registration
   az feature show \
       --namespace Microsoft.EntraAgentID \
       --name AgentIdentityPreview
   ```

3. **Log Analytics Connection**:
   ```bash
   # Test workspace connectivity
   az monitor log-analytics workspace show \
       --resource-group rg-ai-governance \
       --workspace-name law-aigovernance
   ```

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-ai-governance \
    --yes \
    --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify resource group deletion
az group exists --name rg-ai-governance

# Check for any remaining resources
az resource list \
    --query "[?resourceGroup=='rg-ai-governance']" \
    --output table
```

## Cost Optimization

### Resource Sizing Recommendations

- **Logic Apps**: Use Consumption pricing for variable workloads
- **Log Analytics**: Set appropriate retention periods (30-90 days)
- **Storage**: Use Standard tier for audit logs and reports
- **Key Vault**: Standard tier sufficient for most governance scenarios

### Cost Monitoring

```bash
# Set up budget alerts for the resource group
az consumption budget create \
    --resource-group rg-ai-governance \
    --budget-name ai-governance-budget \
    --amount 100 \
    --time-grain Monthly
```

## Security Considerations

### Access Control

- Logic Apps use managed identities for Azure resource access
- Key Vault implements role-based access control (RBAC)
- Log Analytics workspace access follows least privilege principles

### Data Protection

- All data transmission uses HTTPS/TLS encryption
- Audit logs are retained according to compliance requirements
- Sensitive information is stored in Key Vault with appropriate access policies

### Compliance Features

- Audit trail generation for all agent governance activities
- Automated compliance reporting with customizable policies
- Integration with Azure Policy for governance enforcement

## Advanced Configuration

### Multi-Tenant Setup

For organizations with multiple Azure AD tenants:

```bash
# Configure cross-tenant agent discovery
az ad app permission admin-consent \
    --id <logic-app-managed-identity> \
    --api-permissions Directory.Read.All
```

### Custom Compliance Policies

Extend the Logic Apps with custom compliance rules:

```json
{
  "complianceRules": {
    "maxPermissions": 10,
    "allowedResourceTypes": ["Microsoft.CognitiveServices", "Microsoft.MachineLearningServices"],
    "requiredTags": ["environment", "owner", "purpose"]
  }
}
```

## Support and Documentation

- **Azure Documentation**: [Azure Entra Agent ID](https://docs.microsoft.com/en-us/entra/identity/agents/)
- **Logic Apps**: [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- **Monitoring**: [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)

For issues with this infrastructure code, refer to the original recipe documentation or Azure support resources.

## Contributing

To contribute improvements to this infrastructure code:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This infrastructure code is provided under the same license as the parent recipe collection.