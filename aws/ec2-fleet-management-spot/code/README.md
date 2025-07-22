# Infrastructure as Code for EC2 Fleet Management with Spot Instances

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing EC2 Fleet Management with Spot Instances".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - EC2 Fleet management
  - Spot Fleet requests
  - IAM role creation
  - VPC and security group management
  - CloudWatch dashboard creation
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $10-30/hour for fleet resources (varies by instance mix and region)

> **Note**: Ensure your AWS account has sufficient EC2 limits for the target fleet capacity.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name ec2-fleet-management \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=FleetTargetCapacity,ParameterValue=6 \
                 ParameterKey=SpotTargetCapacity,ParameterValue=4 \
                 ParameterKey=OnDemandTargetCapacity,ParameterValue=2

# Wait for stack creation
aws cloudformation wait stack-create-complete \
    --stack-name ec2-fleet-management

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name ec2-fleet-management \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using CDK Python

```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

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

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment progress
./scripts/monitor.sh
```

## Architecture Overview

The infrastructure creates:

- **EC2 Fleet**: Mixed instance fleet with Spot and On-Demand instances
- **Spot Fleet**: Comparison fleet using Spot instances only
- **Launch Template**: Standardized instance configuration
- **Security Group**: Network security rules for fleet instances
- **IAM Role**: Service role for Spot Fleet operations
- **CloudWatch Dashboard**: Monitoring and metrics visualization

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Type |
|-----------|-------------|---------|------|
| FleetTargetCapacity | Total target capacity for EC2 Fleet | 6 | Number |
| SpotTargetCapacity | Target capacity for Spot instances | 4 | Number |
| OnDemandTargetCapacity | Target capacity for On-Demand instances | 2 | Number |
| InstanceTypes | Comma-separated list of instance types | t3.micro,t3.small,t3.nano | String |
| KeyPairName | EC2 Key Pair for SSH access | - | String |
| VpcId | VPC ID for fleet deployment | Default VPC | String |

### CDK Configuration

Modify the configuration in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// TypeScript example
const fleetConfig = {
  targetCapacity: 6,
  spotCapacity: 4,
  onDemandCapacity: 2,
  instanceTypes: ['t3.micro', 't3.small', 't3.nano']
};
```

### Terraform Variables

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| aws_region | AWS region for deployment | us-east-1 | string |
| fleet_name | Name prefix for fleet resources | ec2-fleet-demo | string |
| target_capacity | Total target capacity | 6 | number |
| spot_capacity | Spot instance capacity | 4 | number |
| ondemand_capacity | On-Demand instance capacity | 2 | number |
| instance_types | List of instance types | ["t3.micro", "t3.small", "t3.nano"] | list(string) |

Create a `terraform.tfvars` file:

```hcl
aws_region = "us-west-2"
fleet_name = "my-fleet"
target_capacity = 8
spot_capacity = 6
ondemand_capacity = 2
```

## Monitoring and Validation

### Fleet Status Monitoring

```bash
# Check EC2 Fleet status
aws ec2 describe-fleets \
    --fleet-ids $(terraform output -raw ec2_fleet_id)

# Monitor fleet instances
aws ec2 describe-fleet-instances \
    --fleet-id $(terraform output -raw ec2_fleet_id) \
    --query 'ActiveInstances[*].[InstanceId,InstanceType,AvailabilityZone,Lifecycle]' \
    --output table
```

### CloudWatch Dashboard

Access the CloudWatch dashboard to monitor:
- Fleet CPU utilization
- Spot interruption rates
- Instance distribution across AZs
- Cost optimization metrics

### Testing Web Application

```bash
# Get fleet instance public IPs
FLEET_ID=$(terraform output -raw ec2_fleet_id)
aws ec2 describe-fleet-instances \
    --fleet-id $FLEET_ID \
    --query 'ActiveInstances[*].InstanceId' \
    --output text | xargs aws ec2 describe-instances \
    --instance-ids | jq -r '.Reservations[].Instances[].PublicIpAddress' | \
while read ip; do
    echo "Testing instance at $ip:"
    curl -s "http://$ip" | grep -E "(Instance ID|Instance Type|Availability Zone)"
done
```

## Cost Optimization

### Spot Instance Savings

Monitor Spot instance pricing:

```bash
# Check current Spot prices
aws ec2 describe-spot-price-history \
    --instance-types t3.micro t3.small t3.nano \
    --product-descriptions "Linux/UNIX" \
    --max-items 10 \
    --query 'SpotPriceHistory[*].[InstanceType,SpotPrice,AvailabilityZone]' \
    --output table
```

### Fleet Scaling

Adjust fleet capacity based on demand:

```bash
# Scale up fleet
aws ec2 modify-fleet \
    --fleet-id $(terraform output -raw ec2_fleet_id) \
    --target-capacity-specification '{
        "TotalTargetCapacity": 10,
        "OnDemandTargetCapacity": 4,
        "SpotTargetCapacity": 6
    }'
```

## Troubleshooting

### Common Issues

1. **Fleet Creation Failures**
   - Check IAM permissions for EC2 Fleet operations
   - Verify instance type availability in selected AZs
   - Ensure sufficient EC2 limits for target capacity

2. **Spot Instance Interruptions**
   - Review Spot interruption logs in CloudWatch
   - Consider using capacity-optimized allocation strategy
   - Implement graceful shutdown handling in applications

3. **Instance Launch Failures**
   - Verify launch template configuration
   - Check security group rules
   - Validate AMI availability in target region

### Debug Commands

```bash
# Check fleet events
aws ec2 describe-fleet-history \
    --fleet-id $(terraform output -raw ec2_fleet_id) \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)

# View Spot Fleet events
aws ec2 describe-spot-fleet-request-history \
    --spot-fleet-request-id $(terraform output -raw spot_fleet_id) \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name ec2-fleet-management

# Wait for deletion
aws cloudformation wait stack-delete-complete \
    --stack-name ec2-fleet-management
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Security Considerations

- **IAM Roles**: Minimal permissions for Spot Fleet operations
- **Security Groups**: Restricted inbound access (adjust CIDR blocks as needed)
- **Key Pairs**: Secure storage of private keys
- **Network**: Deploy in private subnets for production workloads
- **Monitoring**: Enable CloudTrail for API call logging

## Performance Optimization

1. **Instance Type Selection**: Choose appropriate instance types for your workload
2. **Allocation Strategy**: Use capacity-optimized for Spot instances
3. **Multi-AZ Distribution**: Spread instances across multiple Availability Zones
4. **Health Checks**: Configure application-level health checks
5. **Auto Scaling**: Integrate with Application Auto Scaling for dynamic capacity

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS EC2 Fleet documentation
3. Validate IAM permissions and service limits
4. Check CloudWatch logs for error details
5. Review AWS Support resources for fleet management

## Additional Resources

- [AWS EC2 Fleet Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-fleet.html)
- [Spot Fleet Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-fleet.html)
- [Spot Instance Best Practices](https://docs.aws.amazon.com/whitepapers/latest/cost-optimization-leveraging-ec2-spot-instances/spot-best-practices.html)
- [AWS Cost Optimization](https://aws.amazon.com/aws-cost-management/aws-cost-optimization/)