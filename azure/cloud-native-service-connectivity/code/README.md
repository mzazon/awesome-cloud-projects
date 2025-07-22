# Infrastructure as Code for Cloud-Native Service Connectivity with Application Gateway for Containers

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cloud-Native Service Connectivity with Application Gateway for Containers".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.61.0 or higher installed and configured
- kubectl installed and configured  
- Appropriate Azure permissions (Owner or Contributor on subscription)
- Basic understanding of Kubernetes and Azure networking concepts
- An active Azure subscription

### Required Azure CLI Extensions

```bash
az extension add --name serviceconnector-passwordless --upgrade
az extension add --name alb --upgrade
```

### Required Azure Feature Flags

```bash
az feature register --namespace Microsoft.ContainerService --name AKS-ExtensionManager
az feature register --namespace Microsoft.ContainerService --name AKS-Dapr
az feature register --namespace Microsoft.ContainerService --name EnableWorkloadIdentityPreview
```

## Architecture Overview

This solution deploys:

- **Azure Kubernetes Service (AKS)** cluster with workload identity and OIDC issuer
- **Application Gateway for Containers** with Gateway API integration
- **Azure Storage Account** for blob storage with managed identity access
- **Azure SQL Database** with managed identity authentication
- **Azure Key Vault** for secure secret management
- **Azure Workload Identity** for passwordless authentication
- **Service Connector** integrations for seamless service connectivity
- **Sample microservices** demonstrating cloud-native connectivity patterns

## Estimated Costs

- **AKS Cluster**: ~$150-200/month (3 Standard_D2s_v3 nodes)
- **Application Gateway for Containers**: ~$50-75/month
- **Azure Storage**: ~$5-10/month (minimal usage)
- **Azure SQL Database**: ~$5-15/month (Basic/Serverless tier)
- **Azure Key Vault**: ~$1-5/month (standard operations)
- **Total Estimated**: ~$200-300/month

> **Note**: Costs may vary based on region, usage patterns, and specific configurations.

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-cloud-native-connectivity \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters clusterName=aks-connectivity-demo \
    --parameters applicationGatewayName=agc-connectivity-demo

# Get AKS credentials
az aks get-credentials \
    --resource-group rg-cloud-native-connectivity \
    --name aks-connectivity-demo

# Deploy Kubernetes resources
kubectl apply -f bicep/kubernetes-resources.yaml
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Get AKS credentials
az aks get-credentials \
    --resource-group $(terraform output -raw resource_group_name) \
    --name $(terraform output -raw aks_cluster_name)

# Deploy Kubernetes resources
kubectl apply -f kubernetes-resources.yaml
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# The script will:
# 1. Create Azure resources
# 2. Configure AKS cluster
# 3. Install Application Gateway for Containers
# 4. Set up workload identity
# 5. Deploy sample applications
# 6. Configure Service Connector integrations
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | Yes |
| `clusterName` | AKS cluster name | `aks-connectivity` | Yes |
| `applicationGatewayName` | Application Gateway name | `agc-connectivity` | Yes |
| `nodeCount` | Number of AKS nodes | `3` | No |
| `nodeVmSize` | VM size for AKS nodes | `Standard_D2s_v3` | No |
| `sqlAdminUsername` | SQL Server admin username | `cloudadmin` | No |
| `sqlAdminPassword` | SQL Server admin password | Generated | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `resource_group_name` | Resource group name | `rg-cloud-native-connectivity` | Yes |
| `location` | Azure region | `East US` | Yes |
| `cluster_name` | AKS cluster name | `aks-connectivity` | Yes |
| `node_count` | Number of AKS nodes | `3` | No |
| `node_vm_size` | VM size for AKS nodes | `Standard_D2s_v3` | No |
| `tags` | Resource tags | `{}` | No |

### Environment Variables (Bash Scripts)

```bash
# Optional: Customize deployment
export RESOURCE_GROUP="rg-cloud-native-connectivity"
export LOCATION="eastus"
export CLUSTER_NAME="aks-connectivity-demo"
export NODE_COUNT="3"
export NODE_VM_SIZE="Standard_D2s_v3"
```

## Deployment Validation

### Verify Infrastructure Deployment

```bash
# Check resource group resources
az resource list \
    --resource-group rg-cloud-native-connectivity \
    --output table

# Verify AKS cluster status
az aks show \
    --resource-group rg-cloud-native-connectivity \
    --name aks-connectivity-demo \
    --query '{name:name,status:powerState.code,nodeResourceGroup:nodeResourceGroup}'

# Check Application Gateway for Containers
az network application-gateway for-containers show \
    --resource-group rg-cloud-native-connectivity \
    --name agc-connectivity-demo \
    --query '{name:name,state:provisioningState}'
```

### Verify Kubernetes Resources

```bash
# Check Gateway API resources
kubectl get gateway -n cloud-native-app
kubectl get httproute -n cloud-native-app

# Verify application deployments
kubectl get pods -n cloud-native-app
kubectl get services -n cloud-native-app

# Check workload identity configuration
kubectl describe serviceaccount workload-identity-sa -n cloud-native-app
```

### Test Application Connectivity

```bash
# Get external IP address
export GATEWAY_IP=$(kubectl get gateway cloud-native-gateway -n cloud-native-app -o jsonpath='{.status.addresses[0].value}')

# Test frontend application
curl -H "Host: frontend.example.com" http://${GATEWAY_IP}/

# Test API service
curl -H "Host: api.example.com" http://${GATEWAY_IP}/api/

# Test internal service communication
kubectl exec -it deployment/frontend-app -n cloud-native-app -- curl http://api-service:8080/
```

## Troubleshooting

### Common Issues

1. **Application Gateway for Containers not installing**
   ```bash
   # Check if the feature is registered
   az feature show --namespace Microsoft.ContainerService --name AKS-ExtensionManager
   
   # Re-register if needed
   az feature register --namespace Microsoft.ContainerService --name AKS-ExtensionManager
   ```

2. **Workload Identity authentication failures**
   ```bash
   # Verify OIDC issuer configuration
   az aks show --resource-group rg-cloud-native-connectivity --name aks-connectivity-demo --query "oidcIssuerProfile.issuerUrl"
   
   # Check federated identity credentials
   az identity federated-credential list --identity-name wi-connectivity --resource-group rg-cloud-native-connectivity
   ```

3. **Service Connector connection issues**
   ```bash
   # List Service Connector connections
   az containerapp connection list --resource-group rg-cloud-native-connectivity
   
   # Check connection status
   az containerapp connection validate --resource-group rg-cloud-native-connectivity --name storage-connection
   ```

### Logs and Monitoring

```bash
# Check Application Gateway for Containers controller logs
kubectl logs -n azure-alb-system -l app=alb-controller

# Monitor application pod logs
kubectl logs -n cloud-native-app deployment/api-service

# Check Azure Activity Log for resource deployment issues
az monitor activity-log list --resource-group rg-cloud-native-connectivity --start-time 2024-01-01 --query '[].{Time:eventTimestamp,Status:status.value,Operation:operationName.value}'
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-cloud-native-connectivity \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify resource group deletion
az group exists --name rg-cloud-native-connectivity

# Check for any remaining resources
az resource list \
    --resource-group rg-cloud-native-connectivity \
    --output table
```

## Security Considerations

This implementation follows Azure security best practices:

- **Workload Identity**: Eliminates need for stored secrets in Kubernetes
- **Managed Identity**: Provides passwordless authentication to Azure services
- **RBAC**: Implements least privilege access controls
- **Network Security**: Uses Azure CNI with network policies
- **Key Vault Integration**: Secure secret management with role-based access

### Security Validation

```bash
# Verify workload identity is properly configured
kubectl get serviceaccount workload-identity-sa -n cloud-native-app -o yaml

# Check managed identity permissions
az role assignment list --assignee $(az identity show --resource-group rg-cloud-native-connectivity --name wi-connectivity --query principalId -o tsv) --output table

# Validate network policies
kubectl get networkpolicy -n cloud-native-app
```

## Performance Optimization

### Recommended Optimizations

1. **Node Pool Configuration**
   - Use appropriate VM sizes for workload requirements
   - Configure node auto-scaling based on traffic patterns
   - Consider spot instances for cost optimization

2. **Application Gateway for Containers**
   - Enable connection draining for graceful updates
   - Configure health probes for reliable traffic routing
   - Use traffic splitting for canary deployments

3. **Resource Limits**
   - Set appropriate CPU and memory limits for applications
   - Configure horizontal pod autoscaling
   - Monitor resource utilization and adjust as needed

### Monitoring Setup

```bash
# Enable container insights
az aks enable-addons \
    --resource-group rg-cloud-native-connectivity \
    --name aks-connectivity-demo \
    --addons monitoring

# Configure Application Insights for applications
az extension add --name application-insights
az monitor app-insights component create \
    --app cloud-native-app \
    --location eastus \
    --resource-group rg-cloud-native-connectivity
```

## Advanced Configuration

### Custom Domain and SSL

```bash
# Add custom domain to Application Gateway for Containers
az network application-gateway for-containers frontend-config update \
    --resource-group rg-cloud-native-connectivity \
    --name agc-connectivity-demo \
    --frontend-config-name frontend-config \
    --custom-domain-name "api.yourdomain.com"
```

### Multi-Environment Support

The IaC supports multiple environments through parameterization:

```bash
# Development environment
az deployment group create \
    --resource-group rg-cloud-native-connectivity-dev \
    --template-file bicep/main.bicep \
    --parameters environment=dev \
    --parameters nodeCount=2

# Production environment
az deployment group create \
    --resource-group rg-cloud-native-connectivity-prod \
    --template-file bicep/main.bicep \
    --parameters environment=prod \
    --parameters nodeCount=5
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for detailed explanations
2. **Azure Documentation**: [Application Gateway for Containers](https://docs.microsoft.com/en-us/azure/application-gateway/for-containers/overview)
3. **Service Connector**: [Service Connector Documentation](https://docs.microsoft.com/en-us/azure/service-connector/)
4. **AKS Workload Identity**: [Workload Identity Documentation](https://docs.microsoft.com/en-us/azure/aks/workload-identity-overview)
5. **Gateway API**: [Gateway API Specification](https://gateway-api.sigs.k8s.io/)

## Contributing

When modifying this infrastructure code:

1. Follow Azure resource naming conventions
2. Update parameter validation as needed
3. Test deployments in isolated environments
4. Update documentation for any configuration changes
5. Validate security configurations meet organizational requirements

---

*This infrastructure code was generated for the cloud-native service connectivity recipe. For the complete solution walkthrough, refer to the original recipe documentation.*