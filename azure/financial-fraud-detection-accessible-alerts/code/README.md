# Infrastructure as Code for Financial Fraud Detection with Accessible Alert Summaries

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Financial Fraud Detection with Accessible Alert Summaries".

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with Cognitive Services contributor permissions
- Appropriate permissions for resource creation (Contributor role on subscription/resource group)
- For Terraform: Terraform v1.0 or later installed
- For Bicep: Azure CLI with Bicep extension installed

> **Note**: Azure AI Metrics Advisor will be retired on October 1, 2026. Consider migrating to Azure AI Anomaly Detector for new implementations.

## Quick Start

### Using Bicep

```bash
# Navigate to bicep directory
cd bicep/

# Create resource group
az group create \
    --name rg-fraud-detection \
    --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-fraud-detection \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters environmentName=demo

# View deployment outputs
az deployment group show \
    --resource-group rg-fraud-detection \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure changes
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters:
# - Resource group name
# - Location (default: eastus)
# - Environment name (default: demo)
```

## Architecture Overview

This IaC deploys a complete financial fraud detection system with the following Azure resources:

### Core AI Services
- **Azure AI Metrics Advisor**: Real-time transaction anomaly detection with time-series analysis
- **Azure AI Immersive Reader**: Accessible fraud alert summaries with multilingual support

### Orchestration and Processing
- **Azure Logic Apps**: Serverless workflow orchestration for end-to-end fraud processing
- **Azure Storage Account**: Secure data storage with transaction-data and fraud-alerts containers

### Monitoring and Observability
- **Azure Log Analytics Workspace**: Centralized logging and monitoring
- **Azure Monitor Alert Rules**: Automated alerting for system health and failures

### Security and Compliance
- **Managed Identities**: Secure service-to-service authentication
- **Network Security**: Private endpoints and secure transfer enforcement
- **Data Encryption**: At-rest and in-transit encryption for all resources

## Resource Configuration

### Azure AI Services Configuration

```bash
# Metrics Advisor - F0 (free) tier for development
Kind: MetricsAdvisor
SKU: F0
Custom Domain: Enabled with unique suffix

# Immersive Reader - F0 (free) tier for development  
Kind: ImmersiveReader
SKU: F0
Custom Domain: Enabled with unique suffix
```

### Storage Account Configuration

```bash
# Performance and Replication
Performance Tier: Standard
Replication: Locally Redundant Storage (LRS)
Containers: transaction-data, fraud-alerts
Security: Public access blocked, HTTPS required
```

### Logic Apps Workflow Configuration

```bash
# Workflow Configuration
Trigger: Manual HTTP trigger
Integration: Azure AI services for processing
Monitoring: Application Insights enabled
Authentication: Managed Identity
```

## Customization

### Variables and Parameters

All implementations support the following customizable parameters:

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `location` | Azure region for deployment | `eastus` | Any Azure region |
| `environmentName` | Environment suffix for resource naming | `demo` | dev, test, prod |
| `resourceGroupName` | Target resource group name | Generated | Custom name |
| `skuName` | Pricing tier for AI services | `F0` | F0, S0, S1, S2 |
| `storageAccountSku` | Storage account performance tier | `Standard_LRS` | Standard_LRS, Standard_GRS |

### Bicep Parameters

```bash
# Deploy with custom parameters
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters location=westus2 \
    --parameters environmentName=prod \
    --parameters skuName=S0
```

### Terraform Variables

```bash
# Create terraform.tfvars file
cat > terraform.tfvars << 'EOF'
location = "westus2"
environment_name = "prod"
sku_name = "S0"
storage_account_sku = "Standard_GRS"
EOF

# Apply with custom variables
terraform apply -var-file="terraform.tfvars"
```

### Bash Script Environment Variables

```bash
# Set environment variables before running deploy.sh
export AZURE_LOCATION="westus2"
export ENVIRONMENT_NAME="prod"
export SKU_NAME="S0"

./scripts/deploy.sh
```

## Security Considerations

### Network Security
- Storage accounts configured with secure transfer required
- Private endpoints supported for enhanced security
- Network access restrictions through subnet integration

### Identity and Access Management
- Managed identities enabled for all services
- Minimal required permissions using RBAC
- Service-to-service authentication without stored credentials

### Data Protection
- Encryption at rest enabled for all storage resources
- Encryption in transit enforced for all communications
- Azure Key Vault integration available for advanced key management

## Monitoring and Logging

### Built-in Monitoring

The deployment includes comprehensive monitoring:

- Azure Monitor integration for all services
- Application Insights for Logic Apps performance tracking
- Custom metrics for fraud detection accuracy and response times

### Log Analytics Queries

Common queries for monitoring the fraud detection system:

```kql
// Logic App execution failures
AzureDiagnostics
| where ResourceType == "MICROSOFT.LOGIC/WORKFLOWS"
| where status_s == "Failed"
| summarize count() by bin(TimeGenerated, 1h)

// Metrics Advisor anomaly detection rate
AzureDiagnostics
| where ResourceType == "MICROSOFT.COGNITIVESERVICES/ACCOUNTS"
| where OperationName contains "Anomaly"
| summarize count() by bin(TimeGenerated, 1h)

// Immersive Reader accessibility usage
AzureDiagnostics
| where ResourceType == "MICROSOFT.COGNITIVESERVICES/ACCOUNTS"
| where OperationName contains "ImmersiveReader"
| summarize count() by bin(TimeGenerated, 1h)
```

### Alerting Rules

Pre-configured alert rules monitor:

- Logic App execution failures (threshold: >5 failures in 5 minutes)
- Cognitive Services API errors (threshold: >10 errors in 5 minutes)
- Storage account availability (threshold: <99% uptime)
- Fraud detection processing latency (threshold: >30 seconds)

## Cost Optimization

### Pricing Tiers

| Environment | AI Services | Storage | Estimated Monthly Cost |
|-------------|-------------|---------|----------------------|
| Development | F0 (free) | Standard_LRS | $10-20 |
| Production | S0 | Standard_GRS | $100-200 |
| Enterprise | Custom | Premium + lifecycle | $500+ |

### Cost Monitoring

```bash
# View estimated costs
az consumption budget list \
    --resource-group <your-resource-group>

# Set up budget alerts
az consumption budget create \
    --resource-group <your-resource-group> \
    --budget-name fraud-detection-budget \
    --amount 100 \
    --time-grain Monthly
```

## Cleanup

### Using Bicep

```bash
# Delete the deployment and resources
az group delete \
    --name <your-resource-group> \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# - List all resources to be deleted
# - Prompt for confirmation
# - Delete resources in proper order
# - Verify deletion completion
```

## Troubleshooting

### Common Issues

1. **Resource naming conflicts**: Ensure unique suffixes for global resources
2. **Permission issues**: Verify Contributor role on target resource group
3. **Region availability**: Check service availability in target region
4. **Quota limits**: Verify subscription quotas for Cognitive Services

### Debug Commands

```bash
# Check resource deployment status
az deployment group show \
    --resource-group <your-resource-group> \
    --name main

# View resource group contents
az resource list \
    --resource-group <your-resource-group> \
    --output table

# Check Logic App run history
az logic workflow list-runs \
    --resource-group <your-resource-group> \
    --name <logic-app-name>

# Test AI services connectivity
az cognitiveservices account keys list \
    --resource-group <your-resource-group> \
    --name <service-name>
```

### Validation Steps

After deployment, validate the fraud detection system:

1. **Verify AI Services**: Check Metrics Advisor and Immersive Reader endpoints
2. **Test Storage**: Confirm containers are created and accessible
3. **Validate Logic Apps**: Run a test workflow execution
4. **Check Monitoring**: Verify logs appear in Log Analytics
5. **Test Alerts**: Trigger test alerts to validate notification flow

## Advanced Configuration

### Multi-Region Deployment

For production environments, consider deploying across multiple regions:

```bash
# Deploy to multiple regions using Terraform
terraform apply \
    -var="primary_location=eastus" \
    -var="secondary_location=westus2" \
    -var="enable_multi_region=true"
```

### Custom Domain Configuration

```bash
# Configure custom domain for Cognitive Services
az cognitiveservices account create \
    --custom-domain "fraud-detection-company" \
    --kind MetricsAdvisor \
    --location eastus \
    --name fraud-detection-metrics \
    --resource-group <your-resource-group>
```

### Integration with Existing Systems

- **Azure Sentinel**: For advanced security monitoring and SIEM integration
- **Power BI**: For fraud detection analytics dashboards and reporting
- **Microsoft Teams**: For real-time alert notifications and collaboration
- **Azure Functions**: For custom processing logic and workflow extensions

## Performance Optimization

### Logic Apps Performance

- Enable Application Insights for detailed performance metrics
- Use parallel processing for batch fraud detection operations
- Implement circuit breaker patterns for external API calls
- Configure connection pooling for high-throughput scenarios

### Storage Performance

- Use Premium storage for high-throughput fraud detection scenarios
- Implement blob lifecycle policies for cost optimization
- Enable soft delete for data protection and recovery
- Configure appropriate redundancy levels based on compliance requirements

## Compliance and Governance

### Azure Policy Integration

Apply governance policies for:

- Resource tagging requirements for cost allocation
- Security configuration standards for financial services
- Cost management controls and spending limits
- Compliance with industry regulations (SOX, PCI-DSS, etc.)

### Audit Logging

- Enable Azure Activity Log for all resource changes
- Configure diagnostic settings for detailed service logs
- Implement log forwarding to SIEM systems
- Maintain audit trails for regulatory compliance

## Support

For issues with this infrastructure code, refer to:

1. The original recipe documentation in the parent directory
2. Azure service documentation:
   - [Azure AI Metrics Advisor Documentation](https://learn.microsoft.com/en-us/azure/ai-services/metrics-advisor/)
   - [Azure AI Immersive Reader Documentation](https://learn.microsoft.com/en-us/azure/ai-services/immersive-reader/)
   - [Azure Logic Apps Documentation](https://learn.microsoft.com/en-us/azure/logic-apps/)
   - [Azure Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
   - [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
3. Provider-specific troubleshooting guides
4. Azure support channels for service-specific issues

## License

This infrastructure code is provided as-is under the same license as the parent recipe repository.