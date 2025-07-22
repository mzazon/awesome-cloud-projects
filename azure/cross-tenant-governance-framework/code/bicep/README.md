# Azure Lighthouse and Azure Automanage - Bicep Templates

This directory contains Bicep templates for implementing cross-tenant resource governance using Azure Lighthouse and Azure Automanage.

## Overview

The templates in this directory provide a complete Infrastructure as Code (IaC) solution for:

- **Azure Lighthouse** - Cross-tenant resource delegation and management
- **Azure Automanage** - Automated VM configuration and compliance
- **Azure Monitor** - Centralized monitoring and alerting across tenants
- **Virtual Machine Deployment** - Customer-side VM deployment with governance

## File Structure

```
bicep/
├── main.bicep                      # Main template (monolithic)
├── main-modular.bicep              # Main template (modular approach)
├── customer-vm-deployment.bicep    # Customer VM deployment template
├── parameters.json                 # Example parameters file
├── workbook-template.json          # Azure Workbook configuration
├── modules/
│   ├── lighthouse.bicep            # Lighthouse delegation module
│   ├── monitoring.bicep            # Monitoring and alerting module
│   └── automanage.bicep           # Automanage configuration module
└── README.md                       # This file
```

## Templates Description

### 1. main.bicep
**Purpose**: Monolithic template that deploys all resources in a single file.

**Resources Created**:
- Log Analytics workspace for centralized monitoring
- Automanage configuration profile for VM management
- Action group for alert notifications
- Lighthouse registration definition and assignment
- Data collection rules for VM monitoring
- Scheduled query rules for advanced monitoring
- Azure Workbook for cross-tenant dashboards

### 2. main-modular.bicep
**Purpose**: Modular approach using separate modules for each component.

**Modules Used**:
- `lighthouse.bicep` - Lighthouse delegation setup
- `monitoring.bicep` - Monitoring and alerting infrastructure
- `automanage.bicep` - Automanage configuration profiles

### 3. customer-vm-deployment.bicep
**Purpose**: Template for deploying VMs in customer tenants with Automanage integration.

**Resources Created**:
- Virtual network and subnet
- Network security group with RDP/WinRM rules
- Public IP addresses for VMs
- Network interfaces
- Windows virtual machines
- VM extensions for monitoring
- Automanage profile assignments

### 4. Module Templates

#### lighthouse.bicep
Creates Azure Lighthouse delegation resources:
- Registration definition
- Registration assignment
- Cross-tenant access configuration

#### monitoring.bicep
Sets up monitoring infrastructure:
- Log Analytics workspace
- Data collection rules
- Action groups
- Scheduled query rules for alerting

#### automanage.bicep
Configures Automanage profiles:
- Standard configuration profile
- Best practices profile
- VM management settings

## Prerequisites

- Azure CLI 2.40.0 or later
- Bicep CLI 0.12.0 or later
- Azure PowerShell 8.0.0 or later (optional)
- Appropriate permissions:
  - **MSP Tenant**: Global Administrator or custom role with managed services permissions
  - **Customer Tenant**: Owner or Contributor on target subscription

## Quick Start

### 1. MSP Tenant Deployment

Deploy the main infrastructure in your MSP tenant:

```bash
# Login to MSP tenant
az login --tenant YOUR_MSP_TENANT_ID

# Set subscription
az account set --subscription YOUR_MSP_SUBSCRIPTION_ID

# Create resource group
az group create --name rg-msp-lighthouse-management --location eastus

# Deploy main template
az deployment group create \
  --resource-group rg-msp-lighthouse-management \
  --template-file main.bicep \
  --parameters @parameters.json
```

### 2. Customer Tenant Delegation

Deploy the delegation in customer tenant:

```bash
# Login to customer tenant
az login --tenant CUSTOMER_TENANT_ID

# Set subscription
az account set --subscription CUSTOMER_SUBSCRIPTION_ID

# Deploy delegation at subscription level
az deployment sub create \
  --name lighthouse-delegation \
  --location eastus \
  --template-file main.bicep \
  --parameters @parameters.json
```

### 3. Customer VM Deployment

Deploy VMs in customer tenant with Automanage:

```bash
# Still in customer tenant context
az group create --name rg-customer-workloads --location eastus

# Deploy customer VMs
az deployment group create \
  --resource-group rg-customer-workloads \
  --template-file customer-vm-deployment.bicep \
  --parameters \
    vmNamePrefix=vm-customer \
    vmCount=2 \
    adminPassword='YourSecurePassword123!' \
    automanageProfileResourceId='/subscriptions/MSP_SUB_ID/resourceGroups/rg-msp-lighthouse-management/providers/Microsoft.Automanage/configurationProfiles/automanage-profile-msp' \
    logAnalyticsWorkspaceResourceId='/subscriptions/MSP_SUB_ID/resourceGroups/rg-msp-lighthouse-management/providers/Microsoft.OperationalInsights/workspaces/law-lighthouse-monitoring'
```

## Parameter Configuration

### Required Parameters

Edit `parameters.json` to configure:

```json
{
  "mspTenantId": "12345678-1234-1234-1234-123456789012",
  "authorizations": [
    {
      "principalId": "GUID_OF_MSP_ADMIN_GROUP",
      "principalIdDisplayName": "MSP Administrators",
      "roleDefinitionId": "b24988ac-6180-42a0-ab88-20f7382dd24c"
    }
  ],
  "alertEmailAddress": "ops@msp-company.com"
}
```

### Key Role Definitions

- **Contributor**: `b24988ac-6180-42a0-ab88-20f7382dd24c`
- **Virtual Machine Contributor**: `9980e02c-c2be-4d73-94e8-173b1dc7cf3c`
- **Automanage Contributor**: `cdfd5644-ae35-4c17-bb47-ac720c1b0b59`
- **Monitoring Reader**: `43d0d8ad-25c7-4714-9337-8ba259a9fe05`

## Deployment Scenarios

### Scenario 1: New MSP Setup
Deploy main template in MSP tenant, then delegate customer subscriptions.

### Scenario 2: Existing MSP Infrastructure
Use modular template to add only needed components.

### Scenario 3: Customer Onboarding
Deploy delegation first, then customer VMs with Automanage.

## Advanced Configuration

### Custom Automanage Configuration

Modify the Automanage module to customize:
- Update schedules
- Backup policies
- Security settings
- Monitoring configurations

### Enhanced Monitoring

Add custom alert rules by extending the monitoring module:
- Disk space alerts
- Network connectivity alerts
- Security event alerts
- Performance threshold alerts

### Multi-Region Deployment

Deploy resources across multiple regions:
- Regional Log Analytics workspaces
- Regional Automanage profiles
- Cross-region monitoring dashboards

## Validation and Testing

### Verify Deployment

```bash
# Check Lighthouse delegation
az managedservices assignment list --include-definition

# Verify Automanage profiles
az automanage configuration-profile list

# Test cross-tenant access
az resource list --subscription CUSTOMER_SUBSCRIPTION_ID
```

### Monitor Health

Use the deployed Azure Workbook to monitor:
- VM availability across tenants
- Resource utilization
- Security events
- Compliance status

## Troubleshooting

### Common Issues

1. **Lighthouse Delegation Failed**
   - Verify MSP tenant ID is correct
   - Check authorization principal IDs exist
   - Ensure proper permissions in customer tenant

2. **Automanage Assignment Failed**
   - Verify VM is supported OS version
   - Check Log Analytics workspace permissions
   - Ensure VM agent is installed

3. **Monitoring Data Missing**
   - Verify VM extensions are installed
   - Check Log Analytics workspace connection
   - Validate data collection rules

### Diagnostic Commands

```bash
# Check Lighthouse status
az managedservices assignment show --assignment ASSIGNMENT_ID

# Verify Automanage status
az automanage configuration-profile-assignment show \
  --resource-group RG_NAME \
  --vm-name VM_NAME \
  --configuration-profile-assignment-name default

# Test monitoring agent
az vm extension show \
  --resource-group RG_NAME \
  --vm-name VM_NAME \
  --name MicrosoftMonitoringAgent
```

## Security Considerations

### Best Practices

1. **Least Privilege**: Grant minimal required permissions
2. **Regular Auditing**: Review delegated access regularly
3. **Monitoring**: Enable comprehensive logging and alerting
4. **Compliance**: Ensure configurations meet regulatory requirements

### Security Features

- Network security groups with restricted access
- Encrypted VM disks
- Azure Security Center integration
- Automated security updates
- Compliance monitoring

## Cost Optimization

### Resource Sizing

- Start with smaller VM sizes for testing
- Use Log Analytics workspace caps
- Implement retention policies
- Monitor alert rule costs

### Cost Monitoring

- Tag all resources for cost tracking
- Set up budget alerts
- Review unused resources regularly
- Optimize Automanage configurations

## Support and Maintenance

### Regular Tasks

1. **Monthly**: Review alert rules and thresholds
2. **Quarterly**: Update Automanage configurations
3. **Annually**: Review and renew delegations
4. **As-needed**: Onboard new customer tenants

### Updates and Patching

- Monitor Azure service updates
- Test template changes in development
- Update Bicep CLI regularly
- Review security advisories

## Additional Resources

- [Azure Lighthouse Documentation](https://docs.microsoft.com/azure/lighthouse/)
- [Azure Automanage Documentation](https://docs.microsoft.com/azure/automanage/)
- [Bicep Documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)
- [Azure Monitor Documentation](https://docs.microsoft.com/azure/azure-monitor/)

## License

This template is provided under the MIT License. See the recipe documentation for full license details.