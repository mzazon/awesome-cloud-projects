# Infrastructure as Code for Production MLOps Pipelines with Kubernetes

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Production MLOps Pipelines with Kubernetes".

## Overview

This recipe implements a production-ready MLOps pipeline using Azure Kubernetes Service (AKS) for scalable container orchestration, Azure Machine Learning for model lifecycle management, Azure Container Registry for secure image storage, and Azure DevOps for end-to-end CI/CD automation. The infrastructure enables automated model training, containerization, deployment, and monitoring while maintaining enterprise-grade security and compliance standards.

## Available Implementations

- **Bicep**: Microsoft's recommended domain-specific language for Azure infrastructure
- **Terraform**: Multi-cloud infrastructure as code using HashiCorp Configuration Language
- **Scripts**: Bash deployment and cleanup scripts for direct Azure CLI usage

## Architecture Components

The infrastructure deploys the following Azure resources:

### Core MLOps Components
- **Azure Kubernetes Service (AKS)**: Managed Kubernetes cluster with autoscaling and GPU support
- **Azure Machine Learning Workspace**: ML model lifecycle management and experiment tracking
- **Azure Container Registry**: Private container registry for model images
- **Azure DevOps**: CI/CD pipeline automation for model deployment

### Supporting Infrastructure
- **Azure Storage Account**: Blob storage for ML workspace and diagnostic data
- **Azure Key Vault**: Secure secrets and configuration management
- **Azure Application Insights**: Application performance monitoring and telemetry
- **Azure Monitor**: Comprehensive monitoring and alerting solution
- **Azure Log Analytics**: Centralized logging and analytics

### Networking & Security
- **Azure Virtual Network**: Isolated network environment for AKS cluster
- **Azure Private Link**: Secure connectivity between services
- **Azure Managed Identity**: Identity and access management for Azure resources
- **Azure RBAC**: Role-based access control for fine-grained permissions

## Prerequisites

Before deploying this infrastructure, ensure you have:

### Required Tools
- Azure CLI version 2.50.0 or later
- kubectl CLI tool for Kubernetes management
- Azure subscription with Owner or Contributor permissions
- Basic understanding of MLOps concepts and Kubernetes

### For Bicep Deployment
- Azure CLI with Bicep extension installed
- PowerShell Core 7.0+ (optional, for enhanced scripting)

### For Terraform Deployment
- Terraform version 1.5.0 or later
- Azure Provider for Terraform

### For Script Deployment
- Bash shell environment (Linux, macOS, or WSL2)
- jq for JSON processing
- openssl for random string generation

### Estimated Costs
- **Development Environment**: $150-250/month
- **Production Environment**: $300-500/month
- **Enterprise Setup**: $500-1000/month

> **Note**: Costs vary based on AKS node count, ML compute usage, and data storage requirements. Enable autoscaling to optimize costs during low-demand periods.

## Quick Start

### Using Bicep

```bash
# Navigate to the Bicep directory
cd bicep/

# Review and customize parameters
cat parameters.json

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-mlops-pipeline" \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment group show \
    --resource-group "rg-mlops-pipeline" \
    --name "main"
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Navigate to the scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy infrastructure
./deploy.sh

# Verify deployment (optional)
az resource list --resource-group "rg-mlops-pipeline" --output table
```

## Deployment Configuration

### Environment Variables

All deployment methods support the following environment variables:

```bash
# Required Configuration
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_TENANT_ID="your-tenant-id"
export LOCATION="eastus"
export RESOURCE_GROUP="rg-mlops-pipeline"

# Optional Customization
export AKS_NODE_COUNT="3"
export AKS_NODE_SIZE="Standard_DS3_v2"
export ML_COMPUTE_INSTANCE_SIZE="Standard_DS3_v2"
export ENABLE_GPU_NODES="false"
export ENVIRONMENT="dev"
```

### Bicep Parameters

Customize the `parameters.json` file to match your requirements:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "environmentName": {
      "value": "dev"
    },
    "aksNodeCount": {
      "value": 3
    },
    "aksNodeVmSize": {
      "value": "Standard_DS3_v2"
    },
    "enableAutoScaling": {
      "value": true
    },
    "enableGpuNodes": {
      "value": false
    }
  }
}
```

### Terraform Variables

Create a `terraform.tfvars` file or set variables via environment:

```hcl
# terraform.tfvars
location           = "eastus"
environment        = "dev"
aks_node_count     = 3
aks_node_vm_size   = "Standard_DS3_v2"
enable_auto_scaling = true
enable_gpu_nodes   = false
ml_compute_sku     = "Standard_DS3_v2"
```

## Post-Deployment Configuration

### 1. Configure kubectl Access

```bash
# Get AKS credentials
az aks get-credentials \
    --resource-group "rg-mlops-pipeline" \
    --name "aks-mlops-cluster"

# Verify cluster access
kubectl get nodes
```

### 2. Verify ML Workspace Integration

```bash
# List ML compute targets
az ml compute list \
    --resource-group "rg-mlops-pipeline" \
    --workspace-name "mlw-mlops-demo"

# Check AKS attachment status
az ml compute show \
    --name "aks-compute" \
    --resource-group "rg-mlops-pipeline" \
    --workspace-name "mlw-mlops-demo"
```

### 3. Configure Azure DevOps Integration

```bash
# Create service connection in Azure DevOps
az devops service-endpoint azurerm create \
    --azure-rm-service-principal-id "$(az account show --query user.name -o tsv)" \
    --azure-rm-subscription-id "$(az account show --query id -o tsv)" \
    --azure-rm-tenant-id "$(az account show --query tenantId -o tsv)" \
    --name "MLOps-ServiceConnection"
```

### 4. Deploy Sample Model

```bash
# Deploy a test model to verify pipeline
az ml model deploy \
    --name "test-model" \
    --model "azureml:sklearn-iris:1" \
    --compute-target "aks-compute" \
    --deploy-config-file "inference-config.json"
```

## Monitoring and Maintenance

### Health Checks

```bash
# Check AKS cluster health
az aks show \
    --resource-group "rg-mlops-pipeline" \
    --name "aks-mlops-cluster" \
    --query "powerState.code"

# Monitor ML workspace metrics
az ml workspace show \
    --resource-group "rg-mlops-pipeline" \
    --workspace-name "mlw-mlops-demo"

# Check container registry status
az acr check-health --name "acrmlops"
```

### Scaling Operations

```bash
# Scale AKS nodes
az aks scale \
    --resource-group "rg-mlops-pipeline" \
    --name "aks-mlops-cluster" \
    --node-count 5

# Update ML compute instance
az ml compute update \
    --name "cpu-cluster" \
    --resource-group "rg-mlops-pipeline" \
    --workspace-name "mlw-mlops-demo" \
    --min-instances 0 \
    --max-instances 10
```

### Backup and Recovery

```bash
# Backup ML workspace metadata
az ml workspace archive \
    --name "mlw-mlops-demo" \
    --resource-group "rg-mlops-pipeline"

# Export AKS configuration
kubectl get all --all-namespaces -o yaml > aks-backup.yaml

# Backup container images
az acr repository list \
    --name "acrmlops" \
    --output table
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name "rg-mlops-pipeline" \
    --yes \
    --no-wait

# Verify deletion
az group exists --name "rg-mlops-pipeline"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Confirm cleanup completion
az group exists --name "rg-mlops-pipeline"
```

## Troubleshooting

### Common Issues

#### AKS Deployment Failures

```bash
# Check AKS events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Verify node status
kubectl describe nodes

# Check pod logs
kubectl logs -n azureml <pod-name>
```

#### ML Workspace Connection Issues

```bash
# Test workspace connectivity
az ml workspace show \
    --resource-group "rg-mlops-pipeline" \
    --workspace-name "mlw-mlops-demo"

# Verify service principal permissions
az role assignment list \
    --assignee "$(az account show --query user.name -o tsv)" \
    --scope "/subscriptions/$(az account show --query id -o tsv)"
```

#### Container Registry Authentication

```bash
# Update AKS-ACR integration
az aks update \
    --resource-group "rg-mlops-pipeline" \
    --name "aks-mlops-cluster" \
    --attach-acr "acrmlops"

# Test registry access
az acr login --name "acrmlops"
docker pull acrmlops.azurecr.io/test-image:latest
```

### Performance Optimization

#### AKS Cluster Optimization

```bash
# Enable cluster autoscaler
az aks update \
    --resource-group "rg-mlops-pipeline" \
    --name "aks-mlops-cluster" \
    --enable-cluster-autoscaler \
    --min-count 1 \
    --max-count 10

# Configure resource requests/limits
kubectl apply -f - <<EOF
apiVersion: v1
kind: LimitRange
metadata:
  name: ml-workload-limits
  namespace: azureml
spec:
  limits:
  - default:
      cpu: 2
      memory: 4Gi
    defaultRequest:
      cpu: 1
      memory: 2Gi
    type: Container
EOF
```

#### ML Compute Optimization

```bash
# Create cost-optimized compute cluster
az ml compute create \
    --name "spot-cluster" \
    --type "amlcompute" \
    --tier "low_priority" \
    --size "Standard_DS3_v2" \
    --min-instances 0 \
    --max-instances 5 \
    --resource-group "rg-mlops-pipeline" \
    --workspace-name "mlw-mlops-demo"
```

## Security Considerations

### Network Security

- All resources are deployed within a virtual network with private endpoints
- AKS cluster uses Azure CNI for advanced networking capabilities
- Network security groups restrict traffic to essential ports only
- Container Registry uses private endpoints for secure image access

### Identity and Access Management

- Managed Identity is used for service-to-service authentication
- Role-based access control (RBAC) follows principle of least privilege
- Azure Key Vault secures all secrets and certificates
- Azure AD integration provides enterprise authentication

### Data Protection

- All data at rest is encrypted using Azure Storage Service Encryption
- Data in transit uses TLS 1.2 encryption
- ML workspace implements data lineage and governance
- Container images are scanned for vulnerabilities

## Best Practices

### Development Workflow

1. **Version Control**: Store all model code and configurations in Git
2. **Environment Isolation**: Use separate environments for dev, staging, and production
3. **Automated Testing**: Implement unit tests and integration tests for model code
4. **Model Validation**: Use automated model validation before deployment
5. **Monitoring**: Implement comprehensive monitoring for model performance and drift

### Production Deployment

1. **Blue-Green Deployment**: Use traffic splitting for zero-downtime deployments
2. **Health Checks**: Implement readiness and liveness probes
3. **Resource Limits**: Set appropriate CPU and memory limits
4. **Backup Strategy**: Regular backups of model artifacts and configurations
5. **Disaster Recovery**: Multi-region deployment for critical workloads

### Cost Optimization

1. **Auto-scaling**: Enable cluster and pod autoscaling
2. **Spot Instances**: Use Azure Spot VMs for training workloads
3. **Resource Scheduling**: Schedule non-critical workloads during off-peak hours
4. **Storage Optimization**: Use appropriate storage tiers for different data types
5. **Regular Cleanup**: Implement automated cleanup of unused resources

## Support and Documentation

### Azure Documentation

- [Azure Kubernetes Service Documentation](https://docs.microsoft.com/azure/aks/)
- [Azure Machine Learning Documentation](https://docs.microsoft.com/azure/machine-learning/)
- [Azure Container Registry Documentation](https://docs.microsoft.com/azure/container-registry/)
- [Azure DevOps Documentation](https://docs.microsoft.com/azure/devops/)

### Community Resources

- [Azure MLOps Examples](https://github.com/Azure/MLOps)
- [AKS Learning Path](https://docs.microsoft.com/learn/paths/intro-to-kubernetes-on-azure/)
- [Azure Architecture Center](https://docs.microsoft.com/azure/architecture/)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Azure service health status
3. Consult the original recipe documentation
4. Refer to Azure support documentation
5. Open an issue in the project repository

## Contributing

When contributing to this infrastructure code:

1. Follow Azure naming conventions
2. Include appropriate resource tags
3. Update documentation for any changes
4. Test deployments in a development environment
5. Ensure security best practices are maintained

## License

This infrastructure code is provided under the same license as the parent recipe repository.