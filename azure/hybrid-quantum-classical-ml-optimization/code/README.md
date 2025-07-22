# Infrastructure as Code for Hybrid Quantum-Classical ML Optimization Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Hybrid Quantum-Classical ML Optimization Workflows".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.61.0 or later installed and configured
- Azure subscription with appropriate permissions for creating:
  - Azure Quantum workspace
  - Azure Machine Learning workspace
  - Azure Batch account
  - Azure Data Lake Storage account
  - Azure Key Vault
  - Compute resources
- Python 3.8+ with Azure ML SDK v2 and Azure Quantum SDK (for testing)
- Basic understanding of quantum computing concepts
- Terraform v1.0+ (if using Terraform implementation)

## Cost Estimate

Estimated cost for running this infrastructure: $50-100 for testing (varies based on quantum hardware usage and compute resources). Azure Quantum provides free credits for first-time users.

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
cd bicep/

# Login to Azure and set subscription
az login
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-quantum-ml-demo" \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var-file="terraform.tfvars"

# Apply the configuration
terraform apply -var-file="terraform.tfvars"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts to configure your deployment
```

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize your deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourcePrefix": {
      "value": "quantum-ml"
    },
    "location": {
      "value": "eastus"
    },
    "quantumProviders": {
      "value": [
        "ionq.simulator",
        "quantinuum.sim.h1-1sc",
        "microsoft.simulator"
      ]
    },
    "mlComputeInstanceSize": {
      "value": "Standard_DS3_v2"
    },
    "batchPoolVmSize": {
      "value": "Standard_DS3_v2"
    }
  }
}
```

### Terraform Variables

Create a `terraform/terraform.tfvars` file:

```hcl
# Required variables
subscription_id = "your-azure-subscription-id"
tenant_id      = "your-azure-tenant-id"

# Optional customization
resource_prefix = "quantum-ml"
location       = "eastus"
environment    = "development"

# Quantum workspace configuration
quantum_providers = [
  "ionq.simulator",
  "quantinuum.sim.h1-1sc", 
  "microsoft.simulator"
]

# Compute configuration
ml_compute_instance_size = "Standard_DS3_v2"
ml_compute_cluster_max_nodes = 4
batch_pool_vm_size = "Standard_DS3_v2"

# Storage configuration
storage_account_tier = "Standard"
storage_replication_type = "LRS"

# Tags
tags = {
  Purpose     = "quantum-ml-demo"
  Environment = "development"
  Owner       = "your-name"
}
```

## Deployment Architecture

The infrastructure includes:

- **Azure Quantum Workspace**: Central hub for quantum computing with multiple provider access
- **Azure Machine Learning Workspace**: Enterprise ML platform with compute resources
- **Azure Data Lake Storage**: Hierarchical storage for training data and model artifacts
- **Azure Batch Account**: Scalable compute for quantum job orchestration
- **Azure Key Vault**: Secure storage for credentials and secrets
- **Compute Resources**: ML compute instances and clusters for model training
- **Monitoring**: Azure Monitor and Application Insights integration

## Post-Deployment Setup

After deploying the infrastructure, complete these setup steps:

### 1. Upload Sample Data

```bash
# Set environment variables from deployment outputs
export STORAGE_ACCOUNT="your-storage-account-name"
export RESOURCE_GROUP="your-resource-group"

# Upload sample training data
az storage blob upload \
    --account-name $STORAGE_ACCOUNT \
    --container-name "quantum-ml-data" \
    --name "train.csv" \
    --file "./sample-data/train.csv"
```

### 2. Install Required Packages

```bash
# Install Azure Quantum SDK
pip install azure-quantum qiskit azure-quantum[qiskit]

# Install Azure ML SDK v2
pip install azure-ai-ml azure-ml-component-sdk
```

### 3. Test Quantum Workspace Connection

```bash
# Test quantum workspace connectivity
az quantum workspace show \
    --name "your-quantum-workspace" \
    --resource-group $RESOURCE_GROUP

# List available quantum targets
az quantum target list \
    --workspace-name "your-quantum-workspace" \
    --resource-group $RESOURCE_GROUP
```

### 4. Submit Test Quantum Job

```python
from azure.quantum import Workspace

# Initialize workspace connection
workspace = Workspace(
    resource_id="/subscriptions/.../resourceGroups/.../providers/Microsoft.Quantum/Workspaces/...",
    location="eastus"
)

# List available simulators
print("Available quantum simulators:")
for solver in workspace.get_solvers():
    print(f"- {solver.name}: {solver.provider_id}")
```

## Testing the Solution

### Run Sample ML Pipeline

```bash
# Navigate to the ML pipeline directory
cd quantum-ml-pipeline/

# Submit a test pipeline job
az ml job create \
    --file hybrid_quantum_ml_pipeline.yml \
    --resource-group $RESOURCE_GROUP \
    --workspace-name "your-ml-workspace"
```

### Test Quantum Feature Mapping

```bash
# Run quantum feature mapping component test
python components/quantum-feature-map/test_quantum_features.py \
    --workspace-id "your-quantum-workspace-id" \
    --test-data "./test-data/sample.csv"
```

### Validate Model Endpoint

```bash
# Get endpoint details
az ml online-endpoint show \
    --name "quantum-ml-inference" \
    --resource-group $RESOURCE_GROUP \
    --workspace-name "your-ml-workspace"

# Test prediction endpoint
curl -X POST "your-endpoint-url" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer your-token" \
    -d '{"data": [[0.1, 0.2, 0.3, 0.4]]}'
```

## Monitoring and Troubleshooting

### View Quantum Job Status

```bash
# Monitor quantum jobs
az quantum job list \
    --workspace-name "your-quantum-workspace" \
    --resource-group $RESOURCE_GROUP

# Get specific job details
az quantum job show \
    --job-id "your-job-id" \
    --workspace-name "your-quantum-workspace" \
    --resource-group $RESOURCE_GROUP
```

### Monitor ML Pipeline Runs

```bash
# List recent ML pipeline runs
az ml job list \
    --resource-group $RESOURCE_GROUP \
    --workspace-name "your-ml-workspace" \
    --max-results 10

# View specific run details
az ml job show \
    --name "your-run-id" \
    --resource-group $RESOURCE_GROUP \
    --workspace-name "your-ml-workspace"
```

### Check Resource Health

```bash
# Check all resource statuses
az resource list \
    --resource-group $RESOURCE_GROUP \
    --output table

# Validate Key Vault access
az keyvault secret list \
    --vault-name "your-key-vault-name"
```

## Performance Optimization

### Quantum Job Optimization

- Use free simulators during development and testing
- Cache quantum computation results to avoid repeated calculations
- Implement batch processing for multiple quantum feature transformations
- Monitor quantum job queue times and optimize scheduling

### ML Pipeline Optimization

- Scale compute clusters based on workload demands
- Use data parallelization for large datasets
- Implement model caching for inference endpoints
- Monitor compute utilization and right-size instances

### Cost Optimization

- Use spot instances for non-critical batch workloads
- Implement automatic scaling policies for compute resources
- Monitor quantum hardware usage and optimize job submission
- Set up cost alerts and budgets for resource groups

## Security Considerations

### Access Control

- Use Azure Active Directory for authentication
- Implement role-based access control (RBAC) for resource access
- Store all credentials in Azure Key Vault
- Enable auditing for quantum workspace and ML workspace

### Data Protection

- Enable encryption at rest for all storage accounts
- Use managed identities for service-to-service authentication
- Implement network security groups for compute resources
- Enable Azure Monitor for security monitoring

### Compliance

- Follow Azure compliance frameworks for your industry
- Implement data residency requirements
- Enable audit logging for all quantum and ML operations
- Use Azure Policy for governance enforcement

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name "rg-quantum-ml-demo" \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var-file="terraform.tfvars"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
az resource list \
    --resource-group "rg-quantum-ml-demo" \
    --output table

# Check for any remaining quantum workspaces
az quantum workspace list --output table

# Verify ML workspaces are removed
az ml workspace list --output table
```

## Troubleshooting Common Issues

### Quantum Workspace Connection Issues

```bash
# Verify quantum providers are available
az quantum target list \
    --workspace-name "your-workspace" \
    --resource-group $RESOURCE_GROUP

# Check workspace permissions
az role assignment list \
    --scope "/subscriptions/.../resourceGroups/.../providers/Microsoft.Quantum/Workspaces/..."
```

### ML Pipeline Failures

```bash
# Check compute instance status
az ml compute show \
    --name "quantum-ml-compute" \
    --resource-group $RESOURCE_GROUP \
    --workspace-name "your-ml-workspace"

# View pipeline job logs
az ml job stream \
    --name "your-job-id" \
    --resource-group $RESOURCE_GROUP \
    --workspace-name "your-ml-workspace"
```

### Permission Issues

```bash
# Check current user permissions
az role assignment list \
    --assignee "your-user-principal-name" \
    --scope "/subscriptions/your-subscription-id"

# Verify service principal permissions (if using)
az ad sp show \
    --id "your-service-principal-id"
```

## Additional Resources

- [Azure Quantum Documentation](https://learn.microsoft.com/en-us/azure/quantum/)
- [Azure Machine Learning Documentation](https://learn.microsoft.com/en-us/azure/machine-learning/)
- [Q# Programming Language Guide](https://learn.microsoft.com/en-us/azure/quantum/user-guide/)
- [Azure Quantum Pricing](https://azure.microsoft.com/en-us/pricing/details/azure-quantum/)
- [Quantum Development Kit](https://learn.microsoft.com/en-us/azure/quantum/install-command-line-qdk)

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Azure service health status
3. Consult the original recipe documentation
4. Contact Azure support for service-specific issues
5. Review Azure Quantum community forums for quantum-specific questions

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Azure best practices and security guidelines
3. Update documentation for any parameter changes
4. Validate all IaC implementations work correctly
5. Consider cost implications of infrastructure changes