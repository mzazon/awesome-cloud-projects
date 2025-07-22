# Infrastructure as Code for Adaptive Healthcare Chatbots with AI-Driven Personalization

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Adaptive Healthcare Chatbots with AI-Driven Personalization". This solution combines Azure Health Bot's compliant conversational AI framework with Azure Personalizer's machine learning-driven recommendation engine to create intelligent healthcare chatbots that adapt to individual patient needs while maintaining HIPAA compliance.

## Available Implementations

- **Bicep**: Azure native infrastructure as code using Microsoft's recommended IaC language
- **Terraform**: Multi-cloud infrastructure as code using HashiCorp Configuration Language
- **Scripts**: Bash deployment and cleanup scripts for complete automation

## Architecture Overview

This solution deploys the following Azure services:

- **Azure Health Bot**: HIPAA-compliant conversational AI platform with healthcare safeguards
- **Azure Personalizer**: Machine learning service for personalized content recommendations
- **Azure SQL Managed Instance**: Enterprise-grade database with healthcare compliance features
- **Azure Functions**: Serverless integration layer between Health Bot and Personalizer
- **Azure API Management**: Secure gateway with healthcare-specific policies
- **Azure Key Vault**: Secure credential and secrets management
- **Azure Virtual Network**: Secure network infrastructure for SQL Managed Instance

## Prerequisites

### General Requirements
- Azure subscription with appropriate permissions for all listed services
- Azure CLI v2.37.0 or later installed and configured
- Basic understanding of healthcare compliance requirements (HIPAA/HITECH)
- Familiarity with conversational AI and machine learning concepts

### Role-Based Access Requirements
- Contributor permissions on the target resource group
- Cognitive Services Contributor role for Azure Personalizer
- SQL DB Contributor role for Azure SQL Managed Instance
- Key Vault Contributor role for Azure Key Vault

### Healthcare Compliance Prerequisites
- Business Associate Agreement (BAA) with Microsoft for healthcare workloads
- Organizational approval for processing Protected Health Information (PHI)
- Understanding of healthcare data privacy and security requirements

### Cost Considerations
- Estimated cost: $200-400/month for development environment
- Production costs vary significantly based on usage patterns
- SQL Managed Instance is the largest cost component (4-6 hours deployment time)

## Quick Start

### Using Bicep

Deploy the complete healthcare chatbot infrastructure using Azure's native IaC language:

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-healthcare-chatbot \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters healthBotName=healthbot-demo \
    --parameters personalizerName=personalizer-demo \
    --parameters sqlManagedInstanceName=sqlmi-demo
```

### Using Terraform

Deploy using HashiCorp's infrastructure as code tool:

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

Automated deployment using Azure CLI commands:

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# Follow prompts for resource naming and configuration
```

## Deployment Parameters

### Required Parameters

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `resourceGroupName` | Name of the resource group | `rg-healthcare-chatbot` | `rg-healthcare-prod` |
| `location` | Azure region for deployment | `eastus` | `westus2` |
| `healthBotName` | Name for Azure Health Bot instance | Generated | `healthbot-prod` |
| `personalizerName` | Name for Azure Personalizer service | Generated | `personalizer-prod` |
| `sqlManagedInstanceName` | Name for SQL Managed Instance | Generated | `sqlmi-prod` |

### Optional Parameters

| Parameter | Description | Default | Notes |
|-----------|-------------|---------|-------|
| `environment` | Environment tag | `development` | `production`, `staging`, `development` |
| `sqlAdminUsername` | SQL Managed Instance admin username | `sqladmin` | Must follow Azure naming conventions |
| `enableAdvancedThreatProtection` | Enable SQL Advanced Threat Protection | `true` | Recommended for healthcare workloads |
| `personalizerSku` | Azure Personalizer pricing tier | `S0` | Use `F0` for development only |

## Healthcare Compliance Configuration

### HIPAA Compliance Features

The infrastructure is configured with healthcare-specific security features:

- **Data Encryption**: All data encrypted at rest and in transit
- **Network Isolation**: SQL Managed Instance deployed in dedicated subnet
- **Access Control**: Role-based access control (RBAC) implemented
- **Audit Logging**: Comprehensive logging for compliance reporting
- **Backup and Recovery**: Automated backup with point-in-time recovery
- **Advanced Threat Protection**: Real-time security monitoring

### Required Compliance Steps

After deployment, complete these compliance configuration steps:

1. **Configure Azure Policy**: Apply healthcare-specific compliance policies
2. **Set Up Monitoring**: Configure Azure Monitor for healthcare compliance dashboards
3. **Enable Diagnostic Logging**: Ensure all services log to compliance-approved locations
4. **Review Access Permissions**: Validate least-privilege access principles
5. **Test Backup and Recovery**: Verify data protection procedures

## Post-Deployment Configuration

### Health Bot Configuration

1. Access the Azure Health Bot management portal (URL provided in deployment outputs)
2. Configure custom scenarios for your healthcare organization
3. Import medical knowledge bases and terminology
4. Set up integration with Azure Personalizer endpoints
5. Configure healthcare disclaimers and safeguards

### Personalizer Configuration

1. Configure learning policy for healthcare content recommendations
2. Set up context features for patient demographics and preferences
3. Define action features for different types of healthcare content
4. Configure reward function for measuring recommendation effectiveness
5. Enable offline evaluation for continuous improvement

### Database Schema Setup

The deployment includes database schema creation scripts:

```sql
-- Patient interaction tracking
CREATE TABLE PatientInteractions (
    InteractionId UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    PatientId NVARCHAR(255) NOT NULL,
    ConversationId NVARCHAR(255) NOT NULL,
    ActionSelected NVARCHAR(255),
    ContextData NVARCHAR(MAX),
    RewardScore FLOAT,
    InteractionDate DATETIME2 DEFAULT GETUTCDATE()
);

-- Personalization preferences
CREATE TABLE PersonalizationPreferences (
    PreferenceId UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    PatientId NVARCHAR(255) NOT NULL,
    PreferenceType NVARCHAR(100),
    PreferenceValue NVARCHAR(MAX),
    LastUpdated DATETIME2 DEFAULT GETUTCDATE()
);
```

## Validation and Testing

### Infrastructure Validation

Verify successful deployment with these commands:

```bash
# Check Health Bot status
az healthbot show --name $HEALTH_BOT_NAME --resource-group $RESOURCE_GROUP

# Verify Personalizer endpoint
curl -X GET "$PERSONALIZER_ENDPOINT/personalizer/v1.0/configurations" \
    -H "Ocp-Apim-Subscription-Key: $PERSONALIZER_KEY"

# Test SQL Managed Instance connectivity
az sql mi show --name $SQL_MI_NAME --resource-group $RESOURCE_GROUP

# Verify Function App deployment
az functionapp show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP
```

### End-to-End Testing

Test the complete integration:

```bash
# Test personalization API
curl -X POST "https://$FUNCTION_APP_NAME.azurewebsites.net/api/GetPersonalizedContent" \
    -H "Content-Type: application/json" \
    -d '{
        "age": 45,
        "location": "suburban",
        "previousInteractions": ["symptom-checker", "appointment-scheduling"]
    }'

# Verify API Management gateway
curl -X GET "https://$APIM_NAME.azure-api.net/health" \
    -H "Ocp-Apim-Subscription-Key: $API_KEY"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name rg-healthcare-chatbot --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification

Verify all resources are properly removed:

```bash
# Check for remaining resources
az resource list --resource-group rg-healthcare-chatbot

# Verify Key Vault deletion (may be in soft-delete state)
az keyvault list-deleted --subscription $SUBSCRIPTION_ID
```

## Customization

### Environment-Specific Configurations

Modify these files for environment-specific deployments:

- **Bicep**: Update `main.bicep` parameter default values
- **Terraform**: Modify `variables.tf` default values
- **Scripts**: Edit environment variables in `deploy.sh`

### Scaling Considerations

For production deployments, consider these modifications:

1. **SQL Managed Instance**: Increase capacity and storage based on expected load
2. **Personalizer**: Use S0 tier for production workloads
3. **Function App**: Configure dedicated hosting plan for predictable performance
4. **API Management**: Use Standard or Premium tier for SLA requirements

### Security Hardening

Additional security configurations for production:

1. **Network Security Groups**: Restrict network access to healthcare networks only
2. **Private Endpoints**: Enable private connectivity for all services
3. **Azure Firewall**: Implement application-level firewall rules
4. **Conditional Access**: Require multi-factor authentication for admin access

## Monitoring and Alerting

### Healthcare-Specific Monitoring

Configure monitoring for healthcare compliance:

```bash
# Enable diagnostic settings for all services
az monitor diagnostic-settings create \
    --name "healthcare-compliance-logs" \
    --resource $RESOURCE_ID \
    --logs '[{"category": "AuditLogs", "enabled": true}]' \
    --workspace $LOG_ANALYTICS_WORKSPACE_ID
```

### Performance Monitoring

Set up key performance indicators:

- Health Bot response times
- Personalizer recommendation accuracy
- SQL Managed Instance performance metrics
- Function App execution duration and success rates

## Troubleshooting

### Common Deployment Issues

1. **SQL Managed Instance Timeout**: Deployment takes 4-6 hours; increase timeout values
2. **Health Bot Licensing**: Ensure healthcare licensing is properly configured
3. **Network Connectivity**: Verify subnet delegation for SQL Managed Instance
4. **Permission Errors**: Check Azure RBAC permissions for all services

### Healthcare Compliance Issues

1. **BAA Requirements**: Ensure Business Associate Agreement is signed
2. **Data Residency**: Verify all services are deployed in approved regions
3. **Encryption Configuration**: Confirm encryption is enabled for all data stores
4. **Access Logging**: Verify comprehensive audit logging is enabled

## Support and Documentation

### Microsoft Documentation

- [Azure Health Bot Documentation](https://docs.microsoft.com/en-us/azure/healthcare-apis/health-bot/)
- [Azure Personalizer Documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/personalizer/)
- [Azure SQL Managed Instance Documentation](https://docs.microsoft.com/en-us/azure/azure-sql/managed-instance/)
- [Azure HIPAA Compliance Guide](https://docs.microsoft.com/en-us/azure/compliance/offerings/offering-hipaa-us)

### Healthcare AI Resources

- [Azure AI for Healthcare](https://docs.microsoft.com/en-us/azure/architecture/industries/healthcare/healthcare-ai)
- [Healthcare Data Architecture Guide](https://docs.microsoft.com/en-us/azure/architecture/industries/healthcare/health-data-consortium)
- [Azure Well-Architected Framework for Healthcare](https://docs.microsoft.com/en-us/azure/architecture/framework/industries/healthcare)

### Community Support

- [Azure Health Bot Community Forum](https://techcommunity.microsoft.com/t5/azure-health-bot/bd-p/AzureHealthBot)
- [Azure AI Community](https://techcommunity.microsoft.com/t5/azure-ai/bd-p/AzureAI)
- [Healthcare Technology Solutions](https://techcommunity.microsoft.com/t5/healthcare-and-life-sciences/bd-p/HealthcareAndLifeSciences)

## Contributing

For improvements to this infrastructure code:

1. Review the original recipe documentation
2. Test changes in a development environment
3. Ensure compliance with healthcare security requirements
4. Document any architectural decisions
5. Update this README with new features or configurations

---

**Important**: This infrastructure code is designed for healthcare applications processing Protected Health Information (PHI). Ensure your organization has proper Business Associate Agreements and compliance procedures in place before deploying to production environments.