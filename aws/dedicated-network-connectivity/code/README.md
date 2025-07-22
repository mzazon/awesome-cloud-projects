# Infrastructure as Code for Dedicated Hybrid Cloud Connectivity

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Dedicated Hybrid Cloud Connectivity".

## Overview

This solution establishes dedicated network connectivity between on-premises infrastructure and AWS using Direct Connect with private and transit virtual interfaces. The architecture provides consistent network performance, enhanced security through private connectivity, reduced data transfer costs, and the ability to access multiple VPCs across regions through a single connection using Direct Connect Gateway and Transit Gateway integration.

## Architecture

The solution deploys:

- **3 VPCs**: Production (10.1.0.0/16), Development (10.2.0.0/16), and Shared Services (10.3.0.0/16)
- **Transit Gateway**: Central hub for multi-VPC connectivity with BGP ASN 64512
- **Direct Connect Gateway**: Bridge between Direct Connect and cloud infrastructure
- **Route 53 Resolver Endpoints**: Inbound and outbound DNS resolution for hybrid environments
- **Security Groups and NACLs**: Layered security controls for hybrid traffic
- **CloudWatch Monitoring**: Dashboards and alarms for connection health and performance
- **VPC Flow Logs**: Comprehensive network traffic monitoring

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS account with appropriate permissions for Direct Connect, VPC, Transit Gateway, and Route 53
- AWS CLI v2 installed and configured (or AWS CloudShell)
- **Important**: Established connection with Direct Connect partner or colocation facility
- On-premises border router supporting BGP and 802.1Q VLAN encapsulation
- Estimated cost: $300-1000/month for 1Gbps dedicated connection plus data transfer charges

> **Note**: Direct Connect requires physical connectivity setup which can take 2-4 weeks. This recipe assumes the physical connection is established.

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name hybrid-connectivity-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectId,ParameterValue=my-project \
                 ParameterKey=OnPremisesCIDR,ParameterValue=10.0.0.0/8 \
                 ParameterKey=OnPremisesASN,ParameterValue=65000 \
                 ParameterKey=AWSASN,ParameterValue=64512 \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name hybrid-connectivity-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --parameters projectId=my-project

# View outputs
npx cdk ls
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters projectId=my-project

# View outputs
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=my-project"

# Apply infrastructure
terraform apply -var="project_id=my-project"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Optional: Set custom configuration
export PROJECT_ID="my-project"
export ON_PREM_CIDR="10.0.0.0/8"
export ON_PREM_ASN="65000"
export AWS_ASN="64512"
./scripts/deploy.sh
```

## Configuration Parameters

| Parameter | Description | Default Value | Required |
|-----------|-------------|---------------|----------|
| `project_id` | Unique identifier for resources | Generated | No |
| `on_premises_cidr` | On-premises network CIDR | 10.0.0.0/8 | Yes |
| `on_premises_asn` | On-premises BGP ASN | 65000 | Yes |
| `aws_asn` | AWS side BGP ASN | 64512 | Yes |
| `aws_region` | AWS region for deployment | Current region | No |
| `private_vif_vlan` | VLAN ID for private VIF | 100 | No |
| `transit_vif_vlan` | VLAN ID for transit VIF | 200 | No |

## Post-Deployment Configuration

### Virtual Interface Setup

After deploying the infrastructure, you'll need to manually configure the Virtual Interfaces through the AWS Direct Connect console:

1. **Create Transit Virtual Interface**:
   - Connection ID: Your Direct Connect connection ID
   - VLAN: 200 (or configured value)
   - BGP ASN: 65000 (or configured value)
   - Direct Connect Gateway: Use the output from deployment
   - Customer Address: 192.168.100.1/30
   - Amazon Address: 192.168.100.2/30

2. **Configure On-Premises Router**:
   ```bash
   # BGP Configuration Template
   router bgp 65000
    bgp router-id 192.168.100.1
    neighbor 192.168.100.2 remote-as 64512
    neighbor 192.168.100.2 password <BGP-AUTH-KEY>
    neighbor 192.168.100.2 timers 10 30
    neighbor 192.168.100.2 soft-reconfiguration inbound
    
    address-family ipv4
     network 10.0.0.0/8
     neighbor 192.168.100.2 activate
     neighbor 192.168.100.2 prefix-list ALLOWED-PREFIXES out
     neighbor 192.168.100.2 prefix-list AWS-PREFIXES in
    exit-address-family
   ```

### DNS Configuration

Configure your on-premises DNS servers to forward AWS queries to the Route 53 Resolver endpoints:

- **Inbound Resolver**: 10.3.1.100 (for on-premises to AWS resolution)
- **Outbound Resolver**: 10.3.1.101 (for AWS to on-premises resolution)

## Validation

### Connectivity Testing

All implementations include testing scripts. After deployment:

```bash
# Test BGP session status
aws directconnect describe-virtual-interfaces \
    --query 'virtualInterfaces[*].{Name:virtualInterfaceName,State:virtualInterfaceState,BGP:bgpStatus}' \
    --output table

# Test Transit Gateway attachments
aws ec2 describe-transit-gateway-attachments \
    --filters Name=transit-gateway-id,Values=<TRANSIT_GATEWAY_ID> \
    --query 'TransitGatewayAttachments[*].{Type:ResourceType,ID:ResourceId,State:State}' \
    --output table

# Test DNS resolver endpoints
aws route53resolver list-resolver-endpoints \
    --query 'ResolverEndpoints[*].{Direction:Direction,Status:Status,IPs:IpAddressCount}' \
    --output table
```

### Monitoring

Access the CloudWatch dashboard named "DirectConnect-{PROJECT_ID}" to monitor:

- Connection state and health
- Bandwidth utilization (ingress/egress)
- Packet statistics
- BGP session status

## Security Considerations

The deployed infrastructure includes:

- **Security Groups**: Restrict DNS traffic to on-premises networks
- **NACLs**: Subnet-level access control for HTTPS and SSH
- **VPC Flow Logs**: Comprehensive network traffic monitoring
- **BGP Prefix Lists**: Control route advertisements between networks

## Troubleshooting

### Common Issues

1. **BGP Session Down**:
   - Verify physical Direct Connect connection is active
   - Check BGP ASN configuration matches on both sides
   - Validate BGP authentication key (if configured)

2. **DNS Resolution Failures**:
   - Ensure security groups allow DNS traffic (port 53 UDP/TCP)
   - Verify resolver endpoint IP addresses are reachable
   - Check outbound resolver rules are configured

3. **VPC Connectivity Issues**:
   - Verify Transit Gateway route table has correct routes
   - Check VPC route tables point to Transit Gateway for on-premises traffic
   - Ensure security groups allow required application traffic

### Logs and Monitoring

- **VPC Flow Logs**: `/aws/vpc/flowlogs-{PROJECT_ID}`
- **CloudWatch Alarms**: Monitor for connection failures
- **Direct Connect Metrics**: Available in CloudWatch under `AWS/DX` namespace

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name hybrid-connectivity-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name hybrid-connectivity-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
npx cdk destroy     # or cdk destroy for Python

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=my-project"

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Cost Optimization

### Estimated Monthly Costs

- **Direct Connect (1Gbps)**: $300-1000/month (varies by location)
- **Transit Gateway**: $36/month + $0.05/GB processed
- **Route 53 Resolver Endpoints**: $0.125/hour per endpoint (~$180/month for 2 endpoints)
- **VPC Flow Logs**: $0.50/GB ingested
- **CloudWatch**: $0.30/alarm + dashboard costs

### Cost Reduction Strategies

1. **Right-size Direct Connect**: Monitor bandwidth utilization to optimize connection speed
2. **Optimize Data Transfer**: Use compression and efficient protocols
3. **Selective Flow Logs**: Enable only for critical VPCs or specific subnets
4. **Reserved Capacity**: Consider AWS Direct Connect dedicated connections for predictable workloads

## Support and Contributing

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS service limits and quotas
3. Consult the original recipe documentation
4. Reference AWS Direct Connect documentation

## Advanced Configuration

### Multi-Region Deployment

To deploy across multiple regions:

```bash
# Deploy to primary region
terraform apply -var="project_id=my-project" -var="aws_region=us-east-1"

# Deploy to secondary region
terraform apply -var="project_id=my-project" -var="aws_region=us-west-2"
```

### Custom Network Segmentation

Modify the VPC CIDR blocks in the configuration files:

```yaml
# CloudFormation parameter
ProductionVPCCIDR: 10.1.0.0/16
DevelopmentVPCCIDR: 10.2.0.0/16
SharedServicesVPCCIDR: 10.3.0.0/16
```

```hcl
# Terraform variable
variable "vpc_cidrs" {
  description = "CIDR blocks for VPCs"
  type = map(string)
  default = {
    production = "10.1.0.0/16"
    development = "10.2.0.0/16"
    shared = "10.3.0.0/16"
  }
}
```

### High Availability

For production deployments, consider:

1. **Redundant Direct Connect connections** in different locations
2. **Multi-AZ Transit Gateway attachments** for high availability
3. **Backup VPN connections** for failover scenarios
4. **Cross-region replication** for disaster recovery

## License

This infrastructure code is provided under the same terms as the original recipe documentation.