# Infrastructure as Code for Managing Enterprise VPC Architectures with Transit Gateway

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Managing Enterprise VPC Architectures with Transit Gateway".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a hub-and-spoke network architecture using AWS Transit Gateway to connect multiple VPCs across different environments (production, development, test, and shared services). The architecture provides:

- Centralized network connectivity through Transit Gateway
- Network segmentation using custom route tables
- Controlled access patterns between environments
- Cross-region connectivity capabilities
- Comprehensive monitoring and logging

## Prerequisites

### AWS Account Requirements

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions:
  - EC2 full access (for VPC, Transit Gateway, and networking resources)
  - CloudWatch Logs access (for flow logs and monitoring)
  - Route 53 Resolver access (for DNS resolution)
  - IAM permissions for creating service roles

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- IAM permissions to create roles and policies

#### CDK (TypeScript/Python)
- Node.js 18+ (for TypeScript implementation)
- Python 3.8+ (for Python implementation)
- AWS CDK CLI installed (`npm install -g aws-cdk`)

#### Terraform
- Terraform 1.0+ installed
- AWS provider configuration

### Cost Considerations

- **Estimated monthly cost**: $150-200
- Transit Gateway charges: $0.05/hour per attachment
- Data processing: $0.02/GB processed
- Cross-region data transfer charges apply for multi-region deployments

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name multi-vpc-tgw-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=EnvironmentName,ParameterValue=production \
                 ParameterKey=EnableCrossRegion,ParameterValue=false \
    --capabilities CAPABILITY_IAM \
    --tags Key=Purpose,Value=NetworkingRecipe

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name multi-vpc-tgw-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name multi-vpc-tgw-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Review resources to be created
cdk diff

# Deploy the stack
cdk deploy --parameters enableCrossRegion=false

# Get deployment outputs
cdk outputs
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Review resources to be created
cdk diff

# Deploy the stack
cdk deploy --parameters enable_cross_region=false

# Get deployment outputs
cdk outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
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

# Check deployment status
./scripts/validate.sh
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Valid Values |
|-----------|-------------|---------|--------------|
| `EnvironmentName` | Name prefix for resources | `production` | String |
| `EnableCrossRegion` | Enable cross-region peering | `false` | `true`/`false` |
| `ProductionCidr` | CIDR block for production VPC | `10.0.0.0/16` | Valid CIDR |
| `DevelopmentCidr` | CIDR block for development VPC | `10.1.0.0/16` | Valid CIDR |
| `TestCidr` | CIDR block for test VPC | `10.2.0.0/16` | Valid CIDR |
| `SharedServicesCidr` | CIDR block for shared services VPC | `10.3.0.0/16` | Valid CIDR |
| `DisasterRecoveryRegion` | AWS region for DR resources | `us-west-2` | AWS region |

### CDK Configuration

Modify the following variables in the CDK code:

```typescript
// CDK TypeScript
const config = {
  environmentName: 'production',
  enableCrossRegion: false,
  vpcs: {
    production: { cidr: '10.0.0.0/16' },
    development: { cidr: '10.1.0.0/16' },
    test: { cidr: '10.2.0.0/16' },
    sharedServices: { cidr: '10.3.0.0/16' }
  }
};
```

```python
# CDK Python
config = {
    'environment_name': 'production',
    'enable_cross_region': False,
    'vpcs': {
        'production': {'cidr': '10.0.0.0/16'},
        'development': {'cidr': '10.1.0.0/16'},
        'test': {'cidr': '10.2.0.0/16'},
        'shared_services': {'cidr': '10.3.0.0/16'}
    }
}
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
environment_name = "production"
enable_cross_region = false

vpc_configs = {
  production = {
    cidr = "10.0.0.0/16"
    environment = "prod"
  }
  development = {
    cidr = "10.1.0.0/16"
    environment = "dev"
  }
  test = {
    cidr = "10.2.0.0/16"
    environment = "test"
  }
  shared_services = {
    cidr = "10.3.0.0/16"
    environment = "shared"
  }
}

dr_region = "us-west-2"
```

## Validation & Testing

### Verify Transit Gateway Configuration

```bash
# Check Transit Gateway status
aws ec2 describe-transit-gateways \
    --query 'TransitGateways[*].[TransitGatewayId,State,Description]' \
    --output table

# Verify VPC attachments
aws ec2 describe-transit-gateway-vpc-attachments \
    --query 'TransitGatewayVpcAttachments[*].[TransitGatewayAttachmentId,State,VpcId]' \
    --output table
```

### Test Network Connectivity

```bash
# Check route table associations
aws ec2 get-transit-gateway-route-table-associations \
    --transit-gateway-route-table-id <ROUTE_TABLE_ID> \
    --query 'Associations[*].[TransitGatewayAttachmentId,State]' \
    --output table

# Verify route propagation
aws ec2 search-transit-gateway-routes \
    --transit-gateway-route-table-id <ROUTE_TABLE_ID> \
    --filters "Name=state,Values=active" \
    --query 'Routes[*].[DestinationCidrBlock,State,Type]' \
    --output table
```

### Monitor VPC Flow Logs

```bash
# Check flow logs status
aws ec2 describe-flow-logs \
    --query 'FlowLogs[*].[FlowLogId,ResourceId,FlowLogStatus]' \
    --output table

# View CloudWatch log groups
aws logs describe-log-groups \
    --log-group-name-prefix /aws/vpc/flowlogs
```

## Security Considerations

### Network Segmentation

- Production environment isolated from development/test
- Shared services accessible to all environments with controlled access
- Blackhole routes prevent unauthorized cross-environment communication
- Security groups provide application-level traffic control

### Monitoring & Compliance

- VPC Flow Logs enabled for all VPCs
- CloudWatch alarms for Transit Gateway utilization
- Route table changes logged and monitored
- Network ACLs provide additional subnet-level protection

### Best Practices Implemented

- Least privilege routing policies
- Encrypted traffic between regions
- DNS resolution centralized in shared services
- Automated monitoring and alerting

## Troubleshooting

### Common Issues

1. **Transit Gateway attachment stuck in "pending"**
   ```bash
   # Check for subnet availability and route table conflicts
   aws ec2 describe-subnets --subnet-ids <SUBNET_ID>
   ```

2. **Cross-region peering not established**
   ```bash
   # Verify peering attachment acceptance
   aws ec2 describe-transit-gateway-peering-attachments \
       --transit-gateway-attachment-ids <PEERING_ID>
   ```

3. **Route propagation not working**
   ```bash
   # Check route table propagation status
   aws ec2 get-transit-gateway-route-table-propagations \
       --transit-gateway-route-table-id <ROUTE_TABLE_ID>
   ```

### Log Analysis

```bash
# Query VPC Flow Logs in CloudWatch
aws logs filter-log-events \
    --log-group-name /aws/vpc/flowlogs \
    --start-time $(date -d '1 hour ago' +%s)000 \
    --filter-pattern "[srcaddr, dstaddr, srcport, dstport, protocol, packets, bytes, windowstart, windowend, action, flowlogstatus]"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name multi-vpc-tgw-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name multi-vpc-tgw-stack
```

### Using CDK

```bash
# Destroy the CDK stack
cd cdk-typescript/  # or cdk-python/
cdk destroy --force

# Clean up CDK bootstrap (optional)
# cdk bootstrap --toolkit-stack-name CDKToolkit
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -auto-approve

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify resource deletion
./scripts/validate-cleanup.sh
```

### Manual Cleanup Verification

```bash
# Verify Transit Gateway deletion
aws ec2 describe-transit-gateways \
    --query 'TransitGateways[?State!=`deleted`]'

# Check for remaining VPCs
aws ec2 describe-vpcs \
    --query 'Vpcs[?State!=`available`]'

# Verify CloudWatch resources cleanup
aws logs describe-log-groups \
    --log-group-name-prefix /aws/transitgateway/
```

## Advanced Configuration

### Cross-Region Deployment

To enable cross-region connectivity, set the `EnableCrossRegion` parameter to `true` and specify the disaster recovery region. This will:

- Create a second Transit Gateway in the DR region
- Establish peering between regions
- Configure appropriate routing for disaster recovery scenarios

### Monitoring Extensions

The implementation includes comprehensive monitoring setup:

- VPC Flow Logs for all networks
- CloudWatch alarms for Transit Gateway metrics
- Custom metrics for route table changes
- SNS notifications for critical network events

### Integration with AWS Services

The architecture integrates with:

- **Route 53 Resolver**: Centralized DNS resolution from shared services
- **AWS Config**: Monitoring configuration compliance
- **CloudTrail**: API call logging for security auditing
- **Systems Manager**: Centralized parameter storage

## Customization

### Adding New VPCs

To add additional VPCs to the architecture:

1. Update the IaC configuration with new VPC definitions
2. Create appropriate route table associations
3. Configure security group rules for the new environment
4. Update monitoring and logging configurations

### Network Segmentation Policies

Modify route table configurations to implement custom segmentation:

- Create environment-specific route tables
- Configure blackhole routes for restricted access
- Implement conditional routing based on source networks
- Add static routes for specific traffic patterns

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS Transit Gateway documentation
3. Consult provider-specific troubleshooting guides
4. Verify IAM permissions and service limits

### Useful Resources

- [AWS Transit Gateway Documentation](https://docs.aws.amazon.com/vpc/latest/tgw/)
- [VPC Flow Logs Guide](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)

## License

This infrastructure code is provided as-is for educational and implementation purposes. Refer to your organization's policies for production usage guidelines.