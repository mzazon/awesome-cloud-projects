# Infrastructure as Code for Zero-Trust Microservices Segmentation with Service Mesh

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Zero-Trust Microservices Segmentation with Service Mesh".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Azure CLI v2.50.0 or later installed and configured
- kubectl command-line tool installed
- Valid Azure subscription with Owner or Contributor access
- Basic understanding of Kubernetes, Istio service mesh, and DNS concepts
- Familiarity with Azure networking and security concepts

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension installed
- PowerShell 7.0+ (optional, for enhanced scripting)

#### For Terraform
- Terraform v1.5.0 or later installed
- Azure CLI authenticated (`az login`)
- Appropriate Azure permissions for resource creation

#### For Bash Scripts
- Bash shell environment
- jq command-line JSON processor
- openssl for generating random values

### Required Azure Permissions
- Microsoft.ContainerService/* (for AKS)
- Microsoft.Network/* (for VNet, DNS, Application Gateway)
- Microsoft.OperationalInsights/* (for Log Analytics)
- Microsoft.Resources/* (for resource groups)
- Microsoft.Authorization/roleAssignments/* (for managed identity)

## Architecture Overview

This infrastructure deploys:
- Azure Kubernetes Service (AKS) cluster with Istio service mesh
- Virtual Network with segmented subnets
- Azure DNS Private Zones for internal service discovery
- Azure Application Gateway with WAF for secure ingress
- Log Analytics workspace for comprehensive monitoring
- Sample microservices with network segmentation policies

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to Bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-advanced-network-segmentation \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters clusterName=aks-service-mesh-cluster

# Configure kubectl access
az aks get-credentials \
    --resource-group rg-advanced-network-segmentation \
    --name aks-service-mesh-cluster
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# Configure kubectl access
az aks get-credentials \
    --resource-group $(terraform output -raw resource_group_name) \
    --name $(terraform output -raw aks_cluster_name)
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will automatically configure kubectl access
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | No |
| `resourceGroupName` | Resource group name | `rg-advanced-network-segmentation` | No |
| `clusterName` | AKS cluster name | `aks-service-mesh-cluster` | No |
| `nodeCount` | Initial node count | `3` | No |
| `nodeVmSize` | VM size for nodes | `Standard_D4s_v3` | No |
| `dnsZoneName` | Private DNS zone name | `company.internal` | No |
| `enableMonitoring` | Enable Azure Monitor integration | `true` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region | `eastus` | No |
| `resource_group_name` | Resource group name | `rg-advanced-network-segmentation` | No |
| `cluster_name` | AKS cluster name | `aks-service-mesh-cluster` | No |
| `node_count` | Initial node count | `3` | No |
| `node_vm_size` | VM size for nodes | `Standard_D4s_v3` | No |
| `dns_zone_name` | Private DNS zone name | `company.internal` | No |
| `enable_auto_scaling` | Enable cluster autoscaling | `true` | No |
| `min_node_count` | Minimum nodes for autoscaling | `2` | No |
| `max_node_count` | Maximum nodes for autoscaling | `10` | No |

## Post-Deployment Configuration

After the infrastructure is deployed, additional configuration is required:

### 1. Verify Istio Installation

```bash
# Check Istio system pods
kubectl get pods -n aks-istio-system

# Verify Istio configuration
kubectl get mutatingwebhookconfiguration istio-sidecar-injector
```

### 2. Deploy Sample Applications

```bash
# Create namespaces with Istio injection
kubectl create namespace frontend
kubectl create namespace backend
kubectl create namespace database

kubectl label namespace frontend istio-injection=enabled
kubectl label namespace backend istio-injection=enabled
kubectl label namespace database istio-injection=enabled

# Deploy sample microservices
kubectl apply -f ../sample-apps/
```

### 3. Configure Network Policies

```bash
# Apply Istio authorization policies
kubectl apply -f ../policies/authorization-policies.yaml

# Apply network policies
kubectl apply -f ../policies/network-policies.yaml
```

### 4. Set Up DNS Records

```bash
# Update DNS records with service IPs (automated in scripts)
./scripts/configure-dns.sh
```

## Validation and Testing

### 1. Verify Network Segmentation

```bash
# Check sidecar injection
kubectl get pods -n frontend -o wide
kubectl get pods -n backend -o wide
kubectl get pods -n database -o wide

# Test service connectivity (should succeed for authorized paths)
kubectl exec -n frontend deploy/frontend-service -- \
    curl -s http://backend-service.company.internal

# Test unauthorized access (should fail)
kubectl exec -n database deploy/database-service -- \
    curl -s http://frontend-service.company.internal
```

### 2. Test External Access

```bash
# Get Application Gateway public IP
APPGW_IP=$(az network public-ip show \
    --resource-group rg-advanced-network-segmentation \
    --name appgw-public-ip \
    --query ipAddress --output tsv)

# Test external access
curl -s http://${APPGW_IP}
```

### 3. Monitor Service Mesh

```bash
# Port forward to monitoring dashboards
kubectl port-forward -n istio-system svc/kiali 20001:20001 &
kubectl port-forward -n istio-system svc/grafana 3000:3000 &

# Access dashboards
echo "Kiali: http://localhost:20001"
echo "Grafana: http://localhost:3000"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-advanced-network-segmentation \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm destructive actions when prompted
```

## Troubleshooting

### Common Issues

#### 1. Istio Sidecar Not Injected
- Verify namespace has `istio-injection=enabled` label
- Check if Istio admission webhook is running
- Restart pods to trigger injection

#### 2. DNS Resolution Failures
- Verify private DNS zone is linked to VNet
- Check CoreDNS configuration
- Validate DNS records are created

#### 3. Service Connectivity Issues
- Review Istio authorization policies
- Check network policies configuration
- Verify service mesh certificates

#### 4. Application Gateway Health Probe Failures
- Confirm Istio ingress gateway is running
- Check backend pool configuration
- Verify security group rules

### Debug Commands

```bash
# Check Istio configuration
istioctl proxy-config cluster <pod-name> -n <namespace>

# Verify DNS resolution
kubectl run test-dns --image=busybox --rm -it --restart=Never -- \
    nslookup frontend-service.company.internal

# Check service mesh certificates
istioctl proxy-config secret <pod-name> -n <namespace>

# View Istio access logs
kubectl logs -n istio-system -l app=istio-proxy -c istio-proxy
```

## Security Considerations

### Network Security
- All service-to-service communication is encrypted with mutual TLS
- Network policies implement default-deny with explicit allow rules
- Application Gateway provides WAF protection for external traffic

### Identity and Access
- AKS uses managed identity for Azure resource access
- Istio authorization policies enforce service-level access controls
- Private DNS zones prevent external DNS enumeration

### Monitoring and Compliance
- Azure Monitor integration provides comprehensive logging
- Istio telemetry enables traffic flow analysis
- Access logs support audit and compliance requirements

## Cost Optimization

### Resource Sizing
- Start with minimum node counts and enable autoscaling
- Use appropriate VM sizes for workload requirements
- Consider spot instances for non-production environments

### Monitoring Costs
- Configure log retention policies in Log Analytics
- Use sampling for telemetry data in high-traffic scenarios
- Set up cost alerts for unexpected usage

### Cleanup Practices
- Remove development/test environments when not in use
- Use resource tags for cost allocation and management
- Regular review of unused resources

## Support and Documentation

### Official Documentation
- [Azure Kubernetes Service with Istio](https://learn.microsoft.com/en-us/azure/aks/istio-about)
- [Azure DNS Private Zones](https://learn.microsoft.com/en-us/azure/dns/private-dns-overview)
- [Azure Application Gateway](https://learn.microsoft.com/en-us/azure/application-gateway/)
- [Azure Monitor for Containers](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-overview)

### Community Resources
- [Istio Documentation](https://istio.io/latest/docs/)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/)

### Getting Help
- For Azure-specific issues: Azure Support or community forums
- For Kubernetes/Istio issues: CNCF community resources
- For infrastructure code issues: Review logs and configuration files

## Contributing

When modifying the infrastructure code:

1. Test changes in a development environment
2. Validate with `bicep build` or `terraform validate`
3. Update documentation for any parameter changes
4. Follow Azure naming conventions and tagging standards
5. Ensure cleanup scripts handle new resources

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and adapt security configurations for production use.