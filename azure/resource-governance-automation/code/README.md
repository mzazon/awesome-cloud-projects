# Infrastructure as Code for Resource Governance Automation with Policy and Resource Graph

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Resource Governance Automation with Policy and Resource Graph".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.30.0 or higher installed and configured
- Azure subscription with Owner or Contributor permissions
- Understanding of Azure Policy concepts and Resource Graph query language (KQL)
- Familiarity with Azure governance and compliance frameworks
- Appropriate permissions for creating and assigning policies at the subscription level

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment sub create \
    --name "tag-governance-deployment" \
    --location "eastus" \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment sub show \
    --name "tag-governance-deployment" \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment status
echo "Deployment complete. Check Azure portal for policy assignments."
```

## Architecture Overview

This solution deploys:

- **Custom Policy Definitions**: Enforce mandatory tagging requirements
- **Policy Initiative**: Groups related policies for comprehensive governance
- **Policy Assignments**: Activates policies at subscription level with remediation
- **Log Analytics Workspace**: Captures policy evaluation logs and compliance data
- **Azure Monitor Integration**: Provides alerts and monitoring for policy violations
- **Compliance Dashboard**: Real-time visibility into tag compliance status
- **Remediation Workflows**: Automated correction of non-compliant resources

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourceGroupName": {
      "value": "rg-governance-demo"
    },
    "location": {
      "value": "eastus"
    },
    "logAnalyticsWorkspaceName": {
      "value": "law-governance"
    },
    "policyInitiativeName": {
      "value": "mandatory-tagging-initiative"
    },
    "excludedResourceTypes": {
      "value": [
        "Microsoft.Network/networkSecurityGroups",
        "Microsoft.Network/routeTables"
      ]
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
resource_group_name = "rg-governance-demo"
location = "eastus"
log_analytics_workspace_name = "law-governance"
policy_initiative_name = "mandatory-tagging-initiative"
excluded_resource_types = [
  "Microsoft.Network/networkSecurityGroups",
  "Microsoft.Network/routeTables"
]
```

### Environment Variables (Bash Scripts)

The bash scripts use these environment variables:

```bash
export RESOURCE_GROUP="rg-governance-demo"
export LOCATION="eastus"
export LOG_ANALYTICS_WORKSPACE="law-governance"
export POLICY_INITIATIVE_NAME="mandatory-tagging-initiative"
export POLICY_ASSIGNMENT_NAME="enforce-mandatory-tags"
```

## Validation and Testing

After deployment, validate the solution:

1. **Check Policy Assignment Status**:
   ```bash
   az policy assignment list \
       --query "[?displayName=='Enforce Mandatory Tags - Subscription Level']" \
       --output table
   ```

2. **Test Tag Enforcement**:
   ```bash
   # This should fail due to missing tags
   az storage account create \
       --name "testsa$(openssl rand -hex 3)" \
       --resource-group ${RESOURCE_GROUP} \
       --location ${LOCATION} \
       --sku Standard_LRS
   
   # This should succeed with required tags
   az storage account create \
       --name "testsa$(openssl rand -hex 3)" \
       --resource-group ${RESOURCE_GROUP} \
       --location ${LOCATION} \
       --sku Standard_LRS \
       --tags Department=IT Environment=Demo
   ```

3. **Query Compliance Status**:
   ```bash
   az graph query -q "
   Resources
   | where type !in ('microsoft.resources/subscriptions', 'microsoft.resources/resourcegroups')
   | extend compliance = case(
       tags.Department != '' and isnotempty(tags.Department) and 
       tags.Environment != '' and isnotempty(tags.Environment), 'Fully Compliant',
       'Non-Compliant'
   )
   | summarize count() by compliance
   " --output table
   ```

## Cost Considerations

Estimated monthly costs:
- **Log Analytics Workspace**: $5-10 (depends on log volume)
- **Azure Monitor Alerts**: $1-2 per alert rule
- **Policy Evaluation**: No additional cost
- **Dashboard**: No additional cost

Total estimated cost: $5-15 per month

## Cleanup

### Using Bicep

```bash
# Delete the deployment
az deployment sub delete \
    --name "tag-governance-deployment"

# Clean up resource group
az group delete \
    --name "rg-governance-demo" \
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
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Policy Assignment Fails**:
   - Ensure you have sufficient permissions (Owner or Contributor)
   - Check if there are conflicting policy assignments
   - Verify the policy definition exists

2. **Resources Not Being Tagged**:
   - Check policy enforcement mode is set to "Default"
   - Verify remediation tasks are running
   - Check if resources are in excluded resource types

3. **Dashboard Not Showing Data**:
   - Ensure Log Analytics workspace is properly configured
   - Check diagnostic settings are enabled
   - Verify data is flowing to the workspace

### Debugging Commands

```bash
# Check policy compliance state
az policy state list \
    --policy-assignment "enforce-mandatory-tags" \
    --query "[].{resourceId:resourceId, complianceState:complianceState}" \
    --output table

# Check remediation task status
az policy remediation list \
    --policy-assignment "enforce-mandatory-tags" \
    --output table

# Query policy evaluation logs
az monitor log-analytics query \
    --workspace "law-governance" \
    --analytics-query "PolicyInsights | where TimeGenerated > ago(1h) | project TimeGenerated, ComplianceState, ResourceId"
```

## Security Considerations

This solution implements several security best practices:

- **Least Privilege**: Remediation tasks use minimal required permissions
- **Audit Trail**: All policy evaluations are logged for compliance
- **Encryption**: Log Analytics workspace data is encrypted at rest
- **Network Security**: No public endpoints exposed
- **Tag Inheritance**: Automatic tag propagation from resource groups

## Extending the Solution

Consider these enhancements:

1. **Multi-Subscription Governance**: Deploy at management group level
2. **Custom Tag Automation**: Add Azure Functions for dynamic tagging
3. **Cost Management Integration**: Connect with Azure Cost Management APIs
4. **Advanced Reporting**: Create Power BI dashboards for executive reporting
5. **Compliance Automation**: Integrate with Azure Security Center

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure Policy documentation: https://learn.microsoft.com/en-us/azure/governance/policy/
3. Consult Azure Resource Graph documentation: https://learn.microsoft.com/en-us/azure/governance/resource-graph/
4. Review Azure governance best practices: https://learn.microsoft.com/en-us/azure/governance/

## Version Information

- **Recipe Version**: 1.0
- **Azure CLI Version**: 2.30.0+
- **Terraform Version**: 1.0+
- **Bicep Version**: 0.15.0+

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Customize according to your organization's requirements and compliance standards.