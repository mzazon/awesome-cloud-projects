# Infrastructure as Code for Simple SMS Notifications with Communication Services and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple SMS Notifications with Communication Services and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.37.0 or later)
- Azure subscription with active billing account
- Appropriate permissions for resource creation:
  - Communication Services Contributor
  - Azure Functions Contributor
  - Storage Account Contributor
  - Resource Group Contributor
- Azure Functions Core Tools v4 (for local development)
- Node.js 20 LTS (for function development)

> **Note**: SMS capabilities depend on your Azure billing location and regional availability. Review [subscription eligibility](https://docs.microsoft.com/en-us/azure/communication-services/concepts/numbers/sub-eligibility-number-capability) before proceeding.

## Quick Start

### Using Bicep (Recommended)

Deploy the complete SMS notification infrastructure using Azure's native IaC language:

```bash
# Create resource group
az group create --name rg-sms-notifications --location eastus

# Deploy infrastructure using Bicep
az deployment group create \
    --resource-group rg-sms-notifications \
    --template-file bicep/main.bicep \
    --parameters environmentName=demo \
                 location=eastus
```

### Using Terraform

Deploy using HashiCorp Terraform with the Azure provider:

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="environment_name=demo" \
               -var="location=eastus"

# Apply infrastructure changes
terraform apply -var="environment_name=demo" \
                -var="location=eastus"
```

### Using Bash Scripts

Deploy using automated bash scripts that execute Azure CLI commands:

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration options
```

## Configuration Options

### Bicep Parameters

- `environmentName`: Environment identifier (default: "dev")
- `location`: Azure region for deployment (default: "eastus")
- `phoneNumberAreaCode`: Area code for toll-free number (default: "800")
- `enableApplicationInsights`: Enable monitoring (default: true)

### Terraform Variables

- `environment_name`: Environment identifier (default: "dev")
- `location`: Azure region for deployment (default: "eastus")
- `phone_number_area_code`: Area code for toll-free number (default: "800")
- `enable_app_insights`: Enable Application Insights monitoring (default: true)
- `tags`: Resource tags (default: {})

### Bash Script Environment Variables

Set these variables before running the deployment script:

```bash
export ENVIRONMENT_NAME="demo"
export LOCATION="eastus"
export PHONE_AREA_CODE="800"
export ENABLE_MONITORING="true"
```

## Post-Deployment Steps

### 1. Toll-Free Number Verification

After deployment, your toll-free number requires verification before it can send SMS messages:

1. Navigate to your Communication Services resource in the Azure portal
2. Go to "Phone numbers" section
3. Select your acquired toll-free number
4. Complete the toll-free verification form with:
   - Business information
   - Use case description
   - Sample message templates
   - Expected message volume

> **Warning**: Unverified toll-free numbers cannot send SMS messages. Verification typically takes 2-3 business days.

### 2. Function App Deployment

Deploy the SMS function code to your newly created Function App:

```bash
# Navigate to function source directory
cd ../function-source/

# Install dependencies
npm install

# Deploy to Azure Function App
func azure functionapp publish <your-function-app-name>
```

### 3. Testing Your SMS Function

```bash
# Get function URL and key
FUNCTION_URL=$(az functionapp function show \
    --name <your-function-app-name> \
    --resource-group <your-resource-group> \
    --function-name sendSMS \
    --query "invokeUrlTemplate" --output tsv)

FUNCTION_KEY=$(az functionapp keys list \
    --name <your-function-app-name> \
    --resource-group <your-resource-group> \
    --query "functionKeys.default" --output tsv)

# Test SMS sending
curl -X POST "${FUNCTION_URL}?code=${FUNCTION_KEY}" \
     -H "Content-Type: application/json" \
     -d '{"to": "+1234567890", "message": "Hello from Azure SMS!"}'
```

## Monitoring and Logging

### Application Insights Integration

All implementations include Application Insights for comprehensive monitoring:

- Function execution metrics
- SMS delivery success/failure rates
- Error tracking and diagnostics
- Performance monitoring
- Custom telemetry and alerts

### Accessing Logs

```bash
# View Function App logs
az functionapp logs tail \
    --name <your-function-app-name> \
    --resource-group <your-resource-group>

# Query Application Insights
az monitor app-insights query \
    --app <your-app-insights-name> \
    --analytics-query "requests | where timestamp > ago(1h) | summarize count() by resultCode"
```

## Security Considerations

### Network Security

- Function App uses HTTPS-only communication
- Communication Services connection string stored as secure app setting
- Function access protected by authentication keys
- Optional VNet integration available for enhanced security

### Access Control

- Function authentication level set to 'function' requiring access keys
- Communication Services uses connection string authentication
- Least privilege IAM roles applied to all services
- Optional Azure AD authentication for enhanced security

### Data Protection

- All data encrypted in transit using TLS 1.2+
- Communication Services provides end-to-end encryption
- Function App configuration encrypted at rest
- Optional customer-managed encryption keys supported

## Cost Optimization

### Pricing Breakdown

- **Azure Functions**: Pay-per-execution on Consumption plan (~$0.000016 per GB-second)
- **Communication Services**: $2/month toll-free number lease + $0.0075-0.01 per SMS
- **Storage Account**: ~$0.02/month for function storage (LRS)
- **Application Insights**: First 5GB/month free, then $2.30/GB

### Cost-Saving Tips

1. Use Consumption plan for variable workloads
2. Implement message batching for high-volume scenarios
3. Monitor and optimize function execution time
4. Use Azure Reservations for predictable workloads
5. Implement message templates to reduce function complexity

## Troubleshooting

### Common Issues

**SMS not delivered**:
- Verify toll-free number is verified for SMS usage
- Check phone number format (must be E.164: +1234567890)
- Review Communication Services quotas and limits
- Verify function execution succeeded in logs

**Function deployment failed**:
- Ensure Azure Functions Core Tools v4 is installed
- Verify Node.js 20 is available
- Check Function App configuration and app settings
- Review deployment logs for specific errors

**Permission errors**:
- Verify account has required Azure RBAC roles
- Check Communication Services resource permissions
- Ensure Function App managed identity is configured
- Review subscription and resource group access

### Debug Commands

```bash
# Check Communication Services status
az communication list --resource-group <resource-group>

# Verify phone number status
az communication phonenumber list \
    --resource-group <resource-group> \
    --communication-service <acs-name>

# Check Function App configuration
az functionapp config show \
    --name <function-app-name> \
    --resource-group <resource-group>

# View recent Function executions
az functionapp logs tail \
    --name <function-app-name> \
    --resource-group <resource-group>
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name rg-sms-notifications --yes --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all infrastructure
terraform destroy -var="environment_name=demo" \
                  -var="location=eastus"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm resource deletion when prompted
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
az group show --name rg-sms-notifications --query "properties.provisioningState"

# Check for any remaining Communication Services resources
az communication list --query "[].{name:name, resourceGroup:resourceGroup}"
```

## Customization

### Environment-Specific Deployments

Create parameter files for different environments:

```bash
# Production parameters
cat > bicep/prod.parameters.json << EOF
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environmentName": {"value": "prod"},
    "location": {"value": "eastus2"},
    "enableApplicationInsights": {"value": true},
    "phoneNumberAreaCode": {"value": "888"}
  }
}
EOF

# Deploy with environment-specific parameters
az deployment group create \
    --resource-group rg-sms-notifications-prod \
    --template-file bicep/main.bicep \
    --parameters @bicep/prod.parameters.json
```

### Function Customization

Extend the SMS function with additional features:

- Message templates and personalization
- Delivery status tracking
- Rate limiting and throttling
- Multi-language support
- Integration with business systems

### Infrastructure Extensions

- Add Azure Logic Apps for workflow orchestration
- Integrate with Event Grid for event-driven messaging
- Implement Azure Service Bus for reliable message queuing
- Add Azure API Management for API governance

## Integration Examples

### Power Platform Integration

```javascript
// Power Automate HTTP request to SMS function
{
  "method": "POST",
  "uri": "https://your-function-app.azurewebsites.net/api/sendSMS?code=your-function-key",
  "headers": {
    "Content-Type": "application/json"
  },
  "body": {
    "to": "@{triggerBody()['phoneNumber']}",
    "message": "@{concat('Hello ', triggerBody()['customerName'], ', your order #', triggerBody()['orderNumber'], ' has been confirmed!')}"
  }
}
```

### Logic Apps Integration

```json
{
  "type": "Http",
  "inputs": {
    "method": "POST",
    "uri": "https://your-function-app.azurewebsites.net/api/sendSMS",
    "headers": {
      "Content-Type": "application/json"
    },
    "body": {
      "to": "@variables('customerPhone')",
      "message": "@variables('notificationMessage')"
    },
    "authentication": {
      "type": "Raw",
      "value": "your-function-key"
    }
  }
}
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for implementation details
2. Consult Azure Communication Services documentation for SMS-specific issues
3. Check Azure Functions documentation for serverless troubleshooting
4. Review Azure CLI documentation for deployment issues

### Useful Documentation Links

- [Azure Communication Services SMS Overview](https://docs.microsoft.com/en-us/azure/communication-services/concepts/sms/concepts)
- [Azure Functions v4 Programming Model](https://docs.microsoft.com/en-us/azure/azure-functions/functions-reference-node?pivots=nodejs-model-v4)
- [Bicep Language Reference](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Toll-Free Verification Process](https://docs.microsoft.com/en-us/azure/communication-services/quickstarts/sms/apply-for-toll-free-verification)

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Azure Well-Architected Framework principles
3. Update documentation for any configuration changes
4. Ensure security best practices are maintained
5. Validate cost implications of modifications