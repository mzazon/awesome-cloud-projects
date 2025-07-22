# Infrastructure as Code for Self-Service Developer Infrastructure with Dev Box and Deployment Environments

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Self-Service Developer Infrastructure with Dev Box and Deployment Environments".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (Bicep)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.55.0 or later installed and configured
- Azure subscription with Owner or Contributor role permissions
- Azure AD with appropriate user licenses for Dev Box (Microsoft 365 E3/E5 or Windows 365)
- Basic knowledge of Azure resource management and identity concepts
- Appropriate permissions for resource creation including DevCenter resources

## Quick Start

### Using Bicep
```bash
cd bicep/

# Create resource group
az group create --name rg-devinfra-demo --location eastus

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-devinfra-demo \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure creates a comprehensive self-service developer platform that includes:

- **Azure DevCenter**: Central management plane for developer infrastructure
- **Dev Box Pools**: Collections of pre-configured cloud-based development workstations
- **Azure Deployment Environments**: On-demand infrastructure provisioning for development projects
- **Network Configuration**: Secure virtual network connectivity for Dev Boxes
- **Identity & Access Management**: Role-based access control for developer self-service

## Key Components

### Azure DevCenter
- Centralized governance and management for developer resources
- Integration with Azure AD for authentication and authorization
- Catalog management for environment templates
- Policy enforcement and compliance

### Dev Box Infrastructure
- High-performance cloud-based development workstations
- Pre-configured with Visual Studio and development tools
- Auto-stop scheduling for cost optimization
- Network isolation and security policies

### Deployment Environments
- Infrastructure-as-Code templates for common development scenarios
- Self-service provisioning of development, staging, and testing environments
- Integration with Git repositories for custom templates
- Automated lifecycle management

## Configuration Options

### Bicep Parameters
The Bicep implementation supports customization through parameters:

- `location`: Azure region for resource deployment
- `resourceGroupName`: Name of the resource group
- `devCenterName`: Name of the DevCenter instance
- `projectName`: Name of the development project
- `environmentTypes`: Array of environment types to create

### Terraform Variables
The Terraform implementation includes these configurable variables:

- `location`: Azure region for deployment
- `resource_group_name`: Resource group name
- `dev_center_name`: DevCenter instance name
- `project_name`: Development project name
- `dev_box_definition_name`: Name for the Dev Box definition
- `network_address_space`: Virtual network address space

### Environment Variables
Both implementations support environment variable configuration:

```bash
export AZURE_LOCATION="eastus"
export RESOURCE_GROUP_NAME="rg-devinfra-demo"
export DEVCENTER_NAME="dc-selfservice-demo"
export PROJECT_NAME="proj-webapp-team"
```

## Security Considerations

### Identity and Access Management
- DevCenter uses system-assigned managed identity
- Role-based access control for developer permissions
- Least-privilege access principles
- Integration with Azure AD for authentication

### Network Security
- Virtual network isolation for Dev Boxes
- Private connectivity to corporate resources
- Network security groups for traffic control
- Azure AD Join for device management

### Data Protection
- Encryption at rest for all storage
- Secure configuration management
- Compliance with organizational policies
- Audit logging for all operations

## Cost Optimization

### Dev Box Cost Management
- Auto-stop schedules to prevent idle charges
- Right-sizing guidance for compute resources
- Usage monitoring and reporting
- Resource lifecycle management

### Deployment Environments
- Consumption-based pricing model
- Automatic resource cleanup policies
- Cost allocation by project and team
- Budget alerts and monitoring

## Monitoring and Maintenance

### Health Monitoring
- Azure Monitor integration for resource health
- Application insights for usage analytics
- Log analytics for troubleshooting
- Performance monitoring dashboards

### Lifecycle Management
- Automated patching and updates
- Version control for environment templates
- Backup and disaster recovery
- Capacity planning and scaling

## Cleanup

### Using Bicep
```bash
# Delete the resource group and all resources
az group delete --name rg-devinfra-demo --yes --no-wait
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

## Customization

### Adding Custom Environment Templates
1. Create your Infrastructure-as-Code templates in a Git repository
2. Attach the repository as a catalog to the DevCenter
3. Configure environment types to use your custom templates
4. Update project permissions for the new environment types

### Modifying Dev Box Configurations
1. Update the Dev Box definition with different VM sizes or images
2. Modify the network configuration for different connectivity requirements
3. Adjust auto-stop schedules based on team working hours
4. Configure additional software installations through customization scripts

### Extending Project Structure
1. Create additional projects for different teams or applications
2. Configure project-specific environment types and permissions
3. Implement custom policies and governance rules
4. Set up cost allocation and monitoring per project

## Troubleshooting

### Common Issues

**Dev Box Pool Creation Fails**
- Verify network connection is properly configured
- Check Azure AD licensing requirements
- Ensure sufficient quota in the target region

**Environment Deployment Fails**
- Validate catalog synchronization status
- Check subscription permissions for the DevCenter identity
- Verify environment template syntax and dependencies

**Access Denied Errors**
- Confirm user has appropriate role assignments
- Check Azure AD group membership
- Validate project permissions configuration

### Diagnostic Commands

```bash
# Check DevCenter status
az devcenter admin devcenter show --name $DEVCENTER_NAME --resource-group $RESOURCE_GROUP_NAME

# Verify catalog synchronization
az devcenter admin catalog show --name "QuickStartCatalog" --dev-center $DEVCENTER_NAME --resource-group $RESOURCE_GROUP_NAME

# List Dev Box pools
az devcenter admin pool list --project $PROJECT_NAME --resource-group $RESOURCE_GROUP_NAME

# Check role assignments
az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME"
```

## Support

For issues with this infrastructure code, refer to:
- Original recipe documentation for architectural guidance
- [Azure DevCenter documentation](https://docs.microsoft.com/en-us/azure/dev-box/)
- [Azure Deployment Environments documentation](https://docs.microsoft.com/en-us/azure/deployment-environments/)
- [Azure DevCenter REST API reference](https://docs.microsoft.com/en-us/rest/api/devcenter/)

## Additional Resources

- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)
- [Azure DevCenter pricing](https://azure.microsoft.com/en-us/pricing/details/dev-box/)
- [Dev Box security baseline](https://docs.microsoft.com/en-us/security/benchmark/azure/baselines/dev-box-security-baseline)
- [Azure Cost Management documentation](https://docs.microsoft.com/en-us/azure/cost-management-billing/costs/overview-cost-management)

## Contributing

When making changes to this infrastructure code:
1. Test changes in a development environment first
2. Follow Azure naming conventions and best practices
3. Update documentation to reflect any changes
4. Ensure all security configurations remain intact
5. Test both deployment and cleanup procedures