# Azure Bicep Template for Financial Fraud Detection Solution

This directory contains Azure Bicep Infrastructure as Code (IaC) templates for deploying a comprehensive financial fraud detection solution that combines Azure AI Metrics Advisor with Azure AI Immersive Reader to create intelligent, accessible fraud detection alerts.

## 🏗️ Architecture Overview

The solution deploys the following Azure resources:

### Core AI Services
- **Azure AI Metrics Advisor** - Real-time transaction anomaly detection
- **Azure AI Immersive Reader** - Accessible fraud alert generation

### Orchestration & Storage
- **Azure Logic Apps** - Workflow orchestration between services
- **Azure Storage Account** - Transaction data and fraud alert storage
- **Azure Key Vault** - Secure storage of API keys and secrets

### Monitoring & Alerting
- **Azure Monitor Log Analytics** - Centralized logging and monitoring
- **Azure Application Insights** - Application performance monitoring
- **Azure Monitor Alerts** - Automated alerting for service failures
- **Azure Monitor Action Groups** - Multi-channel alert notifications

## 📁 Files Included

| File | Description |
|------|-------------|
| `main.bicep` | Main Bicep template defining all infrastructure resources |
| `parameters.json` | Example parameter values for deployment |
| `deploy.sh` | Automated deployment script with validation |
| `cleanup.sh` | Complete resource cleanup script |
| `README.md` | This documentation file |

## 🚀 Quick Start

### Prerequisites

- Azure CLI installed and authenticated
- Bicep CLI installed (or will be installed automatically)
- Azure subscription with appropriate permissions
- Bash shell environment (Windows users can use WSL or Git Bash)

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd azure/implementing-intelligent-financial-fraud-detection-with-azure-ai-metrics-advisor-and-azure-ai-immersive-reader/code/bicep
```

### 2. Deploy Using Script (Recommended)

```bash
# Make scripts executable
chmod +x deploy.sh cleanup.sh

# Deploy with default parameters
./deploy.sh

# Deploy with custom parameters
./deploy.sh "my-resource-group" "eastus" "prod"
```

### 3. Deploy Using Azure CLI

```bash
# Create resource group
az group create --name rg-fraud-detection-dev --location eastus

# Deploy template
az deployment group create \
    --resource-group rg-fraud-detection-dev \
    --template-file main.bicep \
    --parameters @parameters.json
```

## ⚙️ Configuration Parameters

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `location` | Azure region for deployment | `eastus` |
| `environment` | Environment name | `dev`, `test`, `prod` |
| `alertEmailAddress` | Email for fraud alerts | `compliance@company.com` |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `resourceSuffix` | Auto-generated | Unique suffix for resource names |
| `metricsAdvisorSku` | `F0` | Azure AI Metrics Advisor pricing tier |
| `immersiveReaderSku` | `F0` | Azure AI Immersive Reader pricing tier |
| `storageAccountSku` | `Standard_LRS` | Storage account redundancy |
| `logAnalyticsRetentionInDays` | `30` | Log retention period |
| `enableMonitoring` | `true` | Enable monitoring and alerting |

### Example Parameter Customization

```json
{
  "location": {
    "value": "westus2"
  },
  "environment": {
    "value": "production"
  },
  "metricsAdvisorSku": {
    "value": "S0"
  },
  "immersiveReaderSku": {
    "value": "S0"
  },
  "storageAccountSku": {
    "value": "Standard_GRS"
  },
  "alertEmailAddress": {
    "value": "fraud-alerts@mycompany.com"
  },
  "logAnalyticsRetentionInDays": {
    "value": 90
  },
  "tags": {
    "value": {
      "Environment": "production",
      "Project": "FraudDetection",
      "CostCenter": "Security",
      "Owner": "ComplianceTeam"
    }
  }
}
```

## 📊 Deployment Outputs

After successful deployment, the template provides these outputs:

### Service Endpoints
- `metricsAdvisorEndpoint` - Azure AI Metrics Advisor API endpoint
- `immersiveReaderEndpoint` - Azure AI Immersive Reader API endpoint
- `logicAppTriggerUrl` - Logic App webhook URL for fraud alerts

### Resource Names
- `storageAccountName` - Storage account for data persistence
- `keyVaultName` - Key Vault for secure secret storage
- `logAnalyticsWorkspaceName` - Log Analytics workspace for monitoring

### Connection Information
- `connectionInfo` - Comprehensive object with all connection details

## 🔧 Post-Deployment Configuration

### 1. Configure Logic App Connections

The Logic App requires API connections for full functionality:

```bash
# Get resource group and Logic App name from outputs
RESOURCE_GROUP="rg-fraud-detection-dev"
LOGIC_APP_NAME="la-fraud-workflow-xyz123"

# Create Office 365 connection
az resource create \
    --resource-group $RESOURCE_GROUP \
    --resource-type Microsoft.Web/connections \
    --name office365-connection \
    --properties '{
        "displayName": "Office 365 Connection",
        "api": {
            "id": "/subscriptions/[subscription-id]/providers/Microsoft.Web/locations/eastus/managedApis/office365"
        }
    }'

# Create Azure Blob Storage connection
az resource create \
    --resource-group $RESOURCE_GROUP \
    --resource-type Microsoft.Web/connections \
    --name azureblob-connection \
    --properties '{
        "displayName": "Azure Blob Storage Connection",
        "api": {
            "id": "/subscriptions/[subscription-id]/providers/Microsoft.Web/locations/eastus/managedApis/azureblob"
        }
    }'
```

### 2. Test Fraud Detection Workflow

```bash
# Get Logic App trigger URL from deployment outputs
TRIGGER_URL="https://prod-xx.eastus.logic.azure.com:443/workflows/..."

# Send test fraud alert
curl -X POST "$TRIGGER_URL" \
    -H "Content-Type: application/json" \
    -d '{
        "alertId": "test-alert-001",
        "severity": "high",
        "anomalyData": {
            "description": "Transaction volume exceeded normal patterns by 250%",
            "affectedMetrics": ["transaction_volume", "average_amount"],
            "confidenceScore": 0.89,
            "timestamp": "2025-07-12T14:30:00Z"
        }
    }'
```

### 3. Configure Metrics Advisor Data Feeds

```bash
# Get Metrics Advisor endpoint and key
METRICS_ADVISOR_ENDPOINT="https://ma-fraud-xyz123.cognitiveservices.azure.com"
METRICS_ADVISOR_KEY=$(az keyvault secret show \
    --vault-name kv-fraud-xyz123 \
    --name metrics-advisor-key \
    --query value -o tsv)

# Configure data feed (example using REST API)
curl -X POST "$METRICS_ADVISOR_ENDPOINT/metricsadvisor/v1.0/dataFeeds" \
    -H "Ocp-Apim-Subscription-Key: $METRICS_ADVISOR_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "dataFeedName": "TransactionDataFeed",
        "dataSourceType": "AzureBlob",
        "dataSourceParameter": {
            "connectionString": "DefaultEndpointsProtocol=https;AccountName=...",
            "container": "transaction-data",
            "blobTemplate": "transactions-%Y-%m-%d.json"
        },
        "granularityName": "Daily",
        "schema": {
            "metrics": [
                {
                    "metricName": "transaction_volume",
                    "metricDisplayName": "Transaction Volume",
                    "metricDescription": "Daily transaction count"
                },
                {
                    "metricName": "average_transaction_amount",
                    "metricDisplayName": "Average Transaction Amount",
                    "metricDescription": "Daily average transaction amount"
                }
            ],
            "dimensions": [
                {
                    "dimensionName": "region",
                    "dimensionDisplayName": "Region"
                },
                {
                    "dimensionName": "account_type",
                    "dimensionDisplayName": "Account Type"
                }
            ]
        }
    }'
```

## 🔍 Monitoring and Troubleshooting

### View Deployment Status

```bash
# Check deployment status
az deployment group show \
    --resource-group rg-fraud-detection-dev \
    --name fraud-detection-deployment-[timestamp]

# View deployment operations
az deployment operation group list \
    --resource-group rg-fraud-detection-dev \
    --name fraud-detection-deployment-[timestamp]
```

### Monitor Service Health

```bash
# Check Logic App run history
az logic workflow list-runs \
    --resource-group rg-fraud-detection-dev \
    --name la-fraud-workflow-xyz123

# View Log Analytics queries
az monitor log-analytics query \
    --workspace law-fraud-monitoring-xyz123 \
    --analytics-query "AzureDiagnostics | where ResourceProvider == 'MICROSOFT.COGNITIVESERVICES' | summarize count() by bin(TimeGenerated, 1h)"
```

### Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| Logic App connections not authorized | Manually authorize connections in Azure Portal |
| Metrics Advisor data feed errors | Verify storage account permissions and data format |
| Email alerts not sending | Check Office 365 connection and email address |
| High costs | Review SKU selection and enable monitoring alerts |

## 🧹 Cleanup

### Complete Resource Removal

```bash
# Remove all resources
./cleanup.sh rg-fraud-detection-dev
```

### Selective Resource Cleanup

```bash
# Delete specific resources
az cognitiveservices account delete \
    --name ma-fraud-xyz123 \
    --resource-group rg-fraud-detection-dev

az logic workflow delete \
    --name la-fraud-workflow-xyz123 \
    --resource-group rg-fraud-detection-dev
```

## 💰 Cost Considerations

### Estimated Monthly Costs (F0 SKU)

| Service | F0 Tier | S0 Tier | Notes |
|---------|---------|---------|-------|
| Azure AI Metrics Advisor | Free | $500+ | F0: 10 data feeds, 100 time series |
| Azure AI Immersive Reader | Free | $1 per 1k transactions | F0: 3M characters/month |
| Logic Apps | $0.000025 per action | | Pay-per-execution |
| Storage Account | $0.024 per GB | | Based on actual usage |
| Log Analytics | $2.30 per GB | | 5GB free per month |

### Cost Optimization Tips

1. **Use F0 SKUs** for development and testing
2. **Enable auto-shutdown** for non-production environments
3. **Monitor storage usage** and implement lifecycle policies
4. **Set up cost alerts** using Azure Cost Management
5. **Review Log Analytics retention** policies

## 🔒 Security Best Practices

### Network Security
- All services use HTTPS endpoints
- Storage accounts block public access
- Key Vault uses RBAC authorization

### Access Control
- Managed identities for service-to-service authentication
- Role-based access control (RBAC) for human access
- Principle of least privilege

### Data Protection
- Data encryption at rest and in transit
- Secure storage of API keys in Key Vault
- Regular security monitoring and alerting

## 📚 Additional Resources

### Documentation
- [Azure AI Metrics Advisor Documentation](https://docs.microsoft.com/azure/cognitive-services/metrics-advisor/)
- [Azure AI Immersive Reader Documentation](https://docs.microsoft.com/azure/cognitive-services/immersive-reader/)
- [Azure Logic Apps Documentation](https://docs.microsoft.com/azure/logic-apps/)
- [Azure Bicep Documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)

### Support
- [Azure Support](https://azure.microsoft.com/support/)
- [Stack Overflow - Azure](https://stackoverflow.com/questions/tagged/azure)
- [Microsoft Q&A - Azure](https://docs.microsoft.com/answers/topics/azure.html)

## 🤝 Contributing

This template is part of the Azure recipes collection. For improvements or bug reports, please follow the repository's contribution guidelines.

---

**Note**: This solution is designed for demonstration and development purposes. For production deployments, review and adjust security settings, SKUs, and configurations according to your organization's requirements and compliance standards.