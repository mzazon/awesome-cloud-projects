# Terraform Infrastructure for Secure Multi-Cloud Connectivity

This directory contains Terraform Infrastructure as Code (IaC) for implementing secure multi-cloud connectivity using Google Cloud Platform's Network Connectivity Center and Cloud NAT services.

## Architecture Overview

This Terraform configuration deploys:

- **Network Connectivity Center Hub**: Central orchestration point for multi-cloud connectivity
- **4 VPC Networks**: Hub, Production, Development, and Shared Services networks
- **4 Network Spokes**: VPC spokes connecting each network to the NCC hub
- **HA VPN Gateway**: High-availability VPN gateway for external connectivity
- **Cloud Routers**: BGP routers for dynamic routing with ASN configuration
- **Cloud NAT Gateways**: Secure outbound internet access for each VPC
- **Firewall Rules**: Security controls for inter-VPC and external communication
- **VPN Tunnel**: Secure connection to external cloud provider

## Prerequisites

### Required Tools
- [Terraform](https://www.terraform.io/downloads) >= 1.6
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (gcloud)
- [jq](https://stedolan.github.io/jq/) (optional, for parsing outputs)

### Required Permissions
Your Google Cloud account must have the following IAM roles:
- `Compute Network Admin` (roles/compute.networkAdmin)
- `Network Connectivity Admin` (roles/networkconnectivity.networkconnectivityAdmin)
- `Service Usage Admin` (roles/serviceusage.serviceUsageAdmin)
- `Project Editor` (roles/editor) or equivalent custom role

### API Services
The following APIs will be automatically enabled:
- Compute Engine API (compute.googleapis.com)
- Network Connectivity API (networkconnectivity.googleapis.com)
- Cloud Resource Manager API (cloudresourcemanager.googleapis.com)

## Quick Start

### 1. Authentication Setup

```bash
# Authenticate with Google Cloud
gcloud auth login

# Set your project ID
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID

# Enable Application Default Credentials for Terraform
gcloud auth application-default login
```

### 2. Terraform Initialization

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init
```

### 3. Configuration

Create a `terraform.tfvars` file with your specific configuration:

```hcl
# Required Variables
project_id = "your-project-id"
region     = "us-central1"

# Optional: Customize network configuration
hub_subnet_cidr    = "10.1.0.0/24"
prod_subnet_cidr   = "192.168.1.0/24"
dev_subnet_cidr    = "192.168.2.0/24"
shared_subnet_cidr = "192.168.3.0/24"

# VPN Configuration for External Cloud
external_cloud_vpn_ip      = "203.0.113.10"  # Replace with actual external VPN IP
vpn_shared_secret          = "your-secure-shared-secret"
external_cloud_bgp_peer_ip = "169.254.1.2"

# BGP ASN Configuration
hub_bgp_asn            = 64512
external_cloud_bgp_asn = 65001

# Environment and Labeling
environment = "production"

# Additional security configuration
external_network_cidrs = [
  "10.0.0.0/8",     # On-premises networks
  "172.16.0.0/12"   # External cloud networks
]
```

### 4. Deployment

```bash
# Validate the configuration
terraform validate

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### 5. Verification

```bash
# Verify Network Connectivity Center hub
gcloud network-connectivity hubs list

# Check VPC networks
gcloud compute networks list

# Verify VPN gateway status
gcloud compute vpn-gateways list --region=us-central1

# Check BGP sessions
gcloud compute routers get-status hub-router --region=us-central1
```

## Configuration Variables

### Required Variables

| Variable | Description | Type |
|----------|-------------|------|
| `project_id` | GCP project ID | string |

### Optional Variables

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| `region` | GCP region for resources | `us-central1` | string |
| `environment` | Environment label | `production` | string |
| `ncc_hub_name` | Network Connectivity Center hub name | `multi-cloud-hub` | string |
| `hub_subnet_cidr` | Hub subnet CIDR range | `10.1.0.0/24` | string |
| `prod_subnet_cidr` | Production subnet CIDR range | `192.168.1.0/24` | string |
| `dev_subnet_cidr` | Development subnet CIDR range | `192.168.2.0/24` | string |
| `shared_subnet_cidr` | Shared services subnet CIDR range | `192.168.3.0/24` | string |
| `external_cloud_vpn_ip` | External cloud VPN gateway IP | `172.16.1.1` | string |
| `vpn_shared_secret` | VPN tunnel shared secret | `your-shared-secret-here` | string |
| `external_cloud_bgp_asn` | External cloud BGP ASN | `65001` | number |

For a complete list of variables, see [variables.tf](./variables.tf).

## Outputs

After successful deployment, Terraform will output important information including:

- Network Connectivity Center hub details
- VPC network and subnet information  
- VPN gateway external IP addresses
- BGP configuration details
- Cloud NAT gateway information
- Next steps for completing external connectivity

View outputs:
```bash
# Show all outputs
terraform output

# Show specific output
terraform output vpn_gateway_information
```

## Security Considerations

### Firewall Rules
The configuration includes comprehensive firewall rules:
- **Hub VPC**: Allows VPN protocols (IKE, ESP, BGP)
- **Production VPC**: Restricted to necessary ports (22, 80, 443)
- **Development VPC**: Additional development ports (8080)
- **Shared Services VPC**: DNS and common services access

### VPN Security
- Uses IKEv2 for strong encryption
- Implements BGP for dynamic routing
- Shared secrets should be complex and rotated regularly

### Network Isolation
- Each VPC maintains separate address spaces
- Communication controlled through NCC hub routing
- Private Google Access enabled for secure API access

## External Cloud Provider Configuration

### AWS Configuration Example

If connecting to AWS, configure your AWS VPN Gateway:

```bash
# AWS CLI example for VPN connection
aws ec2 create-vpn-connection \
    --type ipsec.1 \
    --customer-gateway-id cgw-xxxxxxxxx \
    --vpn-gateway-id vgw-xxxxxxxxx \
    --options StaticRoutesOnly=false
```

### Azure Configuration Example

For Azure VPN Gateway configuration:

```bash
# Azure CLI example
az network vpn-connection create \
    --resource-group myResourceGroup \
    --name myConnection \
    --vnet-gateway1 myVpnGateway \
    --local-gateway2 myLocalGateway \
    --location eastus \
    --shared-key "your-shared-secret-here"
```

## Monitoring and Troubleshooting

### VPN Tunnel Status
```bash
# Check VPN tunnel status
gcloud compute vpn-tunnels describe tunnel-to-external-cloud \
    --region=us-central1

# Monitor BGP sessions
gcloud compute routers get-status hub-router \
    --region=us-central1 \
    --format="table(result.bgpPeerStatus[].name,result.bgpPeerStatus[].state)"
```

### Network Connectivity Testing
```bash
# Test connectivity between VPCs (requires test instances)
gcloud compute ssh test-instance-prod --command="ping 192.168.2.10"

# Check Cloud NAT logs
gcloud logging read "resource.type=nat_gateway" --limit=10
```

### Common Issues

1. **VPN Tunnel Down**: Check shared secret and external gateway configuration
2. **BGP Session Not Establishing**: Verify ASN configuration and peer IP addresses
3. **Cross-VPC Connectivity Issues**: Check firewall rules and NCC spoke status
4. **NAT Gateway Issues**: Verify router configuration and IP allocation

## Cost Optimization

### Resource Costs
- **VPN Gateway**: ~$36/month per interface
- **Cloud NAT**: ~$45/month + data processing charges
- **Network Connectivity Center**: ~$0.12/hour per spoke
- **Data Transfer**: Variable based on usage

### Optimization Tips
- Use regional resources to minimize cross-region charges
- Monitor NAT gateway IP allocation and usage
- Implement VPN tunnel redundancy only when necessary
- Regular review of firewall rules to minimize data processing

## Maintenance and Updates

### Terraform State Management
```bash
# Backup state file before major changes
cp terraform.tfstate terraform.tfstate.backup

# Import existing resources if needed
terraform import google_compute_network.hub_vpc projects/PROJECT_ID/global/networks/NETWORK_NAME
```

### Updates and Upgrades
```bash
# Update Terraform providers
terraform init -upgrade

# Plan updates
terraform plan -out=update.tfplan

# Apply updates
terraform apply update.tfplan
```

## Cleanup

### Complete Infrastructure Removal
```bash
# Destroy all resources
terraform destroy

# Confirm removal
terraform state list  # Should be empty
```

### Selective Resource Removal
```bash
# Remove specific resources
terraform destroy -target=google_compute_vpn_tunnel.tunnel_to_external_cloud
```

## Support and Documentation

### Additional Resources
- [Google Cloud Network Connectivity Center Documentation](https://cloud.google.com/network-connectivity/docs/network-connectivity-center)
- [Google Cloud VPN Documentation](https://cloud.google.com/network-connectivity/docs/vpn)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help
- [Google Cloud Support](https://cloud.google.com/support)
- [Terraform Community](https://discuss.hashicorp.com/c/terraform-core)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/google-cloud-platform+terraform)

## Contributing

When making changes to this infrastructure:

1. Test changes in a development environment first
2. Update documentation for any configuration changes
3. Follow Terraform best practices for resource naming
4. Include validation rules for new variables
5. Update outputs for new resources