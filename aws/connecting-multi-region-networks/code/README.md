# Infrastructure as Code for Connecting Multi-Region Networks with Transit Gateway

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Connecting Multi-Region Networks with Transit Gateway".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a scalable multi-region network architecture using AWS Transit Gateway with cross-region peering. The solution establishes:

- Transit Gateways in two AWS regions (us-east-1 and us-west-2)
- Multiple VPCs in each region with non-overlapping CIDR blocks
- Cross-region peering attachments for secure connectivity
- Custom route tables for granular routing control
- CloudWatch monitoring for network observability
- Security groups configured for cross-region access

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Transit Gateway (create, delete, modify)
  - VPC (create, delete, modify)
  - CloudWatch (create dashboards, view metrics)
  - Route53 (if DNS resolution is needed)
  - IAM (for service-linked roles)
- Understanding of VPC networking concepts and CIDR blocks
- Familiarity with multi-region AWS architectures
- Estimated cost: $150-200/month for Transit Gateway attachments, data processing, and cross-region data transfer

## Quick Start

### Using CloudFormation

```bash
# Deploy the multi-region Transit Gateway infrastructure
aws cloudformation create-stack \
    --stack-name multi-region-tgw-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-tgw-project \
                 ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
                 ParameterKey=SecondaryRegion,ParameterValue=us-west-2 \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name multi-region-tgw-stack \
    --region us-east-1 \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
# Install dependencies and deploy
cd cdk-typescript/
npm install

# Bootstrap CDK in both regions (if not already done)
cdk bootstrap aws://ACCOUNT-NUMBER/us-east-1
cdk bootstrap aws://ACCOUNT-NUMBER/us-west-2

# Deploy the infrastructure
cdk deploy --all

# View deployment outputs
cdk ls
```

### Using CDK Python

```bash
# Install dependencies and deploy
cd cdk-python/
pip install -r requirements.txt

# Bootstrap CDK in both regions (if not already done)
cdk bootstrap aws://ACCOUNT-NUMBER/us-east-1
cdk bootstrap aws://ACCOUNT-NUMBER/us-west-2

# Deploy the infrastructure
cdk deploy --all

# View deployment outputs
cdk ls
```

### Using Terraform

```bash
# Initialize and deploy
cd terraform/
terraform init

# Review the planned changes
terraform plan \
    -var="project_name=my-tgw-project" \
    -var="primary_region=us-east-1" \
    -var="secondary_region=us-west-2"

# Apply the configuration
terraform apply \
    -var="project_name=my-tgw-project" \
    -var="primary_region=us-east-1" \
    -var="secondary_region=us-west-2"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Monitor deployment progress
# The script will provide status updates and resource IDs
```

## Validation & Testing

After deployment, verify the infrastructure is working correctly:

### 1. Check Transit Gateway Status

```bash
# Verify Transit Gateways are available
aws ec2 describe-transit-gateways \
    --filters "Name=state,Values=available" \
    --query 'TransitGateways[].{ID:TransitGatewayId,State:State,Region:OwnerId}'
```

### 2. Verify Cross-Region Peering

```bash
# Check peering attachment status
aws ec2 describe-transit-gateway-peering-attachments \
    --filters "Name=state,Values=available" \
    --query 'TransitGatewayPeeringAttachments[].{ID:TransitGatewayAttachmentId,State:State}'
```

### 3. Test Route Propagation

```bash
# Check routes in Transit Gateway route tables
aws ec2 search-transit-gateway-routes \
    --transit-gateway-route-table-id <ROUTE_TABLE_ID> \
    --filters "Name=state,Values=active" \
    --query 'Routes[].{Destination:DestinationCidrBlock,State:State}'
```

### 4. Monitor CloudWatch Metrics

```bash
# View Transit Gateway metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/TransitGateway \
    --metric-name BytesIn \
    --dimensions Name=TransitGateway,Value=<TGW_ID> \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name multi-region-tgw-stack \
    --region us-east-1

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name multi-region-tgw-stack \
    --region us-east-1 \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy all CDK stacks
cd cdk-typescript/  # or cdk-python/
cdk destroy --all

# Confirm destruction when prompted
```

### Using Terraform

```bash
# Destroy the infrastructure
cd terraform/
terraform destroy \
    -var="project_name=my-tgw-project" \
    -var="primary_region=us-east-1" \
    -var="secondary_region=us-west-2"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm resource deletion when prompted
```

## Customization

### Configuration Variables

All implementations support customization through variables:

- **project_name**: Unique identifier for your resources
- **primary_region**: First AWS region (default: us-east-1)
- **secondary_region**: Second AWS region (default: us-west-2)
- **primary_vpc_a_cidr**: CIDR block for first VPC in primary region
- **primary_vpc_b_cidr**: CIDR block for second VPC in primary region
- **secondary_vpc_a_cidr**: CIDR block for first VPC in secondary region
- **secondary_vpc_b_cidr**: CIDR block for second VPC in secondary region
- **enable_dns_support**: Enable DNS support for Transit Gateway
- **enable_multicast_support**: Enable multicast support for Transit Gateway

### Advanced Configuration

For production deployments, consider these customizations:

1. **Security Groups**: Modify security group rules for specific application requirements
2. **Route Tables**: Create additional route tables for network segmentation
3. **Monitoring**: Add custom CloudWatch alarms and notifications
4. **Tagging**: Implement comprehensive resource tagging strategy
5. **Cost Optimization**: Configure data transfer optimization settings

## Cost Considerations

This infrastructure incurs the following costs:

- **Transit Gateway**: $36/month per gateway (2 gateways)
- **VPC Attachments**: $36/month per attachment (4 attachments)
- **Peering Attachments**: $36/month per attachment (1 attachment)
- **Data Processing**: $0.02 per GB processed
- **Cross-Region Data Transfer**: $0.02 per GB transferred

**Estimated Monthly Cost**: $150-200 (excluding data transfer charges)

## Security Best Practices

The implementations include these security features:

- **Least Privilege IAM**: Service-linked roles with minimal permissions
- **Network ACLs**: Default deny rules with explicit allow statements
- **Security Groups**: Stateful firewall rules for granular access control
- **Encryption**: All data in transit is encrypted between regions
- **Route Table Isolation**: Custom route tables prevent unwanted connectivity

## Troubleshooting

### Common Issues

1. **Peering Attachment Fails**: Verify both regions have sufficient capacity
2. **Route Propagation Issues**: Check route table associations and propagation settings
3. **Cross-Region Connectivity**: Verify security group rules allow required traffic
4. **CloudWatch Metrics Missing**: Ensure Transit Gateway has active traffic flow

### Debugging Commands

```bash
# Check Transit Gateway route table details
aws ec2 describe-transit-gateway-route-tables \
    --transit-gateway-route-table-ids <ROUTE_TABLE_ID>

# View attachment details
aws ec2 describe-transit-gateway-attachments \
    --filters "Name=transit-gateway-id,Values=<TGW_ID>"

# Check VPC route tables
aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=<VPC_ID>"
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS Transit Gateway documentation
3. Verify your AWS CLI configuration and permissions
4. Review CloudWatch logs for error messages
5. Use AWS Support for service-specific issues

## Additional Resources

- [AWS Transit Gateway Documentation](https://docs.aws.amazon.com/vpc/latest/tgw/)
- [AWS VPC Peering vs Transit Gateway](https://docs.aws.amazon.com/vpc/latest/peering/what-is-vpc-peering.html)
- [Transit Gateway Best Practices](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-best-design-practices.html)
- [Cross-Region Connectivity Options](https://docs.aws.amazon.com/whitepapers/latest/aws-vpc-connectivity-options/welcome.html)