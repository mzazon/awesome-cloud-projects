# Infrastructure as Code for Secure Multi-Cloud Connectivity with Cloud NAT and Network Connectivity Center

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure Multi-Cloud Connectivity with Cloud NAT and Network Connectivity Center".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Google Cloud project with billing enabled
- Appropriate IAM permissions:
  - Compute Network Admin
  - Network Connectivity Admin
  - Service Account Admin
  - Project IAM Admin
- Google Cloud CLI (gcloud) installed and configured
- Terraform (>= 1.5.0) for Terraform deployment
- Access to external cloud provider for VPN configuration
- Network administrator privileges for routing and firewall setup

### Cost Estimation
- Estimated monthly cost: $150-300
- Components: VPN gateways, NAT gateways, data transfer, and compute resources

### External Dependencies
- On-premises network infrastructure with VPN capabilities
- External cloud provider VPN gateway configuration
- BGP routing configuration on external networks

## Quick Start

### Using Infrastructure Manager

```bash
# Set up environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export DEPLOYMENT_NAME="multi-cloud-connectivity"

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source infrastructure-manager/ \
    --inputs-file infrastructure-manager/inputs.yaml

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export RANDOM_SUFFIX="abc123"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud network-connectivity hubs list --global
gcloud compute networks list
```

## Configuration

### Infrastructure Manager Configuration

The Infrastructure Manager implementation uses YAML configuration files:

- `main.yaml`: Primary infrastructure definition
- `inputs.yaml`: Customizable input parameters
- `outputs.yaml`: Resource outputs and endpoints

Key configurable parameters:
- `project_id`: Google Cloud project ID
- `region`: Primary deployment region
- `hub_name`: Network Connectivity Center hub name
- `vpc_networks`: VPC network configurations
- `external_vpn_config`: External cloud provider VPN settings

### Terraform Configuration

The Terraform implementation provides comprehensive variable customization:

- `variables.tf`: All configurable parameters
- `terraform.tfvars.example`: Example configuration file
- `main.tf`: Resource definitions
- `outputs.tf`: Infrastructure outputs

Key variables:
```hcl
variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Primary deployment region"
  type        = string
  default     = "us-central1"
}

variable "hub_name" {
  description = "Network Connectivity Center hub name"
  type        = string
  default     = "multi-cloud-hub"
}

variable "vpc_networks" {
  description = "VPC network configurations"
  type = map(object({
    name_suffix = string
    subnet_cidr = string
    description = string
  }))
}
```

### Bash Scripts Configuration

Environment variables for script-based deployment:

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export HUB_NAME="multi-cloud-hub"

# Optional customization
export VPC_HUB_NAME="hub-vpc-${RANDOM_SUFFIX}"
export VPC_PROD_NAME="prod-vpc-${RANDOM_SUFFIX}"
export VPC_DEV_NAME="dev-vpc-${RANDOM_SUFFIX}"
export VPC_SHARED_NAME="shared-vpc-${RANDOM_SUFFIX}"
```

## Deployment

### Infrastructure Manager Deployment

1. **Prepare Service Account**:
   ```bash
   # Create service account for Infrastructure Manager
   gcloud iam service-accounts create infra-manager \
       --display-name="Infrastructure Manager Service Account"
   
   # Grant necessary permissions
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="serviceAccount:infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
       --role="roles/compute.networkAdmin"
   ```

2. **Customize Configuration**:
   ```bash
   # Edit inputs.yaml with your specific values
   vim infrastructure-manager/inputs.yaml
   ```

3. **Deploy Infrastructure**:
   ```bash
   # Create deployment
   gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
       --service-account projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
       --local-source infrastructure-manager/
   ```

### Terraform Deployment

1. **Initialize and Configure**:
   ```bash
   cd terraform/
   terraform init
   
   # Copy and customize variables
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Plan and Apply**:
   ```bash
   # Review planned changes
   terraform plan
   
   # Apply configuration
   terraform apply
   
   # Confirm deployment
   terraform show
   ```

3. **Access Outputs**:
   ```bash
   # View deployment outputs
   terraform output
   terraform output -json > outputs.json
   ```

## Validation

### Network Connectivity Center Validation

```bash
# Verify hub creation and status
gcloud network-connectivity hubs describe ${HUB_NAME} --global

# List attached spokes
gcloud network-connectivity spokes list --hub ${HUB_NAME} --global

# Check spoke connectivity status
gcloud network-connectivity spokes describe prod-spoke --hub ${HUB_NAME} --global
```

### VPC Network Validation

```bash
# Verify VPC networks
gcloud compute networks list --filter="name:(*hub* OR *prod* OR *dev* OR *shared*)"

# Check subnets configuration
gcloud compute networks subnets list --filter="region:${REGION}"

# Validate firewall rules
gcloud compute firewall-rules list --filter="network:(*hub* OR *prod* OR *dev* OR *shared*)"
```

### Cloud NAT Validation

```bash
# Check NAT gateway status
gcloud compute routers get-nat-mapping-info hub-router --region ${REGION} --nat hub-nat-gateway

# Verify NAT configuration across all routers
for router in hub-router prod-router dev-router shared-router; do
  echo "Checking NAT on $router..."
  gcloud compute routers nats list --router $router --region ${REGION}
done
```

### VPN and BGP Validation

```bash
# Check VPN gateway status
gcloud compute vpn-gateways describe hub-vpn-gateway --region ${REGION}

# Verify BGP sessions
gcloud compute routers get-status hub-router --region ${REGION}

# Check VPN tunnel status
gcloud compute vpn-tunnels list --filter="region:${REGION}"
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**:
   ```bash
   # Verify required IAM roles
   gcloud projects get-iam-policy ${PROJECT_ID} \
       --flatten="bindings[].members" \
       --format="table(bindings.role)" \
       --filter="bindings.members:user:$(gcloud config get-value account)"
   ```

2. **Network Connectivity Issues**:
   ```bash
   # Test connectivity between VPCs
   gcloud compute instances create test-vm \
       --subnet prod-subnet \
       --zone ${ZONE} \
       --image-family debian-11 \
       --image-project debian-cloud
   
   # Check routing tables
   gcloud compute routes list --filter="network:prod-vpc-*"
   ```

3. **VPN Connection Problems**:
   ```bash
   # Verify VPN tunnel status
   gcloud compute vpn-tunnels describe tunnel-to-external-cloud --region ${REGION}
   
   # Check BGP peer status
   gcloud compute routers get-status hub-router --region ${REGION} \
       --format="table(result.bgpPeerStatus[].name,result.bgpPeerStatus[].state)"
   ```

### Debugging Commands

```bash
# Enable detailed logging for troubleshooting
export GOOGLE_CLOUD_DEBUG=true

# Check resource quotas
gcloud compute project-info describe --format="table(quotas.metric,quotas.usage,quotas.limit)"

# Monitor deployment logs
gcloud logging read "resource.type=gce_network" --limit=50 --format=json
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}

# Verify resource cleanup
gcloud compute networks list
gcloud network-connectivity hubs list --global
```

### Using Terraform

```bash
cd terraform/

# Plan destruction (review what will be deleted)
terraform plan -destroy

# Destroy infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual verification of cleanup
gcloud compute networks list --filter="name:(*hub* OR *prod* OR *dev* OR *shared*)"
gcloud network-connectivity hubs list --global
```

### Manual Cleanup (Emergency)

If automated cleanup fails, use these commands:

```bash
# Remove spokes first
for spoke in prod-spoke dev-spoke shared-spoke external-cloud-spoke; do
  gcloud network-connectivity spokes delete $spoke --hub ${HUB_NAME} --global --quiet
done

# Remove hub
gcloud network-connectivity hubs delete ${HUB_NAME} --global --quiet

# Remove VPN infrastructure
gcloud compute vpn-tunnels delete tunnel-to-external-cloud --region ${REGION} --quiet
gcloud compute vpn-gateways delete hub-vpn-gateway --region ${REGION} --quiet

# Remove NAT and routers
for router in hub-router prod-router dev-router shared-router; do
  gcloud compute routers delete $router --region ${REGION} --quiet
done

# Remove firewall rules
for rule in hub-allow-vpn prod-allow-internal dev-allow-internal shared-allow-internal prod-allow-egress; do
  gcloud compute firewall-rules delete $rule --quiet
done

# Remove VPC networks
for network in ${VPC_HUB_NAME} ${VPC_PROD_NAME} ${VPC_DEV_NAME} ${VPC_SHARED_NAME}; do
  gcloud compute networks delete $network --quiet
done
```

## Customization

### Adding Additional VPC Networks

To add more VPC networks to the hub-and-spoke architecture:

1. **Terraform**: Add network configuration to `vpc_networks` variable
2. **Infrastructure Manager**: Add network definition to `main.yaml`
3. **Bash Scripts**: Add network creation commands to `deploy.sh`

Example Terraform addition:
```hcl
vpc_networks = {
  hub = {
    name_suffix = "hub"
    subnet_cidr = "10.1.0.0/24"
    description = "Hub VPC for central connectivity"
  }
  staging = {
    name_suffix = "staging"
    subnet_cidr = "192.168.4.0/24"
    description = "Staging environment VPC"
  }
}
```

### External Cloud Provider Integration

To connect additional cloud providers:

1. Configure external VPN gateway information
2. Update BGP ASN numbers for each provider
3. Modify firewall rules for new IP ranges
4. Add hybrid spokes for each external connection

### Security Enhancements

1. **Enable Private Google Access**:
   ```bash
   gcloud compute networks subnets update prod-subnet \
       --enable-private-ip-google-access \
       --region ${REGION}
   ```

2. **Implement Cloud Armor**:
   ```bash
   gcloud compute security-policies create multi-cloud-policy \
       --description "Security policy for multi-cloud connectivity"
   ```

3. **Configure Cloud KMS for VPN encryption**:
   ```bash
   gcloud kms keyrings create vpn-keyring --location ${REGION}
   gcloud kms keys create vpn-key --keyring vpn-keyring --location ${REGION} --purpose encryption
   ```

## Monitoring and Observability

### Network Intelligence Center

```bash
# Enable Network Intelligence Center
gcloud services enable networkmanagement.googleapis.com

# Create connectivity test
gcloud network-management connectivity-tests create test-inter-vpc \
    --source-instance projects/${PROJECT_ID}/zones/${ZONE}/instances/prod-vm \
    --destination-instance projects/${PROJECT_ID}/zones/${ZONE}/instances/dev-vm \
    --protocol TCP \
    --destination-port 80
```

### Cloud Monitoring

```bash
# Create custom dashboards for network monitoring
gcloud monitoring dashboards create --config-from-file monitoring-dashboard.json

# Set up alerting policies
gcloud alpha monitoring policies create --policy-from-file vpc-alerting-policy.yaml
```

## Support

### Documentation References

- [Google Cloud Network Connectivity Center](https://cloud.google.com/network-connectivity/docs/network-connectivity-center)
- [Cloud NAT Documentation](https://cloud.google.com/nat/docs)
- [Cloud VPN Documentation](https://cloud.google.com/network-connectivity/docs/vpn)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Verify IAM permissions and project configuration
4. Use `gcloud help` for CLI command assistance
5. Consult Google Cloud support for production issues

### Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Follow Google Cloud best practices
3. Update documentation for any modifications
4. Validate security implications of changes