# Infrastructure as Code for Site-to-Site VPN Connections with AWS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Site-to-Site VPN Connections with AWS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for VPC, EC2, and VPN resources
- Static public IP address for your on-premises VPN device
- On-premises router/firewall with IPsec and BGP capabilities
- Basic knowledge of networking concepts (BGP, IPsec, routing)

### Required AWS Permissions

Your AWS credentials must have permissions for:
- VPC creation and management
- EC2 instance and security group management
- VPN Gateway and Customer Gateway creation
- Site-to-Site VPN connection management
- CloudWatch dashboard creation
- Route table management

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name vpn-site-to-site-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=CustomerGatewayPublicIP,ParameterValue=YOUR_PUBLIC_IP \
                 ParameterKey=CustomerGatewayBGPASN,ParameterValue=65000 \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name vpn-site-to-site-stack \
    --query 'Stacks[0].StackStatus'

# Get VPN configuration
aws cloudformation describe-stacks \
    --stack-name vpn-site-to-site-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install

# Configure your customer gateway IP
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy with customer gateway IP parameter
cdk deploy --parameters customerGatewayPublicIP=YOUR_PUBLIC_IP

# View outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt

# Configure environment
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy with customer gateway IP parameter
cdk deploy --parameters customerGatewayPublicIP=YOUR_PUBLIC_IP

# View outputs
cdk ls --long
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
customer_gateway_public_ip = "YOUR_PUBLIC_IP"
customer_gateway_bgp_asn   = 65000
aws_bgp_asn               = 64512
aws_region                = "us-east-1"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export CGW_PUBLIC_IP="YOUR_PUBLIC_IP"
export CGW_BGP_ASN="65000"
export AWS_BGP_ASN="64512"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Configuration

### Customer Gateway Configuration

Before deploying, you must specify your on-premises VPN device's public IP address:

1. **CloudFormation**: Set the `CustomerGatewayPublicIP` parameter
2. **CDK**: Use the `customerGatewayPublicIP` parameter
3. **Terraform**: Set `customer_gateway_public_ip` in `terraform.tfvars`
4. **Bash**: Set the `CGW_PUBLIC_IP` environment variable

### BGP ASN Configuration

The default BGP ASN values are:
- **Customer Gateway ASN**: 65000 (configurable)
- **AWS Virtual Private Gateway ASN**: 64512 (configurable)

These can be customized in each implementation's variables/parameters.

## Post-Deployment Configuration

After deploying the infrastructure, you must configure your on-premises VPN device:

1. **Download VPN Configuration**:
   ```bash
   # Get the VPN connection ID from outputs
   VPN_CONNECTION_ID=$(aws cloudformation describe-stacks \
       --stack-name vpn-site-to-site-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`VPNConnectionId`].OutputValue' \
       --output text)
   
   # Download customer gateway configuration
   aws ec2 describe-vpn-connections \
       --vpn-connection-ids ${VPN_CONNECTION_ID} \
       --query 'VpnConnections[0].CustomerGatewayConfiguration' \
       --output text > vpn-config.txt
   ```

2. **Configure Your VPN Device**: Use the configuration in `vpn-config.txt` to set up your on-premises VPN appliance

3. **Verify Tunnel Status**:
   ```bash
   aws ec2 describe-vpn-connections \
       --vpn-connection-ids ${VPN_CONNECTION_ID} \
       --query 'VpnConnections[0].VgwTelemetry'
   ```

## Testing Connectivity

Once your VPN tunnels are established:

1. **Test Instance Access**:
   ```bash
   # Get test instance IP from outputs
   TEST_INSTANCE_IP=$(aws cloudformation describe-stacks \
       --stack-name vpn-site-to-site-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`TestInstancePrivateIP`].OutputValue' \
       --output text)
   
   # Test connectivity from on-premises
   ping ${TEST_INSTANCE_IP}
   ```

2. **Monitor VPN Metrics**:
   ```bash
   # Check CloudWatch dashboard
   aws cloudwatch get-dashboard \
       --dashboard-name VPN-Monitoring-Dashboard
   ```

## Architecture Overview

The deployed infrastructure includes:

- **VPC**: Isolated network environment (172.31.0.0/16)
- **Subnets**: Public and private subnets across multiple AZs
- **Customer Gateway**: Represents your on-premises VPN device
- **Virtual Private Gateway**: AWS-side VPN endpoint
- **VPN Connection**: IPsec tunnels with BGP routing
- **EC2 Instance**: Test instance in private subnet
- **Security Groups**: Network access controls
- **CloudWatch Dashboard**: VPN monitoring and metrics

## Cost Considerations

- **VPN Connection**: ~$0.05 per hour (~$36/month)
- **Virtual Private Gateway**: No additional charge
- **Data Transfer**: Standard AWS data transfer rates apply
- **EC2 Instance**: t3.micro instance charges
- **CloudWatch**: Dashboard and metrics charges

## Security Features

- **IPsec Encryption**: All traffic encrypted in transit
- **BGP Authentication**: Secure routing protocol
- **Security Groups**: Restrictive network access controls
- **Private Subnets**: No direct internet access
- **Monitoring**: CloudWatch logging and alerting

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name vpn-site-to-site-stack

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name vpn-site-to-site-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
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

## Troubleshooting

### Common Issues

1. **VPN Tunnels Show DOWN Status**:
   - Verify your on-premises device is configured with the correct parameters
   - Check IPsec settings and pre-shared keys
   - Ensure your firewall allows IPsec traffic (UDP 500, 4500)

2. **BGP Routes Not Propagating**:
   - Verify BGP ASN configuration matches on both sides
   - Check route propagation is enabled on route tables
   - Ensure your on-premises device is advertising routes

3. **Cannot Connect to Test Instance**:
   - Verify VPN tunnels are UP
   - Check security group rules allow traffic from on-premises
   - Ensure route tables have proper VPN routes

### Debug Commands

```bash
# Check VPN connection details
aws ec2 describe-vpn-connections --vpn-connection-ids YOUR_VPN_ID

# Check route table propagation
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=YOUR_VPC_ID"

# Check security group rules
aws ec2 describe-security-groups --group-ids YOUR_SG_ID

# Monitor VPN metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/VPN \
    --metric-name VpnState \
    --dimensions Name=VpnId,Value=YOUR_VPN_ID \
    --start-time 2023-01-01T00:00:00Z \
    --end-time 2023-01-01T23:59:59Z \
    --period 300 \
    --statistics Average
```

## Customization

### Variables and Parameters

Each implementation supports customization through variables:

- **VPC CIDR**: Default 172.31.0.0/16
- **Subnet CIDRs**: Configurable public/private ranges
- **Instance Type**: Default t3.micro
- **BGP ASNs**: Customer and AWS side ASNs
- **Availability Zones**: Multi-AZ deployment options

### Advanced Configuration

- **Multiple Customer Gateways**: Deploy additional customer gateways for multi-site connectivity
- **Transit Gateway**: Integrate with AWS Transit Gateway for centralized routing
- **Route Filtering**: Implement BGP route filtering and path selection
- **Monitoring Enhancement**: Add custom CloudWatch alarms and SNS notifications

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../vpn-connections-aws-site-to-site-vpn.md)
2. Review [AWS Site-to-Site VPN documentation](https://docs.aws.amazon.com/vpn/latest/s2svpn/)
3. Consult [AWS VPN troubleshooting guides](https://docs.aws.amazon.com/vpn/latest/s2svpn/Troubleshooting.html)
4. Verify your on-premises VPN device compatibility

## Additional Resources

- [AWS VPN Configuration Examples](https://docs.aws.amazon.com/vpn/latest/s2svpn/Examples.html)
- [BGP Routing with VPN Connections](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPNRoutingTypes.html)
- [VPN CloudWatch Metrics](https://docs.aws.amazon.com/vpn/latest/s2svpn/monitoring-cloudwatch-vpn.html)
- [VPN Connection Logging](https://docs.aws.amazon.com/vpn/latest/s2svpn/monitoring-logs.html)