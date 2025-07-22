# Infrastructure as Code for Cross-Tenant Governance Framework with Lighthouse and Automanage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cross-Tenant Governance Framework with Lighthouse and Automanage".

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code using official Azure provider
- **Scripts**: Bash deployment and cleanup scripts for automated provisioning

## Prerequisites

- Azure CLI v2.30.0 or later installed and configured
- PowerShell 5.1 or later (for ARM template deployment)
- Appropriate permissions:
  - Global Administrator permissions for MSP tenant
  - Owner or Contributor permissions on customer tenant subscriptions
- Basic understanding of Azure Resource Manager templates and RBAC
- Estimated cost: $50-100 per month for monitoring and automation resources

## Quick Start

### Using Bicep

```bash
# Deploy the main infrastructure
az deployment sub create \
    --location eastus \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json

# Verify deployment
az deployment sub show \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan

# Apply the configuration
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment status
az managedservices assignment list --include-definition --output table
```

## Configuration

### Environment Variables

Before deployment, set the following environment variables:

```bash
# MSP tenant configuration
export MSP_TENANT_ID="your-msp-tenant-id"
export MSP_SUBSCRIPTION_ID="your-msp-subscription-id"
export MSP_RESOURCE_GROUP="rg-msp-lighthouse-management"

# Customer tenant configuration
export CUSTOMER_TENANT_ID="customer-tenant-id"
export CUSTOMER_SUBSCRIPTION_ID="customer-subscription-id"
export CUSTOMER_RESOURCE_GROUP="rg-customer-workloads"

# Deployment settings
export LOCATION="eastus"
export RANDOM_SUFFIX=$(openssl rand -hex 3)
```

### Bicep Parameters

Customize the deployment by modifying `bicep/parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "mspTenantId": {
      "value": "your-msp-tenant-id"
    },
    "customerTenantId": {
      "value": "customer-tenant-id"
    },
    "location": {
      "value": "eastus"
    },
    "resourcePrefix": {
      "value": "lighthouse"
    }
  }
}
```

### Terraform Variables

Customize the deployment by modifying `terraform/terraform.tfvars`:

```hcl
msp_tenant_id         = "your-msp-tenant-id"
customer_tenant_id    = "customer-tenant-id"
location              = "eastus"
resource_prefix       = "lighthouse"
enable_monitoring     = true
enable_automanage     = true
```

## Deployment Process

### Phase 1: MSP Tenant Setup

1. **Log in to MSP tenant**:
   ```bash
   az login --tenant ${MSP_TENANT_ID}
   az account set --subscription ${MSP_SUBSCRIPTION_ID}
   ```

2. **Create management resources**:
   - Resource group for MSP management
   - Log Analytics workspace for centralized monitoring
   - Azure Monitor action groups for alerting
   - Automanage configuration profile

### Phase 2: Customer Tenant Delegation

1. **Deploy Lighthouse delegation**:
   - Create registration definition in customer tenant
   - Establish delegation relationship
   - Configure RBAC permissions for MSP team

2. **Verify cross-tenant access**:
   ```bash
   az managedservices assignment list --include-definition --output table
   ```

### Phase 3: VM Deployment and Automanage

1. **Deploy customer VMs**:
   - Create virtual network and subnets
   - Deploy Windows Server virtual machines
   - Configure network security groups

2. **Enable Automanage**:
   - Apply configuration profile to VMs
   - Enable automated patching and monitoring
   - Verify compliance status

### Phase 4: Monitoring and Governance

1. **Configure monitoring**:
   - Set up cross-tenant alerting
   - Create Azure Workbooks for reporting
   - Enable centralized logging

2. **Validate governance**:
   - Test cross-tenant resource access
   - Verify Automanage configuration
   - Confirm monitoring and alerting

## Validation

### Verify Lighthouse Delegation

```bash
# Check delegation status
az managedservices assignment list \
    --include-definition \
    --query "[].{Name:name, Status:properties.provisioningState}" \
    --output table

# Test cross-tenant access
az resource list \
    --subscription ${CUSTOMER_SUBSCRIPTION_ID} \
    --resource-type "Microsoft.Compute/virtualMachines" \
    --output table
```

### Verify Automanage Configuration

```bash
# Check Automanage assignments
az automanage configuration-profile-assignment list \
    --resource-group ${CUSTOMER_RESOURCE_GROUP} \
    --subscription ${CUSTOMER_SUBSCRIPTION_ID} \
    --output table

# Verify compliance status
az automanage configuration-profile-assignment show \
    --resource-group ${CUSTOMER_RESOURCE_GROUP} \
    --vm-name ${VM_NAME} \
    --configuration-profile-assignment-name "default" \
    --subscription ${CUSTOMER_SUBSCRIPTION_ID} \
    --query "properties.status"
```

### Verify Monitoring

```bash
# Query Log Analytics for cross-tenant data
az monitor log-analytics query \
    --workspace ${LOG_ANALYTICS_WORKSPACE} \
    --analytics-query "Heartbeat | where TimeGenerated > ago(1h) | summarize count() by Computer" \
    --output table

# Check alert rule status
az monitor metrics alert show \
    --resource-group ${MSP_RESOURCE_GROUP} \
    --name ${ALERT_RULE_NAME} \
    --query "enabled"
```

## Cleanup

### Using Bicep

```bash
# Remove delegation assignment
az managedservices assignment delete \
    --assignment $(az managedservices assignment list \
        --query "[0].name" --output tsv) \
    --subscription ${CUSTOMER_SUBSCRIPTION_ID}

# Delete resource groups
az group delete --name ${MSP_RESOURCE_GROUP} --yes --no-wait
az group delete --name ${CUSTOMER_RESOURCE_GROUP} --yes --no-wait
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

1. **Delegation Failed**:
   - Verify MSP tenant permissions
   - Check customer tenant consent
   - Validate ARM template syntax

2. **Automanage Assignment Failed**:
   - Ensure VM is in supported region
   - Verify configuration profile exists
   - Check RBAC permissions

3. **Cross-Tenant Access Denied**:
   - Verify delegation status
   - Check role assignments
   - Validate tenant IDs

### Debug Commands

```bash
# Check delegation details
az managedservices definition list --output table

# Verify resource access
az resource list --subscription ${CUSTOMER_SUBSCRIPTION_ID} --output table

# Check Automanage status
az automanage configuration-profile-assignment list \
    --resource-group ${CUSTOMER_RESOURCE_GROUP} \
    --subscription ${CUSTOMER_SUBSCRIPTION_ID}
```

## Security Considerations

- **Least Privilege**: MSP permissions follow principle of least privilege
- **Audit Logging**: All cross-tenant activities are logged in Azure Activity Log
- **Revocable Access**: Customers can revoke delegation at any time
- **Encrypted Communication**: All data in transit is encrypted using TLS 1.2+
- **Compliance**: Solution supports SOC 2, ISO 27001, and other compliance frameworks

## Cost Optimization

- **Resource Sizing**: VMs use appropriate sizes (Standard_B2s for testing)
- **Monitoring Costs**: Log Analytics workspace uses pay-as-you-go pricing
- **Automanage Pricing**: No additional cost for Automanage service
- **Cross-Tenant Monitoring**: Centralized monitoring reduces per-tenant costs

## Best Practices

1. **Multi-Tenant Governance**:
   - Use consistent naming conventions across tenants
   - Implement standardized tagging policies
   - Establish clear escalation procedures

2. **Security Management**:
   - Regularly review delegation permissions
   - Monitor for unauthorized access attempts
   - Implement just-in-time access where possible

3. **Operational Excellence**:
   - Automate routine management tasks
   - Implement comprehensive monitoring
   - Establish incident response procedures

4. **Performance Optimization**:
   - Use Azure regions closest to customers
   - Implement resource scaling policies
   - Monitor and optimize resource utilization

## Extensions

### Azure Policy Integration

```bash
# Deploy policy definitions through Lighthouse
az policy definition create \
    --name "lighthouse-tagging-policy" \
    --rules @policy-rules.json \
    --subscription ${CUSTOMER_SUBSCRIPTION_ID}
```

### Azure Sentinel Integration

```bash
# Connect to centralized SIEM
az sentinel workspace create \
    --resource-group ${MSP_RESOURCE_GROUP} \
    --workspace-name "lighthouse-sentinel" \
    --location ${LOCATION}
```

### Cost Management

```bash
# Set up cost alerts
az consumption budget create \
    --resource-group ${CUSTOMER_RESOURCE_GROUP} \
    --budget-name "customer-monthly-budget" \
    --amount 1000 \
    --subscription ${CUSTOMER_SUBSCRIPTION_ID}
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for detailed implementation steps
2. **Azure Documentation**: 
   - [Azure Lighthouse Documentation](https://docs.microsoft.com/en-us/azure/lighthouse/)
   - [Azure Automanage Documentation](https://docs.microsoft.com/en-us/azure/automanage/)
3. **Provider Documentation**: Consult Azure Resource Manager, Bicep, and Terraform documentation
4. **Community Support**: Azure community forums and Stack Overflow

## Additional Resources

- [Azure Lighthouse Architecture Guide](https://docs.microsoft.com/en-us/azure/lighthouse/concepts/architecture)
- [Azure Automanage Best Practices](https://docs.microsoft.com/en-us/azure/automanage/automanage-best-practices)
- [Azure Monitor Cross-Tenant Guidance](https://docs.microsoft.com/en-us/azure/lighthouse/how-to/monitor-at-scale)
- [Azure Governance Documentation](https://docs.microsoft.com/en-us/azure/governance/)