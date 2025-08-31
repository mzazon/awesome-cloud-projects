# Infrastructure as Code for Simple Email Notifications with Communication Services

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Email Notifications with Communication Services".

## Available Implementations

- **Bicep**: Azure native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login` completed)
- Appropriate Azure subscription with permissions for:
  - Resource Group creation
  - Communication Services resource creation
  - Email Communication Services
  - Azure Functions and App Service Plans
  - Storage Accounts
- Node.js 18+ (for function code deployment)
- Estimated cost: $0.01-$0.05 USD for testing (minimal charges for function execution and email sending)

### Additional Prerequisites by Implementation

#### Bicep
- Azure CLI with Bicep extension installed
- Azure PowerShell (optional, for advanced scenarios)

#### Terraform
- Terraform CLI installed (version 1.0+)
- Azure provider for Terraform

## Quick Start

### Using Bicep

```bash
# Set your parameters
export LOCATION="eastus"
export RESOURCE_GROUP="rg-email-notifications-demo"

# Deploy the infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file bicep/main.bicep \
    --parameters location=${LOCATION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
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

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export LOCATION="eastus"                    # Azure region
export RESOURCE_GROUP="rg-email-demo"      # Resource group name
export COMMUNICATION_SERVICE="cs-email"    # Communication Services name
export FUNCTION_APP="func-email"           # Function App name
export STORAGE_ACCOUNT="stemail"           # Storage account name
```

### Customizable Parameters

#### Bicep Parameters
- `location`: Azure region (default: resourceGroup().location)
- `projectName`: Base name for resources (default: "email-notifications")
- `environment`: Environment tag (default: "demo")

#### Terraform Variables
- `location`: Azure region (default: "East US")
- `resource_group_name`: Resource group name
- `project_name`: Base name for all resources
- `environment`: Environment tag for resources
- `function_runtime_version`: Node.js runtime version (default: "18")

## Validation & Testing

After deployment, test the email notification system:

### Get Function URL

#### Using Azure CLI
```bash
# Get function app name from deployment
FUNCTION_APP_NAME=$(az functionapp list \
    --resource-group ${RESOURCE_GROUP} \
    --query "[0].name" \
    --output tsv)

# Get function key
FUNCTION_KEY=$(az functionapp keys list \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query functionKeys.default \
    --output tsv)

# Construct function URL
FUNCTION_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net/api/index?code=${FUNCTION_KEY}"
echo "Function URL: ${FUNCTION_URL}"
```

### Test Email Sending

```bash
# Send a test email
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
        "to": "your-email@example.com",
        "subject": "Test Email from Azure Functions",
        "body": "This is a test email sent from Azure Functions using Communication Services."
    }'
```

### Expected Response

```json
{
    "message": "Email sent successfully",
    "messageId": "abc123-def456-ghi789",
    "status": "Succeeded"
}
```

### Validate Infrastructure

#### Check Communication Services
```bash
az communication list \
    --resource-group ${RESOURCE_GROUP} \
    --output table
```

#### Check Function App Status
```bash
az functionapp show \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query "state" \
    --output tsv
```

#### View Function Logs
```bash
az functionapp logs tail \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP}
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

## Architecture Components

This infrastructure deploys the following Azure resources:

1. **Resource Group**: Container for all resources
2. **Communication Services**: Email sending service
3. **Email Communication Service**: Managed email domain
4. **Storage Account**: Function app storage backend
5. **Function App**: Serverless HTTP trigger function
6. **Application Insights**: Function monitoring and logging

## Security Considerations

- Communication Services connection string stored as app setting
- Function app uses system-assigned managed identity where possible
- HTTPS enforced for all endpoints
- Function access key required for API calls
- Sender address restricted to managed domain

## Monitoring

### Application Insights Integration

The Function App automatically integrates with Application Insights for:
- Function execution monitoring
- Performance metrics
- Error tracking
- Custom telemetry

### Key Metrics to Monitor

- Function execution count
- Function duration
- Error rates
- Email send success/failure rates

## Troubleshooting

### Common Issues

1. **Function not responding**
   - Check Function App status in Azure portal
   - Verify application settings are configured
   - Review function logs for errors

2. **Email not sending**
   - Verify Communication Services connection string
   - Check sender address configuration
   - Review Communication Services quota limits

3. **Authentication errors**
   - Verify function key is correct
   - Check if function app is running
   - Validate request format matches expected schema

### Debug Commands

```bash
# Check resource group resources
az resource list \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# Get Communication Services connection string
az communication list-key \
    --name ${COMMUNICATION_SERVICE} \
    --resource-group ${RESOURCE_GROUP}

# Check function app configuration
az functionapp config appsettings list \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP}
```

## Cost Optimization

- Function App uses Consumption plan (pay-per-execution)
- Storage account uses Standard LRS for cost efficiency
- Communication Services charges per email sent
- Consider Azure Free Tier limits for development/testing

## Scaling Considerations

- Functions automatically scale based on demand
- Communication Services supports high-volume email sending
- Consider upgrading storage account SKU for high-throughput scenarios
- Monitor and adjust Function App timeout settings for bulk operations

## Best Practices

1. **Error Handling**: Implement retry logic for transient failures
2. **Monitoring**: Set up alerts for failed email sends
3. **Security**: Use Azure Key Vault for sensitive configuration in production
4. **Performance**: Consider connection pooling for high-volume scenarios
5. **Compliance**: Review data residency requirements for email content

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Azure service documentation
3. Validate resource configurations in Azure portal
4. Review function logs and Application Insights data

## Next Steps

To extend this solution:
1. Add HTML email template support
2. Implement email queuing with Service Bus
3. Add delivery status tracking with Event Grid
4. Integrate with Azure AD for authentication
5. Add support for email attachments