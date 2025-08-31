# Azure Health Bot - Bicep Infrastructure as Code

This directory contains Bicep templates for deploying the "Simple Healthcare Chatbot with Azure Health Bot" recipe infrastructure.

## Overview

This template deploys:
- Azure Health Bot service instance with HIPAA compliance features
- Log Analytics Workspace for audit trails and monitoring (optional)
- Application Insights for performance telemetry (optional)
- Proper tagging and naming conventions for healthcare environments

## Prerequisites

- Azure CLI installed and configured (version 2.40.0 or later)
- Azure subscription with permissions to create Health Bot resources
- Bicep CLI installed (included with Azure CLI 2.20.0+)
- Resource group created or permissions to create one

## Quick Start

### 1. Customize Parameters

Edit the `parameters.json` file to match your organization's requirements:

```json
{
  "healthBotName": {
    "value": "your-healthbot-name"
  },
  "organizationName": {
    "value": "your-organization"
  },
  "environment": {
    "value": "prod"
  }
}
```

### 2. Deploy Infrastructure

```bash
# Create resource group (if needed)
az group create \
    --name rg-healthbot-prod \
    --location eastus

# Deploy the template
az deployment group create \
    --resource-group rg-healthbot-prod \
    --template-file main.bicep \
    --parameters @parameters.json
```

### 3. Alternative: Deploy with inline parameters

```bash
az deployment group create \
    --resource-group rg-healthbot-demo \
    --template-file main.bicep \
    --parameters \
        healthBotName=healthbot-$(date +%s) \
        location=eastus \
        healthBotSku=F0 \
        environment=demo \
        organizationName=my-healthcare-org
```

## Template Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `healthBotName` | string | *required* | Name of the Azure Health Bot instance |
| `location` | string | `resourceGroup().location` | Azure region for deployment |
| `healthBotSku` | string | `F0` | Service tier (F0=Free, S1=Standard) |
| `environment` | string | `demo` | Environment tag (dev/test/prod/demo) |
| `purpose` | string | `healthcare-chatbot` | Purpose tag for resource identification |
| `organizationName` | string | `healthcare-org` | Organization name for tagging |
| `enableAuditLogging` | bool | `true` | Enable Log Analytics and Application Insights |
| `dataRetentionDays` | int | `90` | Data retention period (30-2555 days) |

## Template Outputs

The template provides the following outputs:

- `healthBotId`: Resource ID of the Health Bot
- `healthBotName`: Name of the deployed Health Bot
- `managementPortalUrl`: URL to access the Health Bot management portal
- `webChatEndpoint`: Endpoint URL for web chat integration
- `logAnalyticsWorkspaceId`: Log Analytics workspace ID (if enabled)
- `applicationInsightsConnectionString`: Application Insights connection string

## Post-Deployment Configuration

After deployment, access the Health Bot Management Portal to:

1. **Configure Healthcare Scenarios**:
   - Enable built-in symptom checker
   - Configure disease information lookup
   - Set up medication guidance scenarios

2. **Setup Communication Channels**:
   - Enable web chat for website integration
   - Configure Microsoft Teams integration
   - Set up SMS capabilities if needed

3. **Customize Branding**:
   - Upload organization logo
   - Configure welcome messages
   - Set up custom disclaimers

4. **Review Compliance Settings**:
   - Verify HIPAA compliance configuration
   - Review data retention policies
   - Configure audit logging

## SKU Pricing Information

| SKU | Description | Price (USD/month) | Use Case |
|-----|-------------|-------------------|----------|
| F0  | Free tier   | $0 | Development, testing, proof of concept |
| S1  | Standard    | ~$500 | Production healthcare environments |

> **Note**: Free tier (F0) includes limited transactions. Production deployments should use S1 tier.

## Security and Compliance

This template includes:

- **HIPAA Compliance**: Health Bot service is HIPAA-compliant by default
- **Data Encryption**: All data encrypted at rest and in transit
- **Audit Trails**: Optional Log Analytics for compliance monitoring
- **Access Controls**: Integration with Azure Active Directory
- **Data Retention**: Configurable retention policies

## Monitoring and Observability

When `enableAuditLogging` is set to `true`, the template deploys:

- **Log Analytics Workspace**: Centralized logging for compliance
- **Application Insights**: Performance monitoring and telemetry
- **Daily Quota**: Cost protection with 1GB daily limit

## Cleanup

To remove all deployed resources:

```bash
# Delete the resource group (removes all contained resources)
az group delete \
    --name rg-healthbot-demo \
    --yes \
    --no-wait
```

Or delete individual resources:

```bash
# Get deployment outputs
HEALTHBOT_NAME=$(az deployment group show \
    --resource-group rg-healthbot-demo \
    --name main \
    --query 'properties.outputs.healthBotName.value' \
    --output tsv)

# Delete Health Bot
az healthbot delete \
    --name $HEALTHBOT_NAME \
    --resource-group rg-healthbot-demo \
    --yes
```

## Troubleshooting

### Common Issues

1. **Health Bot creation fails**:
   - Verify Health Bot service is available in your region
   - Check subscription limits for Health Bot instances
   - Ensure proper permissions for resource creation

2. **Template validation errors**:
   - Update Bicep CLI to latest version: `az bicep upgrade`
   - Verify parameter values match allowed constraints
   - Check Azure resource provider registration

3. **Access denied errors**:
   - Verify you have Contributor role on the resource group
   - Check Azure AD permissions for Health Bot service
   - Ensure subscription is registered for Microsoft.HealthBot provider

### Useful Commands

```bash
# Check Bicep version
az bicep version

# Validate template syntax
az deployment group validate \
    --resource-group rg-healthbot-demo \
    --template-file main.bicep \
    --parameters @parameters.json

# Preview template changes
az deployment group what-if \
    --resource-group rg-healthbot-demo \
    --template-file main.bicep \
    --parameters @parameters.json

# Check deployment status
az deployment group show \
    --resource-group rg-healthbot-demo \
    --name main
```

## Best Practices

1. **Naming Conventions**: Use consistent naming with environment and purpose
2. **Resource Tagging**: Apply comprehensive tags for cost management
3. **Security**: Enable audit logging for production environments
4. **Cost Management**: Monitor usage and adjust SKU as needed
5. **Backup**: Export Health Bot configuration regularly
6. **Testing**: Test scenarios in non-production environments first

## Additional Resources

- [Azure Health Bot Documentation](https://learn.microsoft.com/en-us/azure/health-bot/)
- [Azure Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Microsoft HIPAA Compliance](https://learn.microsoft.com/en-us/compliance/regulatory/offering-hipaa-hitech)
- [Health Bot Management Portal](https://healthbot.microsoft.com/)

## Support

For issues with this template:
1. Review the troubleshooting section above
2. Check Azure Health Bot service status
3. Consult the original recipe documentation
4. Contact your Azure support team for service-specific issues