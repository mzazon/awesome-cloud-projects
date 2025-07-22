# Infrastructure as Code for Governance Automation with Blueprints and Well-Architected Framework

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Governance Automation with Blueprints and Well-Architected Framework".

## Available Implementations

- **Bicep**: Microsoft's recommended domain-specific language for Azure Resource Manager templates
- **Terraform**: Multi-cloud infrastructure as code using the Azure Resource Manager provider
- **Scripts**: Bash deployment and cleanup scripts for direct Azure CLI deployment

## Prerequisites

- Azure CLI 2.50.0 or later installed and configured
- Azure subscription with Owner or Contributor permissions at the Management Group level
- Understanding of Azure Policy concepts and JSON template syntax
- Familiarity with Azure Resource Manager templates and governance principles
- Knowledge of Azure Well-Architected Framework pillars
- For Terraform: Terraform 1.0+ installed
- For Bicep: Bicep CLI installed (included with Azure CLI 2.20.0+)

## Architecture Overview

This solution implements enterprise-grade governance automation using:

- **Azure Blueprints**: Orchestrates deployment of governance artifacts
- **Azure Policy**: Enforces organizational standards and compliance
- **Azure Resource Manager**: Provides template-based resource deployment
- **Azure Advisor**: Delivers Well-Architected Framework recommendations
- **Azure Monitor**: Tracks governance compliance and policy enforcement

## Quick Start

### Using Bicep

```bash
# Navigate to the bicep directory
cd bicep/

# Deploy the governance infrastructure
az deployment sub create \
    --location eastus \
    --template-file main.bicep \
    --parameters @main.parameters.json

# Verify deployment
az blueprint assignment show \
    --name "enterprise-governance-assignment" \
    --subscription $(az account show --query id --output tsv)
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
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the governance infrastructure
./scripts/deploy.sh

# Verify deployment status
az blueprint assignment list --output table
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export RESOURCE_GROUP="rg-governance-$(openssl rand -hex 3)"
export LOCATION="eastus"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
export BLUEPRINT_NAME="enterprise-governance-blueprint"
export MANAGEMENT_GROUP_ID=$(az account management-group list --query "[0].name" --output tsv)
```

### Bicep Parameters

Customize the deployment by modifying `bicep/main.parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourceGroupName": {
      "value": "rg-governance-demo"
    },
    "location": {
      "value": "eastus"
    },
    "blueprintName": {
      "value": "enterprise-governance-blueprint"
    },
    "logAnalyticsWorkspaceName": {
      "value": "law-governance-workspace"
    },
    "governanceAlertEmail": {
      "value": "governance@company.com"
    }
  }
}
```

### Terraform Variables

Customize the deployment by modifying `terraform/terraform.tfvars`:

```hcl
resource_group_name = "rg-governance-demo"
location = "East US"
blueprint_name = "enterprise-governance-blueprint"
log_analytics_workspace_name = "law-governance-workspace"
governance_alert_email = "governance@company.com"
environment = "production"
cost_center = "IT"
owner = "CloudTeam"
```

## Deployment Details

### Resources Created

The infrastructure deployment creates:

1. **Azure Blueprint Definition**: Enterprise governance blueprint with versioning
2. **Custom Policy Definitions**: Required tagging and security policies
3. **Policy Initiative**: Comprehensive security and governance policy set
4. **Blueprint Assignment**: Applies governance controls to target subscription
5. **Log Analytics Workspace**: Centralized governance monitoring
6. **Action Group**: Automated alerts for governance violations
7. **Azure Monitor Dashboard**: Real-time governance compliance visibility
8. **Role Assignments**: Governance team permissions

### Security Features

- **Encryption**: All storage accounts created with encryption enabled
- **HTTPS Enforcement**: TLS 1.2 minimum for all communications
- **Access Controls**: Role-based access control for governance resources
- **Policy Enforcement**: Automated compliance with security standards
- **Audit Logging**: Comprehensive audit trail for all governance activities

### Cost Optimization

- **Resource Tagging**: Mandatory tags for cost allocation and tracking
- **Advisor Integration**: Automated cost optimization recommendations
- **Monitoring**: Real-time cost and usage visibility
- **Lifecycle Management**: Automated cleanup of unused resources

## Testing and Validation

### Validation Steps

1. **Verify Blueprint Status**:
   ```bash
   az blueprint assignment show \
       --name "enterprise-governance-assignment" \
       --subscription $(az account show --query id --output tsv)
   ```

2. **Test Policy Enforcement**:
   ```bash
   # This should fail due to missing required tags
   az storage account create \
       --name "testnoncomplientstorage$(openssl rand -hex 3)" \
       --resource-group ${RESOURCE_GROUP} \
       --location ${LOCATION} \
       --sku Standard_LRS
   ```

3. **Check Compliance Status**:
   ```bash
   az policy state list \
       --subscription $(az account show --query id --output tsv) \
       --output table
   ```

### Expected Outcomes

- Blueprint assignment shows "Succeeded" status
- Policy enforcement prevents non-compliant resource creation
- Compliance dashboard shows real-time governance metrics
- Advisor provides Well-Architected Framework recommendations
- Monitoring alerts are configured and functional

## Cleanup

### Using Bicep

```bash
# Delete the blueprint assignment
az blueprint assignment delete \
    --name "enterprise-governance-assignment" \
    --subscription $(az account show --query id --output tsv) \
    --yes

# Delete the resource group
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait

# Clean up blueprint definition
az blueprint delete \
    --name ${BLUEPRINT_NAME} \
    --subscription $(az account show --query id --output tsv) \
    --yes
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

1. **Blueprint Assignment Failure**:
   - Verify sufficient permissions at subscription level
   - Check that all policy definitions are valid
   - Ensure resource group exists before assignment

2. **Policy Enforcement Not Working**:
   - Verify policy assignments are active
   - Check policy definition syntax
   - Allow time for policy evaluation (can take up to 30 minutes)

3. **Terraform State Issues**:
   - Initialize Terraform backend if using remote state
   - Verify Azure provider authentication
   - Check resource naming conflicts

### Debugging Commands

```bash
# Check Azure CLI authentication
az account show

# Verify subscription permissions
az role assignment list --assignee $(az account show --query user.name --output tsv)

# Review policy evaluation results
az policy state list --subscription $(az account show --query id --output tsv)

# Check blueprint assignment logs
az blueprint assignment show --name "enterprise-governance-assignment" --subscription $(az account show --query id --output tsv)
```

## Important Notes

> **Warning**: Azure Blueprints is being deprecated on July 11, 2026. Microsoft recommends migrating to Template Specs and Deployment Stacks for future governance automation. This implementation demonstrates current best practices while preparing for the transition.

> **Note**: The governance policies implemented in this solution may prevent certain resource configurations. Review the policy definitions before applying to production environments.

> **Tip**: Use the Azure Policy compliance dashboard to monitor governance effectiveness and identify optimization opportunities across your organization.

## Customization

### Adding Custom Policies

To add custom policy definitions:

1. **Bicep**: Add policy definitions to `bicep/policies/` directory
2. **Terraform**: Add policy resources to `terraform/policies.tf`
3. **Bash**: Add policy creation commands to `scripts/deploy.sh`

### Environment-Specific Configurations

Create separate parameter files for different environments:

- `parameters/dev.parameters.json`
- `parameters/staging.parameters.json`
- `parameters/prod.parameters.json`

### Extending the Blueprint

Add additional artifacts to the blueprint:

1. **ARM Templates**: For standardized resource deployments
2. **Role Assignments**: For environment-specific permissions
3. **Policy Assignments**: For additional compliance requirements

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure Blueprint documentation: https://docs.microsoft.com/en-us/azure/governance/blueprints/
3. Refer to Azure Policy documentation: https://docs.microsoft.com/en-us/azure/governance/policy/
4. Consult the Azure Well-Architected Framework: https://docs.microsoft.com/en-us/azure/architecture/framework/

## Version Information

- **Recipe Version**: 1.0
- **Azure CLI Version**: 2.50.0+
- **Terraform Version**: 1.0+
- **Bicep Version**: 0.15.0+
- **Last Updated**: 2025-07-12

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Please review and adapt for your specific organizational requirements before using in production environments.