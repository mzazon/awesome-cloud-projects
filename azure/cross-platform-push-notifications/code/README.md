# Infrastructure as Code for Cross-Platform Push Notifications with Spring Microservices

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cross-Platform Push Notifications with Spring Microservices".

## Available Implementations

- **Bicep**: Azure native infrastructure as code language
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with contributor access
- Java 11 or later for Spring Boot application
- Firebase project with FCM credentials (for Android notifications)
- Apple Developer account with APNS certificates (for iOS notifications)
- Appropriate Azure permissions for:
  - Creating resource groups
  - Managing Azure Notification Hubs
  - Managing Azure Spring Apps
  - Managing Azure Key Vault
  - Managing Azure Monitor and Application Insights

## Quick Start

### Using Bicep
```bash
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-pushnotif-demo \
    --template-file main.bicep \
    --parameters environment=dev \
                 location=eastus \
                 notificationHubName=nh-multiplatform \
                 springAppsName=asa-pushnotif
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="location=eastus" \
    -var="environment=dev"

# Apply the configuration
terraform apply \
    -var="location=eastus" \
    -var="environment=dev"
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure environment variables
```

## Configuration Parameters

### Bicep Parameters
- `environment`: Environment name (dev, staging, prod) - default: dev
- `location`: Azure region for resources - default: eastus
- `notificationHubName`: Name for the notification hub - default: nh-multiplatform
- `springAppsName`: Name for Azure Spring Apps instance - auto-generated with suffix
- `keyVaultName`: Name for Azure Key Vault - auto-generated with suffix

### Terraform Variables
- `location`: Azure region for deployment
- `environment`: Environment tag for resources
- `resource_group_name`: Name of the resource group
- `notification_hub_namespace_name`: Notification Hub namespace name
- `spring_apps_name`: Azure Spring Apps service name
- `key_vault_name`: Azure Key Vault name

## Post-Deployment Configuration

After infrastructure deployment, you'll need to configure platform-specific credentials:

### 1. Configure FCM (Firebase Cloud Messaging) for Android
```bash
# Store FCM server key in Key Vault
az keyvault secret set \
    --vault-name ${KEY_VAULT_NAME} \
    --name "fcm-server-key" \
    --value "your-actual-fcm-server-key"

# Configure in Azure Portal
# Navigate to Notification Hub > Google (GCM/FCM)
# Enter FCM Server Key and save
```

### 2. Configure APNS for iOS
```bash
# Store APNS credentials in Key Vault
az keyvault secret set \
    --vault-name ${KEY_VAULT_NAME} \
    --name "apns-key-id" \
    --value "your-apns-key-id"

az keyvault secret set \
    --vault-name ${KEY_VAULT_NAME} \
    --name "apns-team-id" \
    --value "your-apns-team-id"

# Configure in Azure Portal
# Navigate to Notification Hub > Apple (APNS)
# Upload certificate or configure token-based authentication
```

### 3. Configure Web Push (VAPID)
```bash
# Generate VAPID keys (use online tool or Node.js)
# Store in Key Vault
az keyvault secret set \
    --vault-name ${KEY_VAULT_NAME} \
    --name "vapid-public-key" \
    --value "your-vapid-public-key"

az keyvault secret set \
    --vault-name ${KEY_VAULT_NAME} \
    --name "vapid-private-key" \
    --value "your-vapid-private-key"
```

## Application Deployment

### Deploy Spring Boot Application
```bash
# Build the Spring Boot application
cd notification-service/
./mvnw clean package -DskipTests

# Deploy to Azure Spring Apps
az spring app deploy \
    --name notification-api \
    --service ${SPRING_APPS_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --artifact-path target/notification-service-1.0.jar

# Get application URL
APP_URL=$(az spring app show \
    --name notification-api \
    --service ${SPRING_APPS_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query properties.url -o tsv)

echo "Application URL: ${APP_URL}"
```

## Testing the Deployment

### 1. Verify Infrastructure Health
```bash
# Check Notification Hub status
az notification-hub show \
    --resource-group ${RESOURCE_GROUP} \
    --namespace-name ${NOTIFICATION_HUB_NAMESPACE} \
    --name ${NOTIFICATION_HUB_NAME} \
    --query provisioningState

# Check Spring Apps status
az spring app show \
    --name notification-api \
    --service ${SPRING_APPS_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query properties.provisioningState

# Test application health endpoint
curl -s ${APP_URL}/actuator/health
```

### 2. Send Test Notification
```bash
# Register a test device
curl -X POST ${APP_URL}/api/devices/register \
    -H "Content-Type: application/json" \
    -d '{
      "deviceId": "test-device-123",
      "platform": "android",
      "pushHandle": "test-fcm-token",
      "tags": ["test-user", "android"]
    }'

# Send test notification
curl -X POST ${APP_URL}/api/notifications \
    -H "Content-Type: application/json" \
    -d '{
      "message": "Hello from Azure!",
      "platforms": ["android"],
      "tags": ["test-user"]
    }'
```

### 3. Monitor Delivery Metrics
```bash
# Query notification metrics
az monitor metrics list \
    --resource $(az notification-hub show \
        --resource-group ${RESOURCE_GROUP} \
        --namespace-name ${NOTIFICATION_HUB_NAMESPACE} \
        --name ${NOTIFICATION_HUB_NAME} \
        --query id -o tsv) \
    --metric "notification.pushes" \
    --interval PT1M
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-pushnotif-demo \
    --yes \
    --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy \
    -var="location=eastus" \
    -var="environment=dev"
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

## Architecture Overview

The deployed infrastructure includes:

- **Azure Notification Hubs**: Central service for managing push notifications across platforms
- **Azure Spring Apps**: Managed platform hosting the Spring Boot notification service
- **Azure Key Vault**: Secure storage for platform-specific credentials (FCM, APNS, VAPID keys)
- **Azure Monitor & Application Insights**: Monitoring and analytics for notification delivery
- **Log Analytics Workspace**: Centralized logging for all services

## Security Considerations

- All sensitive credentials are stored in Azure Key Vault
- Managed identities are used for secure service-to-service authentication
- Network security groups restrict access to necessary ports only
- All communications use TLS encryption
- RBAC is configured following least privilege principles

## Cost Estimation

Estimated monthly costs for basic usage:
- Azure Notification Hubs (Standard): ~$10/month (includes 10M pushes)
- Azure Spring Apps (Standard): ~$40-60/month depending on usage
- Azure Key Vault: ~$3/month for operations
- Azure Monitor/Application Insights: ~$5-15/month depending on data volume

Total estimated cost: ~$60-90/month for development/testing workloads

## Troubleshooting

### Common Issues

1. **Notification delivery failures**:
   - Verify platform credentials in Key Vault
   - Check Notification Hub configuration in Azure Portal
   - Review Application Insights logs for errors

2. **Spring Apps deployment issues**:
   - Verify managed identity has Key Vault access
   - Check application logs in Azure Portal
   - Ensure Java version compatibility

3. **Authentication errors**:
   - Verify Azure CLI is authenticated
   - Check resource group permissions
   - Validate subscription access

### Debug Commands
```bash
# Check resource group resources
az resource list --resource-group ${RESOURCE_GROUP} --output table

# View Spring Apps logs
az spring app logs \
    --name notification-api \
    --service ${SPRING_APPS_NAME} \
    --resource-group ${RESOURCE_GROUP}

# Check Key Vault access policies
az keyvault show \
    --name ${KEY_VAULT_NAME} \
    --query properties.accessPolicies
```

## Customization

### Environment-Specific Configurations

Modify the parameter files or variables to customize for different environments:

- **Development**: Minimal SKUs, basic monitoring
- **Staging**: Production-like setup with enhanced monitoring
- **Production**: High availability, advanced security, comprehensive monitoring

### Scaling Considerations

- Azure Spring Apps supports auto-scaling based on CPU/memory metrics
- Notification Hubs Standard tier supports up to 10M device registrations
- Consider upgrading to Premium tier for high-volume scenarios (100M+ notifications/month)

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation
2. Review Azure service documentation
3. Consult Azure support for platform-specific issues
4. Check the troubleshooting section above

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Refer to Azure service pricing and terms for production usage.