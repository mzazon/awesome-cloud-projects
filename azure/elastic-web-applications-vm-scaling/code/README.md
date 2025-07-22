# Infrastructure as Code for Elastic Web Applications with VM Auto-Scaling

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Elastic Web Applications with VM Auto-Scaling".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.0.80 or later installed and configured
- Azure subscription with appropriate permissions to create:
  - Virtual Machine Scale Sets
  - Load Balancers
  - Virtual Networks
  - Network Security Groups
  - Public IP addresses
  - Monitor resources
- For Terraform: Terraform CLI v1.0+ installed
- For Bicep: Azure CLI with Bicep extension installed

## Architecture Overview

This implementation deploys:
- Azure Virtual Machine Scale Set (2-10 instances)
- Azure Standard Load Balancer with public IP
- Virtual Network with subnet and Network Security Group
- Auto-scaling rules based on CPU metrics
- Application Insights for monitoring
- Health probes and alerting

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to Bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-autoscale-web-app \
    --template-file main.bicep \
    --parameters location="East US" \
    --parameters vmssName="vmss-webapp-$(openssl rand -hex 3)" \
    --parameters adminUsername="azureuser"

# Monitor deployment
az deployment group show \
    --resource-group rg-autoscale-web-app \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="location=East US" \
    -var="resource_group_name=rg-autoscale-web-app"

# Apply the configuration
terraform apply \
    -var="location=East US" \
    -var="resource_group_name=rg-autoscale-web-app"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration options
# Script will create all resources and provide endpoint information
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `East US` | Yes |
| `vmssName` | Name for the Virtual Machine Scale Set | `vmss-webapp-${uniqueString}` | No |
| `loadBalancerName` | Name for the Load Balancer | `lb-webapp-${uniqueString}` | No |
| `vnetName` | Name for the Virtual Network | `vnet-webapp-${uniqueString}` | No |
| `adminUsername` | Admin username for VMs | `azureuser` | Yes |
| `vmSku` | VM size for scale set instances | `Standard_B2s` | No |
| `instanceCount` | Initial number of instances | `2` | No |
| `minInstances` | Minimum instances for auto-scaling | `2` | No |
| `maxInstances` | Maximum instances for auto-scaling | `10` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for deployment | `East US` | No |
| `resource_group_name` | Name of the resource group | `rg-autoscale-web-app` | No |
| `environment` | Environment tag | `demo` | No |
| `vm_size` | VM size for scale set instances | `Standard_B2s` | No |
| `admin_username` | Admin username for VMs | `azureuser` | No |
| `initial_capacity` | Initial number of instances | `2` | No |
| `min_capacity` | Minimum instances for auto-scaling | `2` | No |
| `max_capacity` | Maximum instances for auto-scaling | `10` | No |

### Script Configuration

The bash scripts use environment variables for configuration:

```bash
# Set before running deploy.sh
export LOCATION="East US"
export RESOURCE_GROUP="rg-autoscale-web-app"
export VM_SIZE="Standard_B2s"
export ADMIN_USERNAME="azureuser"
```

## Deployment Verification

After deployment, verify the infrastructure:

### Check Scale Set Status

```bash
# List VMSS instances
az vmss list-instances \
    --resource-group rg-autoscale-web-app \
    --name vmss-webapp-* \
    --output table

# Check auto-scaling configuration
az monitor autoscale show \
    --resource-group rg-autoscale-web-app \
    --name autoscale-profile
```

### Test Load Balancer

```bash
# Get public IP
PUBLIC_IP=$(az network public-ip show \
    --resource-group rg-autoscale-web-app \
    --name pip-webapp-* \
    --query ipAddress \
    --output tsv)

# Test web application
curl http://${PUBLIC_IP}

# Test load balancing (run multiple times)
for i in {1..5}; do
    curl -s http://${PUBLIC_IP} | grep "Web Server"
done
```

### Monitor Auto-Scaling

```bash
# View current instance count
az vmss show \
    --resource-group rg-autoscale-web-app \
    --name vmss-webapp-* \
    --query "sku.capacity"

# Generate load to trigger scaling (optional)
# Warning: This may trigger additional charges
for i in {1..1000}; do
    curl -s http://${PUBLIC_IP} > /dev/null &
done
```

## Monitoring and Observability

### Application Insights

Access Application Insights dashboard:

```bash
# Get Application Insights app ID
az monitor app-insights component show \
    --resource-group rg-autoscale-web-app \
    --app webapp-insights-* \
    --query "appId" \
    --output tsv
```

### Azure Monitor Alerts

View configured alerts:

```bash
# List alert rules
az monitor metrics alert list \
    --resource-group rg-autoscale-web-app \
    --output table
```

## Cost Optimization

This infrastructure includes several cost optimization features:

- **Auto-scaling**: Automatically adjusts instance count based on demand
- **Standard_B2s VMs**: Burstable instances suitable for variable workloads
- **Basic Load Balancer option**: Can be configured for lower-cost scenarios
- **Resource tagging**: Enables cost tracking and allocation

### Estimated Costs

| Component | Estimated Monthly Cost (East US) |
|-----------|----------------------------------|
| Standard_B2s VMs (2-10 instances) | $30-150 |
| Standard Load Balancer | $20-40 |
| Public IP (Standard) | $4 |
| Application Insights | $0-10 |
| **Total Estimate** | **$54-204** |

*Costs are estimates and may vary based on actual usage, region, and current Azure pricing.*

## Troubleshooting

### Common Issues

1. **Deployment Fails Due to Quotas**
   ```bash
   # Check compute quotas
   az vm list-usage --location "East US" \
       --query "[?localName=='Standard Bs Family vCPUs']"
   ```

2. **Auto-scaling Not Triggering**
   ```bash
   # Check auto-scale profile status
   az monitor autoscale show \
       --resource-group rg-autoscale-web-app \
       --name autoscale-profile \
       --query "enabled"
   ```

3. **Load Balancer Health Probe Failures**
   ```bash
   # Check backend pool health
   az network lb show-backend-health \
       --resource-group rg-autoscale-web-app \
       --name lb-webapp-*
   ```

4. **SSH Access Issues**
   ```bash
   # Add SSH access rule to NSG if needed
   az network nsg rule create \
       --resource-group rg-autoscale-web-app \
       --nsg-name nsg-webapp-* \
       --name Allow-SSH \
       --protocol tcp \
       --priority 120 \
       --destination-port-range 22 \
       --access allow
   ```

## Security Considerations

This implementation includes several security best practices:

- **Network Security Groups**: Restrict traffic to necessary ports (80, 443)
- **Standard Load Balancer**: Provides better security and availability features
- **No direct SSH access**: Instances are accessed through the load balancer
- **Application Insights**: Monitors for security-related events

### Security Hardening Options

1. **Enable Azure Defender**
2. **Implement WAF with Application Gateway**
3. **Use Azure Key Vault for secrets management**
4. **Enable disk encryption**
5. **Configure Azure Security Center recommendations**

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-autoscale-web-app \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy \
    -var="location=East US" \
    -var="resource_group_name=rg-autoscale-web-app"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
# Script will remove resources in correct order
```

### Verify Cleanup

```bash
# Confirm resource group is deleted
az group exists --name rg-autoscale-web-app
# Should return: false
```

## Customization

### Scaling Configuration

Modify auto-scaling rules in the IaC templates:

```bicep
// In Bicep: Adjust scaling thresholds
scaleOutRule: {
  scaleAction: {
    direction: 'Increase'
    type: 'ChangeCount'
    value: '2'  // Scale out by 2 instances
    cooldown: 'PT5M'
  }
  metricTrigger: {
    metricName: 'Percentage CPU'
    threshold: 70  // Trigger at 70% CPU
    timeAggregation: 'Average'
    timeWindow: 'PT5M'
  }
}
```

### Network Configuration

Modify Virtual Network settings:

```hcl
# In Terraform: Adjust network configuration
variable "vnet_address_space" {
  description = "Address space for VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefix" {
  description = "Address prefix for subnet"
  type        = string
  default     = "10.0.1.0/24"
}
```

### Application Configuration

Customize the web application deployment:

```bash
# Modify cloud-init script in IaC templates
custom_data = base64encode(<<-EOF
#cloud-config
package_upgrade: true
packages:
  - nginx
  - htop
  - curl
runcmd:
  - systemctl start nginx
  - systemctl enable nginx
  - echo "<h1>Custom Web App</h1>" > /var/www/html/index.html
  - systemctl restart nginx
EOF
)
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Azure Documentation**: [Virtual Machine Scale Sets](https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/)
3. **Load Balancer Documentation**: [Azure Load Balancer](https://docs.microsoft.com/en-us/azure/load-balancer/)
4. **Bicep Documentation**: [Azure Bicep](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
5. **Terraform Azure Provider**: [Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate with `az deployment validate` (Bicep) or `terraform plan` (Terraform)
3. Update documentation and examples
4. Consider backwards compatibility
5. Add appropriate tags and metadata

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Please review and modify according to your organization's security and compliance requirements before using in production environments.