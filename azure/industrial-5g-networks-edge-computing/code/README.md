# Infrastructure as Code for Industrial 5G Networks for Edge Computing

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Industrial 5G Networks for Edge Computing".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (Microsoft's recommended IaC language)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This IaC deploys a complete private 5G network infrastructure including:

- Azure Operator Nexus platform for hybrid cloud management
- Azure Private 5G Core network functions
- Mobile Network with network slicing capabilities
- Data networks for OT/IT system segregation
- Azure Stack Edge integration for edge computing
- IoT Hub and Device Provisioning Service
- Monitoring and analytics with Log Analytics
- Container registry for edge workloads

## Prerequisites

### General Requirements
- Azure subscription with Enterprise Agreement
- Azure CLI v2.40.0 or later installed and configured
- Appropriate permissions for Azure Operator Nexus and Private 5G Core
- Azure Stack Edge Pro GPU device(s) deployed and configured
- 5G radio equipment (gNodeB) from certified partners
- Private spectrum license or CBRS access (3.5 GHz band in US)

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension
- PowerShell or Bash terminal

#### For Terraform
- Terraform v1.0+ installed
- Azure CLI authenticated
- Terraform Azure provider v3.0+

### Cost Considerations
- Estimated monthly cost: $5,000-$10,000 for core infrastructure
- Additional spectrum licensing costs apply
- Azure Stack Edge hardware costs not included

> **Important**: Azure Private 5G Core service will retire on September 30, 2025. Microsoft recommends migrating to partner solutions like Nokia or Ericsson private wireless offerings available in Azure Marketplace.

## Quick Start

### Using Bicep

```bash
# Deploy the complete private 5G infrastructure
cd bicep/

# Create resource group
az group create \
    --name rg-private5g-demo \
    --location eastus

# Deploy main template
az deployment group create \
    --resource-group rg-private5g-demo \
    --template-file main.bicep \
    --parameters siteName=factory01 \
                 mobileNetworkName=mn-manufacturing \
                 location=eastus
```

### Using Terraform

```bash
# Initialize and deploy with Terraform
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="resource_group_name=rg-private5g-demo" \
    -var="location=eastus" \
    -var="site_name=factory01"

# Apply configuration
terraform apply \
    -var="resource_group_name=rg-private5g-demo" \
    -var="location=eastus" \
    -var="site_name=factory01"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration values
```

## Configuration Parameters

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `resourceGroupName` | Resource group name | `rg-private5g-demo` | Yes |
| `siteName` | Site identifier for the factory/facility | `factory01` | Yes |
| `mobileNetworkName` | Mobile network identifier | `mn-manufacturing` | Yes |
| `plmnMcc` | Mobile Country Code | `310` | Yes |
| `plmnMnc` | Mobile Network Code | `950` | Yes |

### Network Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `accessInterfaceAddress` | N2 interface IP address | `192.168.1.10` |
| `accessInterfaceSubnet` | N2 interface subnet | `192.168.1.0/24` |
| `accessInterfaceGateway` | N2 interface gateway | `192.168.1.1` |
| `otNetworkSubnet` | OT systems data network | `10.1.0.0/16` |
| `itNetworkSubnet` | IT systems data network | `10.2.0.0/16` |

### Hardware Integration

| Parameter | Description | Required |
|-----------|-------------|----------|
| `customLocationId` | Azure Arc custom location ID | Yes |
| `azureStackEdgeId` | Azure Stack Edge device resource ID | Yes |

## Post-Deployment Configuration

After successful deployment, complete these manual steps:

### 1. Azure Stack Edge Integration

```bash
# Connect your Azure Stack Edge device to the deployed custom location
az customlocation show \
    --name cl-factory01 \
    --resource-group rg-private5g-demo
```

### 2. SIM Provisioning

```bash
# Create and provision SIM cards for your devices
az mobile-network sim create \
    --mobile-network-name mn-manufacturing \
    --resource-group rg-private5g-demo \
    --sim-name sim-device001 \
    --device-type industrial-iot
```

### 3. Radio Equipment Configuration

Configure your 5G gNodeB radio equipment with:
- Connection to the N2 interface at `192.168.1.10`
- Proper authentication certificates
- Network slice configurations

### 4. Device Testing

```bash
# Test device connectivity
az mobile-network attached-data-network show \
    --mobile-network-name mn-manufacturing \
    --data-network-name dn-ot-systems \
    --resource-group rg-private5g-demo
```

## Monitoring and Validation

### Check Deployment Status

```bash
# Verify packet core deployment
az mobile-network pccp show \
    --name factory01 \
    --resource-group rg-private5g-demo \
    --query "{State:provisioningState,Version:version}"

# Check network slices
az mobile-network slice list \
    --mobile-network-name mn-manufacturing \
    --resource-group rg-private5g-demo
```

### Monitor Performance

```bash
# View real-time metrics
az monitor metrics list \
    --resource "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-private5g-demo/providers/Microsoft.MobileNetwork/packetCoreControlPlanes/factory01" \
    --metric "ConnectedDeviceCount"
```

### Access Logs

```bash
# Query device events in Log Analytics
az monitor log-analytics query \
    --workspace law-private5g-* \
    --analytics-query "DeviceEvents_CL | take 100"
```

## Security Considerations

### Network Isolation
- OT and IT networks are properly segmented
- SIM-based device authentication
- Encrypted air interface communications

### Access Control
- Azure RBAC for management plane access
- Custom location isolation for edge workloads
- Private endpoints for sensitive services

### Compliance
- Data sovereignty through edge processing
- Audit logging enabled for all components
- Network slice isolation for different use cases

## Troubleshooting

### Common Issues

1. **Packet Core Deployment Failures**
   ```bash
   # Check custom location status
   az customlocation show --name cl-factory01 --resource-group rg-private5g-demo
   
   # Verify Azure Stack Edge connectivity
   az resource show --ids $AZURE_STACK_EDGE_ID
   ```

2. **Device Connectivity Issues**
   ```bash
   # Verify SIM policy configuration
   az mobile-network sim-policy show \
       --mobile-network-name mn-manufacturing \
       --sim-policy-name policy-industrial-iot \
       --resource-group rg-private5g-demo
   ```

3. **Network Slice Problems**
   ```bash
   # Check slice configuration
   az mobile-network slice show \
       --mobile-network-name mn-manufacturing \
       --slice-name slice-critical-iot \
       --resource-group rg-private5g-demo
   ```

### Support Resources

- [Azure Private 5G Core Documentation](https://learn.microsoft.com/en-us/azure/private-5g-core/)
- [Azure Operator Nexus Documentation](https://learn.microsoft.com/en-us/azure/operator-nexus/)
- [Azure Support Plans](https://azure.microsoft.com/en-us/support/plans/)

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-private5g-demo \
    --yes --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all managed infrastructure
terraform destroy \
    -var="resource_group_name=rg-private5g-demo" \
    -var="location=eastus" \
    -var="site_name=factory01"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup Steps

Some resources may require manual cleanup:

1. **Azure Stack Edge Device**: Disconnect from custom location
2. **Physical Radio Equipment**: Power down gNodeB units
3. **SIM Cards**: Deactivate through carrier portal
4. **Spectrum License**: Return/cancel if applicable

## Customization

### Network Slicing

Modify the network slice configurations in the IaC templates to match your use case:

- **Critical IoT**: Ultra-reliable low-latency (URLLC)
- **Massive IoT**: Enhanced mobile broadband (eMBB)
- **Video Surveillance**: High throughput requirements

### Quality of Service

Adjust QoS parameters in the service policies:

```bicep
// Example QoS configuration for real-time control
service_qos: {
  fiveQi: 82
  arp: {
    priorityLevel: 1
    preemptionCapability: 'MayPreempt'
    preemptionVulnerability: 'NotPreemptable'
  }
}
```

### Geographic Distribution

For multi-site deployments, replicate the infrastructure with site-specific parameters:

```bash
# Deploy additional sites
az deployment group create \
    --resource-group rg-private5g-multi \
    --template-file main.bicep \
    --parameters siteName=warehouse02 \
                 location=westus2
```

## Migration Planning

> **Critical**: Azure Private 5G Core service retires September 30, 2025

### Recommended Actions

1. **Assess Current Deployment**: Document all configurations and customizations
2. **Evaluate Alternatives**: Review Nokia, Ericsson solutions in Azure Marketplace
3. **Plan Migration Timeline**: Allow 6-9 months for migration planning and execution
4. **Test Partner Solutions**: Set up proof-of-concept with recommended alternatives
5. **Data Migration**: Plan for configuration and operational data transfer

### Partner Solutions

- **Nokia Private Wireless**: Available in Azure Marketplace
- **Ericsson Private Networks**: Available in Azure Marketplace
- **Custom Integration**: Direct partnership with radio equipment vendors

## Performance Optimization

### Edge Computing Workloads

Deploy containerized applications alongside the 5G core for minimal latency:

```bash
# Deploy real-time analytics workload
kubectl apply -f edge-workloads/ \
    --kubeconfig custom-location-kubeconfig
```

### Network Optimization

- Configure quality of service (QoS) policies per application
- Implement network slicing for traffic isolation
- Use Azure Monitor for performance tracking

### Cost Optimization

- Right-size Azure Stack Edge deployment
- Optimize container resource allocation
- Consider reserved instances for long-term deployments

## Support

For issues with this infrastructure code:

1. **Azure Private 5G Core**: Contact Microsoft Azure Support
2. **Infrastructure Issues**: Refer to the original recipe documentation
3. **Radio Equipment**: Contact your 5G equipment vendor
4. **Spectrum Issues**: Contact your spectrum provider/regulator

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-07-12 | Initial release with Bicep, Terraform, and Bash implementations |

---

**Note**: This infrastructure code implements the complete solution described in the recipe "Industrial 5G Networks for Edge Computing". Ensure you have the necessary hardware, spectrum licenses, and Azure permissions before deployment.