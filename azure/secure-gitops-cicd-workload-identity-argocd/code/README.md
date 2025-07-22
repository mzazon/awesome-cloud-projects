# Infrastructure as Code for Secure GitOps CI/CD with Workload Identity and ArgoCD

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure GitOps CI/CD with Workload Identity and ArgoCD".

## Available Implementations

- **Bicep**: Azure native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.47.0 or later installed and configured
- kubectl command-line tool installed
- Git repository for storing application manifests
- Appropriate Azure permissions for:
  - Creating AKS clusters and managed identities
  - Key Vault resource management
  - Role assignments and federated identity credentials
- Basic understanding of Kubernetes, GitOps principles, and Azure identity concepts
- Estimated cost: $50-100 per month for AKS cluster and associated resources

> **Note**: This recipe requires AKS clusters with managed service identity (MSI) enabled. Service Principal Name (SPN) based clusters must be converted to MSI using `az aks update --enable-managed-identity`.

## Architecture Overview

This solution implements a secure GitOps CI/CD pipeline using:

- **Azure Kubernetes Service (AKS)** with Workload Identity enabled
- **Azure Key Vault** for centralized secret management
- **Azure Workload Identity** for keyless authentication
- **ArgoCD** for GitOps continuous deployment
- **Federated Identity Credentials** for secure token exchange

The architecture eliminates hard-coded secrets by leveraging Azure-native identity services and implements zero-trust security principles for container workloads.

## Quick Start

### Using Bicep

```bash
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-gitops-demo \
    --template-file main.bicep \
    --parameters @parameters.json

# Get AKS credentials
az aks get-credentials \
    --resource-group rg-gitops-demo \
    --name aks-gitops-cluster

# Configure ArgoCD applications (post-deployment)
kubectl apply -f ../manifests/argocd-application.yaml
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# Get AKS credentials
az aks get-credentials \
    --resource-group $(terraform output -raw resource_group_name) \
    --name $(terraform output -raw aks_cluster_name)

# Configure ArgoCD applications (post-deployment)
kubectl apply -f ../manifests/argocd-application.yaml
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# The script will:
# 1. Create Azure resources
# 2. Configure workload identity
# 3. Install ArgoCD extension
# 4. Set up sample applications
# 5. Configure GitOps workflows
```

## Post-Deployment Configuration

After the infrastructure is deployed, you'll need to:

### 1. Access ArgoCD UI

```bash
# Expose ArgoCD UI via LoadBalancer
kubectl expose service argocd-server \
    --type LoadBalancer \
    --name argocd-server-lb \
    --port 80 \
    --target-port 8080 \
    -n argocd

# Get ArgoCD admin password
kubectl get secret argocd-initial-admin-secret \
    -n argocd \
    -o jsonpath="{.data.password}" | base64 -d

# Get LoadBalancer IP
kubectl get service argocd-server-lb -n argocd
```

### 2. Configure Git Repository

Update your Git repository with the application manifests and configure ArgoCD to sync from your repository:

```bash
# Create ArgoCD application pointing to your Git repository
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: your-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/your-repo.git
    targetRevision: HEAD
    path: manifests/
  destination:
    server: https://kubernetes.default.svc
    namespace: your-app-namespace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
```

### 3. Validate Workload Identity

```bash
# Check service account annotations
kubectl get serviceaccount sample-app-sa -n sample-app -o yaml

# Verify secrets are accessible
kubectl exec -it deployment/sample-app -n sample-app -- ls -la /mnt/secrets

# Test Key Vault integration
kubectl exec -it deployment/sample-app -n sample-app -- env | grep DATABASE_CONNECTION_STRING
```

## Customization

### Bicep Parameters

Customize the deployment by modifying `bicep/parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "clusterName": {
      "value": "aks-gitops-cluster"
    },
    "nodeCount": {
      "value": 3
    },
    "vmSize": {
      "value": "Standard_D2s_v3"
    }
  }
}
```

### Terraform Variables

Customize the deployment by modifying `terraform/terraform.tfvars`:

```hcl
location = "eastus"
cluster_name = "aks-gitops-cluster"
node_count = 3
vm_size = "Standard_D2s_v3"
key_vault_sku = "standard"
```

### Script Environment Variables

Customize the bash deployment by setting environment variables before running:

```bash
export LOCATION="westus2"
export CLUSTER_NAME="my-gitops-cluster"
export NODE_COUNT=5
export VM_SIZE="Standard_D4s_v3"

./scripts/deploy.sh
```

## Security Considerations

This implementation follows Azure security best practices:

- **Workload Identity**: Eliminates stored credentials in Kubernetes
- **Federated Identity**: Secure token exchange between Kubernetes and Azure AD
- **RBAC**: Least privilege access to Key Vault secrets
- **Managed Identity**: Azure-native authentication without credential management
- **Key Vault Integration**: Centralized secret management with audit trails

### Additional Security Enhancements

Consider implementing these additional security measures:

1. **Azure Policy**: Enforce governance and compliance rules
2. **Microsoft Defender for Cloud**: Advanced threat protection
3. **Network Security Groups**: Restrict network access
4. **Private Endpoints**: Secure connectivity to Azure services
5. **Azure Monitor**: Comprehensive logging and monitoring

## Monitoring and Observability

### ArgoCD Monitoring

```bash
# Check ArgoCD application status
kubectl get applications -n argocd

# View application details
kubectl describe application sample-app-gitops -n argocd

# Check ArgoCD controller logs
kubectl logs -f deployment/argocd-application-controller -n argocd
```

### Workload Identity Monitoring

```bash
# Check federated identity credentials
az identity federated-credential list \
    --identity-name mi-argocd-${RANDOM_SUFFIX} \
    --resource-group rg-gitops-demo

# Verify service account configurations
kubectl get serviceaccounts -A -o yaml | grep -A 5 -B 5 "azure.workload.identity"
```

### Key Vault Monitoring

```bash
# Check Key Vault access logs
az monitor activity-log list \
    --resource-group rg-gitops-demo \
    --resource-name kv-gitops-${RANDOM_SUFFIX}

# List Key Vault secrets
az keyvault secret list --vault-name kv-gitops-${RANDOM_SUFFIX}
```

## Troubleshooting

### Common Issues

1. **ArgoCD Extension Installation Fails**
   ```bash
   # Check extension status
   az k8s-extension show \
       --resource-group rg-gitops-demo \
       --cluster-name aks-gitops-cluster \
       --cluster-type managedClusters \
       --name argocd
   ```

2. **Workload Identity Authentication Errors**
   ```bash
   # Verify OIDC issuer configuration
   az aks show \
       --name aks-gitops-cluster \
       --resource-group rg-gitops-demo \
       --query "oidcIssuerProfile.issuerUrl"
   
   # Check federated identity credentials
   az identity federated-credential list \
       --identity-name mi-argocd-${RANDOM_SUFFIX} \
       --resource-group rg-gitops-demo
   ```

3. **Key Vault Access Issues**
   ```bash
   # Check role assignments
   az role assignment list \
       --assignee ${USER_ASSIGNED_PRINCIPAL_ID} \
       --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-gitops-demo"
   
   # Test Key Vault connectivity from pod
   kubectl exec -it deployment/sample-app -n sample-app -- \
       curl -H "Metadata: true" \
       "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net"
   ```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-gitops-demo \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all infrastructure
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete ArgoCD applications
# 2. Remove ArgoCD extension
# 3. Delete federated identity credentials
# 4. Remove all Azure resources
```

### Manual Cleanup (if needed)

```bash
# Delete specific resources if automated cleanup fails
az aks delete \
    --resource-group rg-gitops-demo \
    --name aks-gitops-cluster \
    --yes \
    --no-wait

az keyvault delete \
    --name kv-gitops-${RANDOM_SUFFIX} \
    --resource-group rg-gitops-demo

az identity delete \
    --name mi-argocd-${RANDOM_SUFFIX} \
    --resource-group rg-gitops-demo
```

## Cost Optimization

- **AKS Node Pools**: Use appropriate VM sizes for your workload requirements
- **Key Vault**: Standard SKU is sufficient for most use cases
- **Storage**: Use managed disks with appropriate performance tiers
- **Monitoring**: Configure log retention policies to manage costs
- **Auto-scaling**: Enable cluster autoscaler to optimize resource usage

## Advanced Configuration

### Multi-Environment Setup

Configure separate environments with environment-specific parameters:

```bash
# Development environment
./scripts/deploy.sh -e dev -l eastus -n 2

# Production environment  
./scripts/deploy.sh -e prod -l westus2 -n 5
```

### High Availability Configuration

For production deployments, consider:

- Multiple availability zones
- Node pool distribution
- ArgoCD high availability mode
- Key Vault geo-replication

### Integration with Azure DevOps

Configure Azure DevOps integration for complete CI/CD:

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include:
    - main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: AzureCLI@2
  inputs:
    azureSubscription: 'your-service-connection'
    scriptType: 'bash'
    scriptLocation: 'scriptPath'
    scriptPath: 'scripts/deploy.sh'
```

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Azure documentation:
   - [Azure Workload Identity](https://docs.microsoft.com/en-us/azure/aks/workload-identity-overview)
   - [ArgoCD Extension for AKS](https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/tutorial-use-gitops-connected-cluster)
   - [Azure Key Vault Provider for Secrets Store CSI Driver](https://docs.microsoft.com/en-us/azure/aks/csi-secrets-store-driver)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Validate all security configurations
3. Update documentation as needed
4. Follow Azure naming conventions
5. Implement proper resource tagging

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Ensure compliance with your organization's policies and Azure terms of service.