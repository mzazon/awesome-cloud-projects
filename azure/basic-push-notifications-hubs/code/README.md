# Infrastructure as Code for Basic Push Notifications with Notification Hubs

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Basic Push Notifications with Notification Hubs".

## Available Implementations

- **Bicep**: Azure native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.67.0 or later)
- Azure subscription with Contributor permissions
- Notification Hub CLI extension (installed automatically with Azure CLI 2.67.0+)
- For Terraform: Terraform installed (version 1.0 or later)
- For Bicep: Bicep CLI installed (bundled with Azure CLI)

## Architecture Overview

This infrastructure deploys:
- Azure Resource Group
- Azure Notification Hub Namespace (Free tier)
- Azure Notification Hub
- Authorization rules for client and server access

## Quick Start

### Using Bicep

```bash
# Navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-notifications-demo \
    --template-file main.bicep \
    --parameters \
        location=eastus \
        notificationHubNamespaceName=nh-namespace-demo \
        notificationHubName=notification-hub-demo

# Get deployment outputs
az deployment group show \
    --resource-group rg-notifications-demo \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan \
    -var="resource_group_name=rg-notifications-demo" \
    -var="location=eastus" \
    -var="notification_hub_namespace_name=nh-namespace-demo" \
    -var="notification_hub_name=notification-hub-demo"

# Apply the configuration
terraform apply \
    -var="resource_group_name=rg-notifications-demo" \
    -var="location=eastus" \
    -var="notification_hub_namespace_name=nh-namespace-demo" \
    -var="notification_hub_name=notification-hub-demo"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure resource names and location
# The script will create all resources and display connection strings
```

## Configuration Options

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `eastus` | Azure region for deployment |
| `notificationHubNamespaceName` | string | - | Name for the Notification Hub namespace |
| `notificationHubName` | string | - | Name for the Notification Hub |
| `skuName` | string | `Free` | SKU for the Notification Hub namespace |
| `tags` | object | `{}` | Resource tags |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `resource_group_name` | string | - | Name of the resource group |
| `location` | string | `East US` | Azure region for deployment |
| `notification_hub_namespace_name` | string | - | Name for the Notification Hub namespace |
| `notification_hub_name` | string | - | Name for the Notification Hub |
| `sku_name` | string | `Free` | SKU for the Notification Hub namespace |
| `tags` | map(string) | `{}` | Resource tags |

### Environment Variables (Bash Scripts)

The bash scripts use environment variables that can be customized:

```bash
export RESOURCE_GROUP="rg-notifications-custom"
export LOCATION="westus2"
export NH_NAMESPACE="nh-namespace-custom"
export NH_NAME="notification-hub-custom"
```

## Validation

After deployment, verify the infrastructure:

### Check Resource Group

```bash
az group show --name <resource-group-name> --output table
```

### Verify Notification Hub

```bash
az notification-hub show \
    --resource-group <resource-group-name> \
    --namespace-name <namespace-name> \
    --name <hub-name> \
    --output table
```

### Test Notification

```bash
az notification-hub test-send \
    --resource-group <resource-group-name> \
    --namespace-name <namespace-name> \
    --notification-hub-name <hub-name> \
    --notification-format template \
    --message "Hello from Infrastructure as Code!"
```

### Get Connection Strings

```bash
# Listen connection string (for client apps)
az notification-hub authorization-rule list-keys \
    --resource-group <resource-group-name> \
    --namespace-name <namespace-name> \
    --notification-hub-name <hub-name> \
    --name DefaultListenSharedAccessSignature \
    --query primaryConnectionString --output tsv

# Full access connection string (for server apps)
az notification-hub authorization-rule list-keys \
    --resource-group <resource-group-name> \
    --namespace-name <namespace-name> \
    --notification-hub-name <hub-name> \
    --name DefaultFullSharedAccessSignature \
    --query primaryConnectionString --output tsv
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name rg-notifications-demo --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy \
    -var="resource_group_name=rg-notifications-demo" \
    -var="location=eastus" \
    -var="notification_hub_namespace_name=nh-namespace-demo" \
    -var="notification_hub_name=notification-hub-demo"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Cost Considerations

- **Free Tier**: Includes 1 million push notifications and 500 active devices
- **Standard Tier**: Pay-per-use pricing for higher volumes
- **Basic Tier**: Fixed monthly fee with included notifications

For detailed pricing, see [Azure Notification Hubs pricing](https://azure.microsoft.com/en-us/pricing/details/notification-hubs/).

## Security Best Practices

1. **Access Control**: Use separate connection strings for client and server applications
2. **Network Security**: Consider using Private Endpoints for production workloads
3. **Credential Management**: Store connection strings in Azure Key Vault
4. **Monitoring**: Enable diagnostic settings for security monitoring

## Troubleshooting

### Common Issues

1. **Namespace Name Conflicts**: Ensure namespace names are globally unique
2. **Permission Errors**: Verify Contributor permissions on the subscription/resource group
3. **CLI Extension**: Install notification-hub extension if not available:
   ```bash
   az extension add --name notification-hub
   ```

### Debug Commands

```bash
# Check resource deployment status
az deployment group list --resource-group <resource-group-name> --output table

# View deployment errors
az deployment group show \
    --resource-group <resource-group-name> \
    --name <deployment-name> \
    --query properties.error
```

## Next Steps

After deploying the infrastructure:

1. Configure platform-specific credentials (APNS, FCM, WNS)
2. Integrate with mobile applications using the listen connection string
3. Implement server-side notification sending using the full access connection string
4. Set up monitoring and alerting for notification delivery metrics
5. Consider implementing notification templates for personalized messaging

## Support

For issues with this infrastructure code:
- Refer to the original recipe documentation
- Check [Azure Notification Hubs documentation](https://docs.microsoft.com/en-us/azure/notification-hubs/)
- Review [Azure CLI notification-hub commands](https://docs.microsoft.com/en-us/cli/azure/notification-hub)

## Contributing

When updating this infrastructure code:
1. Test all deployment methods
2. Validate against Azure best practices
3. Update documentation for any new parameters or outputs
4. Ensure cleanup procedures work correctly