# Infrastructure as Code for Cross-Account Service Discovery with VPC Lattice and ECS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cross-Account Service Discovery with VPC Lattice and ECS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- AWS CLI v2 installed and configured
- Two AWS accounts with administrative access for cross-account configuration
- Understanding of containerized applications and microservices architecture
- Basic knowledge of AWS networking concepts (VPC, subnets, security groups)
- Estimated cost: $20-30 for 45 minutes of testing (ECS tasks, VPC Lattice data processing)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2 with CloudFormation permissions
- IAM permissions for VPC Lattice, ECS, EventBridge, CloudWatch, and RAM operations

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK CLI (`npm install -g aws-cdk`)
- TypeScript compiler (`npm install -g typescript`)

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI (`pip install aws-cdk-lib`)
- Virtual environment recommended

#### Terraform
- Terraform v1.5 or later
- AWS provider v5.0 or later

#### Bash Scripts
- Bash shell environment
- jq for JSON parsing
- AWS CLI v2 with appropriate permissions

## Architecture Overview

This infrastructure creates a cross-account service discovery solution using:
- Amazon VPC Lattice for managed application networking
- Amazon ECS with Fargate for containerized services
- AWS Resource Access Manager (RAM) for cross-account sharing
- EventBridge for service discovery event monitoring
- CloudWatch for comprehensive observability

## Quick Start

### Using CloudFormation

```bash
# Deploy in Account A (Producer)
aws cloudformation create-stack \
    --stack-name cross-account-lattice-producer \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=AccountBId,ParameterValue=123456789012 \
    --capabilities CAPABILITY_IAM

# Monitor deployment
aws cloudformation wait stack-create-complete \
    --stack-name cross-account-lattice-producer
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy CrossAccountLatticeStack \
    --parameters accountBId=123456789012

# View outputs
cdk ls
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Deploy the stack
cdk deploy CrossAccountLatticeStack \
    --parameters account-b-id=123456789012

# View stack information
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="account_b_id=123456789012" \
    -var="aws_region=us-east-1"

# Apply configuration
terraform apply \
    -var="account_b_id=123456789012" \
    -var="aws_region=us-east-1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export ACCOUNT_B_ID="123456789012"
export AWS_REGION="us-east-1"

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment progress
# The script will provide status updates and validation steps
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `AccountBId` | AWS Account ID to share VPC Lattice service network | - | Yes |
| `VpcId` | VPC ID for ECS deployment | Default VPC | No |
| `ClusterName` | Name for ECS cluster | `cross-account-cluster` | No |
| `ServiceNetworkName` | Name for VPC Lattice service network | `cross-account-network` | No |

### CDK Configuration

Modify the following variables in the CDK app files:

```typescript
// TypeScript
const props = {
    accountBId: '123456789012',
    vpcId: 'vpc-12345678',  // Optional: specify VPC
    clusterName: 'my-cluster',
    serviceNetworkName: 'my-service-network'
};
```

```python
# Python
props = {
    'account_b_id': '123456789012',
    'vpc_id': 'vpc-12345678',  # Optional: specify VPC
    'cluster_name': 'my-cluster',
    'service_network_name': 'my-service-network'
}
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
# Required variables
account_b_id = "123456789012"
aws_region   = "us-east-1"

# Optional variables
vpc_id                = "vpc-12345678"
cluster_name         = "cross-account-cluster"
service_network_name = "cross-account-network"
container_image      = "nginx:latest"
task_cpu            = "256"
task_memory         = "512"
```

## Validation & Testing

After deployment, validate the infrastructure:

### Check VPC Lattice Service Network

```bash
# List service networks
aws vpc-lattice list-service-networks

# Get service network details
aws vpc-lattice get-service-network \
    --service-network-identifier <service-network-id>
```

### Verify ECS Service

```bash
# Check ECS cluster status
aws ecs describe-clusters --clusters <cluster-name>

# Check service status
aws ecs describe-services \
    --cluster <cluster-name> \
    --services <service-name>
```

### Test Cross-Account Sharing

```bash
# Check AWS RAM resource shares
aws ram get-resource-shares --resource-owner SELF

# Verify EventBridge rules
aws events list-rules --name-prefix "vpc-lattice"
```

### View CloudWatch Dashboard

```bash
# Open CloudWatch dashboard
aws cloudwatch get-dashboard \
    --dashboard-name "cross-account-service-discovery"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name cross-account-lattice-producer

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name cross-account-lattice-producer
```

### Using CDK

```bash
# Destroy the stack
cdk destroy CrossAccountLatticeStack

# Confirm deletion when prompted
# Type 'y' to confirm
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="account_b_id=123456789012" \
    -var="aws_region=us-east-1"

# Confirm destruction when prompted
# Type 'yes' to confirm
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
# The script will clean up resources in proper order
```

## Troubleshooting

### Common Issues

1. **Cross-Account Permissions**: Ensure both AWS accounts have proper IAM permissions for VPC Lattice and RAM operations.

2. **VPC Lattice Service Registration**: If ECS tasks don't register with target groups, verify security group configurations and subnet routing.

3. **EventBridge Events**: If events aren't appearing in CloudWatch, check EventBridge rule patterns and IAM permissions.

4. **Resource Sharing**: Verify AWS RAM resource sharing is accepted in Account B.

### Debug Commands

```bash
# Check VPC Lattice target health
aws vpc-lattice list-targets \
    --target-group-identifier <target-group-arn>

# View ECS task logs
aws logs get-log-events \
    --log-group-name "/ecs/producer" \
    --log-stream-name <log-stream-name>

# Check EventBridge rule targets
aws events list-targets-by-rule \
    --rule "vpc-lattice-events"
```

## Security Considerations

### IAM Permissions

The infrastructure creates IAM roles with least-privilege access:
- ECS task execution role for container management
- EventBridge role for CloudWatch Logs access
- VPC Lattice service roles for cross-account communication

### Network Security

- VPC Lattice provides IAM-based authentication
- ECS tasks run in private subnets with NAT Gateway access
- Security groups restrict traffic to necessary ports only

### Cross-Account Security

- AWS RAM enables secure resource sharing
- IAM policies control cross-account access
- VPC Lattice auth policies can be implemented for fine-grained control

## Cost Optimization

### Resource Costs

- **VPC Lattice**: Pay-per-use pricing for data processed
- **ECS Fargate**: Pay-per-second for task execution
- **EventBridge**: Minimal cost for custom events
- **CloudWatch**: Standard pricing for logs and dashboards

### Cost-Saving Tips

1. Use Fargate Spot pricing for non-critical workloads
2. Implement log retention policies to manage CloudWatch costs
3. Monitor VPC Lattice data processing charges
4. Use ECS Service Auto Scaling to optimize task counts

## Advanced Configuration

### Multi-Region Deployment

To deploy across multiple regions, modify the region parameter and ensure cross-region networking is configured properly.

### Custom Container Images

Replace the default nginx image with your application container:

```bash
# Update container image in parameters
--parameters ParameterKey=ContainerImage,ParameterValue=your-account.dkr.ecr.region.amazonaws.com/your-app:latest
```

### VPC Lattice Auth Policies

Implement fine-grained access control:

```bash
# Create auth policy for service
aws vpc-lattice create-auth-policy \
    --resource-identifier <service-arn> \
    --policy file://auth-policy.json
```

## Support and Documentation

- [AWS VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- [Amazon ECS Developer Guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/)
- [AWS Resource Access Manager User Guide](https://docs.aws.amazon.com/ram/latest/userguide/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)

For issues with this infrastructure code, refer to the original recipe documentation or contact your AWS support team.

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment
2. Validate against AWS best practices
3. Update documentation as needed
4. Consider backward compatibility
5. Follow security best practices

## License

This infrastructure code is provided as-is for educational and development purposes. Ensure compliance with your organization's policies before use in production environments.