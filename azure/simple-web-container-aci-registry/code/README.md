# Infrastructure as Code for Simple Web Container with Azure Container Instances

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Web Container with Azure Container Instances".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.0.55 or later)
- Docker installed locally for building container images
- Appropriate Azure permissions for:
  - Resource Group creation and management
  - Azure Container Registry creation and management
  - Azure Container Instances creation and management
- Active Azure subscription with Container Instances service enabled

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-simple-web-container \
    --template-file main.bicep \
    --parameters location=eastus \
                 containerRegistryName=acrsimpleweb$(openssl rand -hex 3) \
                 containerInstanceName=aci-nginx-$(openssl rand -hex 3)
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# The script will:
# 1. Create Azure Container Registry
# 2. Build and push the nginx container image
# 3. Deploy to Azure Container Instances
# 4. Provide the public IP address for testing
```

## Solution Components

This Infrastructure as Code deploys the following Azure resources:

- **Resource Group**: Container for all related resources
- **Azure Container Registry**: Private Docker registry for storing container images
- **Azure Container Instances**: Serverless container hosting service
- **Public IP Address**: Automatically assigned for web access

## Configuration Options

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | eastus | Azure region for deployment |
| `containerRegistryName` | string | Generated | Unique name for container registry |
| `containerInstanceName` | string | Generated | Name for the container instance |
| `imageName` | string | simple-nginx | Container image name |
| `imageTag` | string | v1 | Container image tag |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `location` | string | eastus | Azure region for deployment |
| `resource_group_name` | string | Generated | Resource group name |
| `container_registry_name` | string | Generated | Container registry name |
| `container_instance_name` | string | Generated | Container instance name |
| `image_name` | string | simple-nginx | Container image name |
| `image_tag` | string | v1 | Container image tag |

## Deployment Steps

The infrastructure deployment follows this sequence:

1. **Resource Group Creation**: Creates the container resource group
2. **Container Registry Setup**: Deploys Azure Container Registry with admin access
3. **Image Build and Push**: Builds custom nginx image and pushes to registry
4. **Container Instance Deployment**: Creates ACI with public IP address
5. **Output Generation**: Provides web application URL and connection details

## Validation and Testing

After deployment, verify the solution:

```bash
# Check container instance status
az container show \
    --resource-group <resource-group-name> \
    --name <container-instance-name> \
    --output table

# Test web application (replace with actual IP)
curl -I http://<public-ip-address>

# View container logs
az container logs \
    --resource-group <resource-group-name> \
    --name <container-instance-name>
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-simple-web-container \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all infrastructure
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# This will remove:
# - Container instances
# - Container registry
# - Resource group
# - Local container files
```

## Cost Considerations

- **Azure Container Registry**: Basic tier provides 10 GB storage (~$5/month)
- **Azure Container Instances**: Pay-per-second billing (~$0.50-$2.00/hour when running)
- **Data Transfer**: Minimal costs for web traffic and image pulls
- **Storage**: Additional charges for container image storage beyond included quota

> **Cost Optimization Tip**: Container instances only incur charges while running. Consider implementing auto-shutdown for development environments.

## Security Features

The deployed infrastructure includes:

- **Private Container Registry**: Secure image storage with authentication
- **Admin Authentication**: Registry access controls with managed credentials
- **Network Security**: Public IP with configurable port access
- **Resource Isolation**: Dedicated container instances with resource limits
- **Azure Integration**: Native security through Azure Active Directory

## Customization Examples

### Custom HTML Content

Modify the nginx-app/index.html file before deployment to customize the web application content.

### Resource Sizing

Adjust container resources in the IaC templates:

```bicep
// Bicep example
containerResources: {
  cpu: 2
  memoryInGb: 4
}
```

```hcl
# Terraform example
cpu    = "2.0"
memory = "4.0"
```

### Multiple Container Deployment

Extend the solution to deploy multiple containers in a container group by adding additional container definitions to the IaC templates.

## Troubleshooting

### Common Issues

1. **Registry Authentication Failures**
   - Verify admin access is enabled on the container registry
   - Check registry credentials are correctly configured

2. **Container Startup Failures**
   - Review container logs: `az container logs --resource-group <rg> --name <name>`
   - Verify image exists in registry: `az acr repository list --name <registry>`

3. **Network Connectivity Issues**
   - Confirm public IP is assigned: `az container show --query ipAddress.ip`
   - Verify port 80 is configured in container instance

4. **Resource Naming Conflicts**
   - Container registry names must be globally unique
   - Use random suffixes or timestamps for uniqueness

### Debug Commands

```bash
# Check resource group contents
az resource list --resource-group <resource-group-name> --output table

# Verify container registry
az acr show --name <registry-name> --query "{loginServer:loginServer, adminUserEnabled:adminUserEnabled}"

# Monitor container instance events
az container show --resource-group <rg> --name <name> --query containers[0].instanceView.events
```

## Performance Optimization

- **Container Resources**: Allocate appropriate CPU and memory based on workload requirements
- **Image Optimization**: Use multi-stage Docker builds to minimize image size
- **Registry Location**: Deploy registry in the same region as container instances
- **Caching Strategy**: Implement container image layer caching for faster deployments

## Integration Options

### CI/CD Integration

The IaC templates can be integrated with:

- **Azure DevOps**: Use Azure Resource Manager deployment tasks
- **GitHub Actions**: Implement automated deployment workflows
- **Azure CLI**: Script-based deployment automation
- **Terraform Cloud**: Remote state management and collaboration

### Monitoring Integration

Extend the solution with:

- **Azure Monitor**: Container performance and health monitoring
- **Application Insights**: Application performance monitoring
- **Log Analytics**: Centralized logging and analysis
- **Azure Alerts**: Proactive notification and response

## Support and Documentation

- [Azure Container Instances Documentation](https://learn.microsoft.com/en-us/azure/container-instances/)
- [Azure Container Registry Documentation](https://learn.microsoft.com/en-us/azure/container-registry/)
- [Bicep Language Reference](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or the Azure service documentation.

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Refer to Azure service terms and conditions for production usage.