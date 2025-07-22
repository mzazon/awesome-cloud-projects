# Infrastructure as Code for Enterprise MLflow Lifecycle Management with Containers

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise MLflow Lifecycle Management with Containers".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts for step-by-step resource creation

## Prerequisites

### General Requirements
- Azure CLI v2.45.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Azure Machine Learning
  - Azure Container Apps
  - Azure Container Registry
  - Azure Monitor and Log Analytics
  - Azure Storage
  - Azure Key Vault
- Basic understanding of machine learning workflows and containerization
- Estimated cost: $50-100 for a full day of testing

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension installed
- PowerShell or Bash shell

#### For Terraform
- Terraform v1.0+ installed
- Azure CLI authenticated with appropriate permissions

#### For Bash Scripts
- Docker installed for building container images
- Python 3.8+ with pip for MLflow dependencies
- curl for testing endpoints

## Architecture Overview

This infrastructure deploys:

- **Azure Machine Learning Workspace** with built-in MLflow integration
- **Azure Container Apps Environment** for scalable model serving
- **Azure Container Registry** for storing model serving images
- **Azure Monitor & Log Analytics** for comprehensive observability
- **Azure Storage Account** for ML workspace artifacts
- **Azure Key Vault** for secrets management

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters location=eastus \
                 environmentName=mlflow-demo \
                 modelName=demo-regression-model

# Get deployment outputs
az deployment group show \
    --resource-group <your-resource-group> \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan -var="location=eastus" \
               -var="environment_name=mlflow-demo"

# Deploy infrastructure
terraform apply -var="location=eastus" \
                -var="environment_name=mlflow-demo"

# Get outputs
terraform output
```

### Using Bash Scripts (Step-by-Step)

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-mlflow-lifecycle-demo"
export LOCATION="eastus"

# Deploy infrastructure
./scripts/deploy.sh

# Follow the interactive prompts for configuration
```

## Post-Deployment Setup

After infrastructure deployment, complete these steps:

### 1. Train and Register a Model

```bash
# Install required Python packages
pip install mlflow azureml-mlflow scikit-learn pandas numpy

# Create and run model training script
python - << 'EOF'
import mlflow
import mlflow.sklearn
import numpy as np
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_squared_error, r2_score
from azureml.core import Workspace

# Connect to Azure ML workspace
ws = Workspace.from_config() # Requires .azureml/config.json
mlflow.set_tracking_uri(ws.get_mlflow_tracking_uri())
mlflow.set_experiment("model-lifecycle-demo")

# Generate sample data and train model
np.random.seed(42)
X = np.random.randn(1000, 4)
y = X[:, 0] + 2 * X[:, 1] - X[:, 2] + 0.5 * X[:, 3] + np.random.randn(1000) * 0.1
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

with mlflow.start_run():
    model = RandomForestRegressor(n_estimators=100, random_state=42)
    model.fit(X_train, y_train)
    y_pred = model.predict(X_test)
    
    mlflow.log_param("n_estimators", 100)
    mlflow.log_metric("mse", mean_squared_error(y_test, y_pred))
    mlflow.log_metric("r2_score", r2_score(y_test, y_pred))
    
    mlflow.sklearn.log_model(
        model, 
        "model",
        registered_model_name="demo-regression-model",
        input_example=X_train[:5],
        signature=mlflow.models.infer_signature(X_train, y_train)
    )
    
print("✅ Model trained and registered successfully")
EOF
```

### 2. Build and Deploy Model Serving Container

```bash
# Get deployment outputs (adjust based on your IaC choice)
CONTAINER_REGISTRY_NAME=$(terraform output -raw container_registry_name)
CONTAINER_APP_NAME=$(terraform output -raw container_app_name)
RESOURCE_GROUP=$(terraform output -raw resource_group_name)

# Build model serving container (requires Docker)
cd model-serving/
docker build -t ${CONTAINER_REGISTRY_NAME}.azurecr.io/model-serving:latest .

# Push to Azure Container Registry
az acr login --name ${CONTAINER_REGISTRY_NAME}
docker push ${CONTAINER_REGISTRY_NAME}.azurecr.io/model-serving:latest

# Update container app with new image
az containerapp update \
    --name ${CONTAINER_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --image ${CONTAINER_REGISTRY_NAME}.azurecr.io/model-serving:latest
```

### 3. Test Model Serving Endpoint

```bash
# Get container app URL
CONTAINER_APP_URL=$(az containerapp show \
    --name ${CONTAINER_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query properties.configuration.ingress.fqdn --output tsv)

# Test health endpoint
curl -X GET https://${CONTAINER_APP_URL}/health

# Test model prediction
curl -X POST https://${CONTAINER_APP_URL}/predict \
    -H "Content-Type: application/json" \
    -d '{"features": [1.0, 2.0, -1.0, 0.5]}'

# Check model information
curl -X GET https://${CONTAINER_APP_URL}/model-info
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `environmentName` | Prefix for resource names | `mlflow` | Yes |
| `modelName` | Name for the MLflow model | `demo-model` | No |
| `containerAppMinReplicas` | Minimum container app replicas | `1` | No |
| `containerAppMaxReplicas` | Maximum container app replicas | `10` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `environment_name` | Prefix for resource names | `mlflow` | Yes |
| `resource_group_name` | Resource group name | `rg-mlflow-lifecycle` | No |
| `model_name` | Name for the MLflow model | `demo-model` | No |
| `container_app_cpu` | CPU allocation for container app | `1.0` | No |
| `container_app_memory` | Memory allocation for container app | `2.0Gi` | No |

### Bash Script Environment Variables

Set these before running `deploy.sh`:

```bash
export RESOURCE_GROUP="rg-mlflow-lifecycle-demo"
export LOCATION="eastus"
export ML_WORKSPACE_NAME="mlws-demo"
export CONTAINER_APP_NAME="ca-model-serve-demo"
export STORAGE_ACCOUNT_NAME="stmlflowdemo"
export KEY_VAULT_NAME="kv-mlflow-demo"
export CONTAINER_REGISTRY_NAME="acrmlflowdemo"
```

## Monitoring and Observability

The infrastructure includes comprehensive monitoring:

- **Azure Monitor**: Performance metrics and alerts
- **Log Analytics**: Centralized logging for all components
- **Application Insights**: Deep application performance monitoring
- **Container App Metrics**: Scaling and performance metrics

### View Monitoring Data

```bash
# View container app metrics
az monitor metrics list \
    --resource "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/containerApps/${CONTAINER_APP_NAME}" \
    --metric Replicas,Requests

# Query application logs
az monitor log-analytics query \
    --workspace ${LOG_ANALYTICS_WORKSPACE_ID} \
    --analytics-query "ContainerAppConsoleLogs_CL | where TimeGenerated > ago(1h) | limit 100"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name <your-resource-group> --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="location=eastus" \
                  -var="environment_name=mlflow-demo"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Model Loading Errors**: Ensure the model is properly registered in Azure ML registry
2. **Container App Not Starting**: Check container logs for Python dependency issues
3. **Authentication Errors**: Verify Azure CLI is logged in with appropriate permissions
4. **Resource Naming Conflicts**: Use unique environment names to avoid conflicts

### Debug Commands

```bash
# Check container app logs
az containerapp logs show \
    --name ${CONTAINER_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --follow

# Check ML workspace status
az ml workspace show \
    --name ${ML_WORKSPACE_NAME} \
    --resource-group ${RESOURCE_GROUP}

# Verify container registry access
az acr repository list --name ${CONTAINER_REGISTRY_NAME}
```

## Security Considerations

- **Key Vault Integration**: Secrets are stored in Azure Key Vault
- **Private Endpoints**: Consider enabling private endpoints for production
- **RBAC**: Use role-based access control for fine-grained permissions
- **Network Security**: Container apps are deployed with secure ingress configuration
- **Image Scanning**: Enable vulnerability scanning in Azure Container Registry

## Cost Optimization

- **Auto-scaling**: Container apps scale to zero when not in use
- **Reserved Instances**: Consider reserved capacity for production workloads
- **Storage Tiers**: Use appropriate storage tiers for different data types
- **Resource Tagging**: All resources are tagged for cost tracking

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for detailed explanations
2. Review Azure service documentation for specific configuration options
3. Use Azure Support for platform-specific issues
4. Check the troubleshooting section above for common problems

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Follow Azure best practices and security guidelines
3. Update documentation for any new parameters or features
4. Ensure backwards compatibility where possible