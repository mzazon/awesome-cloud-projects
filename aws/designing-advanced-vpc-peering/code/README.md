# Infrastructure as Code for Designing Advanced VPC Peering with Complex Routing Scenarios

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Designing Advanced VPC Peering with Complex Routing Scenarios".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a sophisticated multi-region VPC peering architecture with:

- **4 AWS Regions**: US-East-1 (Primary Hub), US-West-2 (DR Hub), EU-West-1 (Regional Hub), AP-Southeast-1 (Regional Spoke)
- **8 VPCs**: Hub and spoke VPCs across regions with strategic CIDR allocation
- **Complex Routing**: Hub-and-spoke topology with transit routing capabilities
- **Cross-Region DNS**: Route 53 Resolver for unified DNS resolution
- **Monitoring**: CloudWatch alarms for DNS and connectivity monitoring

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- Permissions for VPC, Route Tables, Route 53, and CloudWatch operations across multiple regions
- Understanding of advanced networking concepts and CIDR block planning
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.5+ (for Terraform implementation)
- Estimated cost: $400-600/month for VPC peering connections and data transfer

> **Warning**: Cross-region data transfer charges can be substantial. Monitor your usage carefully and implement cost controls to prevent unexpected charges.

## Quick Start

### Using CloudFormation

```bash
# Deploy the multi-region infrastructure
aws cloudformation create-stack \
    --stack-name multi-region-vpc-peering \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-global-network \
                 ParameterKey=Environment,ParameterValue=production \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name multi-region-vpc-peering \
    --region us-east-1 \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK in all required regions
cdk bootstrap aws://ACCOUNT-ID/us-east-1
cdk bootstrap aws://ACCOUNT-ID/us-west-2
cdk bootstrap aws://ACCOUNT-ID/eu-west-1
cdk bootstrap aws://ACCOUNT-ID/ap-southeast-1

# Deploy the infrastructure
cdk deploy --all

# View deployed resources
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK in all required regions
cdk bootstrap aws://ACCOUNT-ID/us-east-1
cdk bootstrap aws://ACCOUNT-ID/us-west-2
cdk bootstrap aws://ACCOUNT-ID/eu-west-1
cdk bootstrap aws://ACCOUNT-ID/ap-southeast-1

# Deploy the infrastructure
cdk deploy --all

# View deployed resources
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
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

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment
aws ec2 describe-vpc-peering-connections \
    --region us-east-1 \
    --query 'VpcPeeringConnections[*].[VpcPeeringConnectionId,Status.Code]' \
    --output table
```

## Configuration Options

### Environment Variables (for Bash Scripts)

```bash
export PROJECT_NAME="my-global-network"
export PRIMARY_REGION="us-east-1"
export SECONDARY_REGION="us-west-2"
export EU_REGION="eu-west-1"
export APAC_REGION="ap-southeast-1"
```

### CloudFormation Parameters

- `ProjectName`: Name prefix for all resources (default: "global-peering")
- `Environment`: Environment tag (dev/staging/production)
- `HubCidr`: CIDR block for primary hub VPC (default: "10.0.0.0/16")
- `EnableDnsResolution`: Enable cross-region DNS resolution (default: true)

### Terraform Variables

```hcl
# terraform.tfvars
project_name = "my-global-network"
environment = "production"
regions = {
  primary   = "us-east-1"
  secondary = "us-west-2"
  eu        = "eu-west-1"
  apac      = "ap-southeast-1"
}
enable_dns_resolver = true
enable_monitoring = true
```

### CDK Configuration

Both CDK implementations support configuration through `cdk.json`:

```json
{
  "context": {
    "projectName": "my-global-network",
    "environment": "production",
    "enableDnsResolver": true,
    "enableMonitoring": true,
    "regions": {
      "primary": "us-east-1",
      "secondary": "us-west-2",
      "eu": "eu-west-1",
      "apac": "ap-southeast-1"
    }
  }
}
```

## Validation & Testing

### Verify VPC Peering Connections

```bash
# Check all peering connections status
aws ec2 describe-vpc-peering-connections \
    --region us-east-1 \
    --query 'VpcPeeringConnections[*].[VpcPeeringConnectionId,Status.Code,AccepterVpcInfo.Region]' \
    --output table
```

### Test Route Table Configuration

```bash
# Get stack outputs for route table IDs
aws cloudformation describe-stacks \
    --stack-name multi-region-vpc-peering \
    --region us-east-1 \
    --query 'Stacks[0].Outputs[?OutputKey==`HubRouteTableId`].OutputValue' \
    --output text

# Verify routes in hub route table
aws ec2 describe-route-tables \
    --region us-east-1 \
    --route-table-ids <ROUTE-TABLE-ID> \
    --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,VpcPeeringConnectionId,State]' \
    --output table
```

### Validate DNS Resolution

```bash
# Check Route 53 Resolver rule associations
aws route53resolver list-resolver-rule-associations \
    --region us-east-1 \
    --query 'ResolverRuleAssociations[*].[VpcId,ResolverRuleId,Status]' \
    --output table
```

## Monitoring and Observability

### CloudWatch Metrics

The implementation includes monitoring for:

- VPC Peering connection status
- Route 53 Resolver query failures
- Cross-region data transfer volumes
- Network performance metrics

### Access CloudWatch Dashboard

```bash
# View DNS resolution metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Route53Resolver \
    --metric-name QueryCount \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 3600 \
    --statistics Sum \
    --region us-east-1
```

## Troubleshooting

### Common Issues

1. **Peering Connection Stuck in Pending**: Ensure IAM permissions in accepter region
2. **Route Table Conflicts**: Verify CIDR blocks don't overlap
3. **DNS Resolution Failures**: Check Route 53 Resolver endpoint status
4. **Cross-Region Connectivity**: Verify security groups allow traffic

### Debug Commands

```bash
# Check VPC peering connection details
aws ec2 describe-vpc-peering-connections \
    --region us-east-1 \
    --vpc-peering-connection-ids <CONNECTION-ID>

# Verify route propagation
aws ec2 describe-route-tables \
    --region us-east-1 \
    --filters "Name=vpc-id,Values=<VPC-ID>"

# Check DNS resolver status
aws route53resolver get-resolver-rule \
    --resolver-rule-id <RULE-ID> \
    --region us-east-1
```

## Security Considerations

### Network Security

- All VPC peering connections use private IP addresses only
- No internet gateway access between peered VPCs
- Route tables configured with least privilege principles
- Security groups and NACLs should be configured per application requirements

### IAM Permissions

Required IAM permissions for deployment:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*Vpc*",
        "ec2:*Route*",
        "ec2:*Subnet*",
        "route53resolver:*",
        "cloudwatch:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Cost Optimization

### Cost Factors

- VPC Peering connections: ~$0.01/hour per connection
- Cross-region data transfer: $0.02/GB
- Route 53 Resolver queries: $0.40 per million queries
- CloudWatch metrics and alarms: $0.30 per metric per month

### Cost Monitoring

```bash
# Enable cost allocation tags
aws ec2 create-tags \
    --resources <RESOURCE-ID> \
    --tags Key=Project,Value=GlobalPeering Key=Environment,Value=Production

# Monitor data transfer costs
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name multi-region-vpc-peering \
    --region us-east-1

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name multi-region-vpc-peering \
    --region us-east-1 \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy all CDK stacks
cdk destroy --all

# Confirm destruction
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
aws ec2 describe-vpcs \
    --region us-east-1 \
    --filters "Name=tag:Project,Values=<PROJECT-NAME>" \
    --query 'Vpcs[*].VpcId'
```

## Advanced Usage

### Extending the Architecture

1. **Add New Regions**: Modify the IaC to include additional regions
2. **Implement Transit Gateway**: Upgrade to AWS Transit Gateway for more complex routing
3. **Add VPN Connectivity**: Integrate Site-to-Site VPN for hybrid connectivity
4. **Implement Network Segmentation**: Add additional spoke VPCs with micro-segmentation

### Integration with Other Services

- **AWS Direct Connect**: For dedicated network connections
- **AWS Global Accelerator**: For improved global application performance
- **AWS WAF**: For web application firewall protection
- **AWS Shield**: For DDoS protection

## Support and Documentation

- [AWS VPC Peering Guide](https://docs.aws.amazon.com/vpc/latest/peering/)
- [Route 53 Resolver Documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver.html)
- [Multi-Region Networking Best Practices](https://docs.aws.amazon.com/whitepapers/latest/aws-vpc-connectivity-options/aws-vpc-connectivity-options.html)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.