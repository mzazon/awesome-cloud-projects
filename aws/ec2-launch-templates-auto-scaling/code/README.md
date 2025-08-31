# Infrastructure as Code for EC2 Launch Templates with Auto Scaling

This directory contains Infrastructure as Code (IaC) implementations for the recipe "EC2 Launch Templates with Auto Scaling".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with IAM permissions for EC2, Auto Scaling, and CloudWatch services
- Access to the default VPC and at least two availability zones
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Basic understanding of EC2 instances and Auto Scaling concepts

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name ec2-autoscaling-demo \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=InstanceType,ParameterValue=t2.micro \
                 ParameterKey=KeyPairName,ParameterValue=your-key-pair

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name ec2-autoscaling-demo

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name ec2-autoscaling-demo \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters instanceType=t2.micro

# View deployed resources
cdk ls
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters instance-type=t2.micro

# View deployed resources
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan -var="instance_type=t2.micro"

# Apply configuration
terraform apply -var="instance_type=t2.micro"

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
./scripts/deploy.sh --status

# Verify resources are healthy
./scripts/deploy.sh --validate
```

## Architecture Overview

This infrastructure creates:

- **Launch Template**: Defines EC2 instance configuration with versioning support
- **Auto Scaling Group**: Manages instance capacity across multiple AZs (min: 1, max: 4, desired: 2)
- **Security Group**: Controls network access (HTTP port 80 and SSH port 22)
- **Target Tracking Policy**: Automatically scales based on CPU utilization (70% target)
- **CloudWatch Metrics**: Monitors Auto Scaling group performance

## Configuration Options

### CloudFormation Parameters

- `InstanceType`: EC2 instance type (default: t2.micro)
- `KeyPairName`: EC2 Key Pair for SSH access
- `VpcId`: VPC ID (defaults to default VPC)
- `SubnetIds`: Comma-separated list of subnet IDs
- `MinSize`: Minimum number of instances (default: 1)
- `MaxSize`: Maximum number of instances (default: 4)
- `DesiredCapacity`: Initial desired capacity (default: 2)

### CDK Configuration

Modify the following in the CDK app files:

```typescript
// TypeScript example
const autoScalingGroup = new autoscaling.AutoScalingGroup(this, 'ASG', {
  launchTemplate: launchTemplate,
  minCapacity: 1,
  maxCapacity: 4,
  desiredCapacity: 2,
  // ... other configurations
});
```

```python
# Python example
auto_scaling_group = autoscaling.AutoScalingGroup(
    self, "ASG",
    launch_template=launch_template,
    min_capacity=1,
    max_capacity=4,
    desired_capacity=2,
    # ... other configurations
)
```

### Terraform Variables

Customize deployment by modifying `terraform.tfvars`:

```hcl
instance_type = "t2.micro"
min_size = 1
max_size = 4
desired_capacity = 2
cpu_target_value = 70.0
```

### Bash Script Environment Variables

Set environment variables before running scripts:

```bash
export INSTANCE_TYPE="t2.micro"
export MIN_SIZE=1
export MAX_SIZE=4
export DESIRED_CAPACITY=2
export CPU_TARGET=70
```

## Validation & Testing

### Verify Deployment

After deployment, validate the infrastructure:

```bash
# Check Auto Scaling Group status
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names [ASG-NAME] \
    --query 'AutoScalingGroups[0].{Name:AutoScalingGroupName,Instances:length(Instances),Health:HealthCheckType}'

# Test web application
INSTANCE_IPS=$(aws ec2 describe-instances \
    --filters "Name=tag:aws:autoscaling:groupName,Values=[ASG-NAME]" \
    --query 'Reservations[].Instances[].PublicIpAddress' \
    --output text)

for ip in $INSTANCE_IPS; do
    curl -s http://$ip
done
```

### Load Testing (Optional)

Generate load to test auto scaling:

```bash
# Install stress testing tool
sudo amazon-linux-extras install epel -y
sudo yum install stress -y

# Generate CPU load on instances
for ip in $INSTANCE_IPS; do
    ssh -i your-key.pem ec2-user@$ip "stress --cpu 2 --timeout 600s" &
done
```

## Monitoring

### CloudWatch Metrics

Monitor key metrics in the AWS Console or via CLI:

```bash
# View Auto Scaling group metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/AutoScaling \
    --metric-name GroupDesiredCapacity \
    --dimensions Name=AutoScalingGroupName,Value=[ASG-NAME] \
    --start-time $(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S') \
    --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
    --period 300 \
    --statistics Average
```

### Scaling Activities

```bash
# View recent scaling activities
aws autoscaling describe-scaling-activities \
    --auto-scaling-group-name [ASG-NAME] \
    --max-items 10
```

## Cleanup

> **Warning**: Cleanup will permanently delete all resources. Ensure you no longer need the infrastructure before proceeding.

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name ec2-autoscaling-demo

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name ec2-autoscaling-demo
```

### Using CDK (AWS)

```bash
# Navigate to appropriate CDK directory
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

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**: Ensure your AWS credentials have the required permissions for EC2, Auto Scaling, and CloudWatch
2. **No Default VPC**: If no default VPC exists, specify VPC and subnet IDs manually
3. **Key Pair Not Found**: Create an EC2 key pair or specify an existing one
4. **Instance Launch Failures**: Check security group rules and AMI availability in your region

### Debug Commands

```bash
# Check Auto Scaling group events
aws autoscaling describe-scaling-activities \
    --auto-scaling-group-name [ASG-NAME]

# View launch template details
aws ec2 describe-launch-template-versions \
    --launch-template-id [LT-ID]

# Check instance system logs
aws ec2 get-console-output --instance-id [INSTANCE-ID]
```

## Cost Optimization

- Use t3.micro or t4g.micro instances for better price-performance
- Implement scheduled scaling for predictable traffic patterns
- Consider Spot instances for development environments
- Monitor CloudWatch costs if enabling detailed monitoring

## Security Considerations

- Launch template includes security group with restricted access
- Consider using Systems Manager Session Manager instead of SSH
- Enable CloudTrail for audit logging
- Use IAM roles for applications instead of storing credentials
- Regularly update AMIs for security patches

## Customization

### Adding Application Load Balancer

To integrate with an Application Load Balancer:

1. Create ALB and target group
2. Attach target group to Auto Scaling group
3. Configure health checks
4. Update security group rules

### Custom AMI

To use a custom AMI:

1. Replace the AMI ID in launch template configuration
2. Ensure User Data scripts are compatible
3. Test thoroughly before production deployment

### Multi-Region Deployment

For multi-region setups:

1. Deploy in each target region
2. Use Route 53 for DNS routing
3. Consider data replication requirements
4. Implement cross-region monitoring

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS documentation for service-specific guidance
3. Validate IAM permissions and resource limits
4. Monitor CloudFormation/CDK events for deployment issues

## Additional Resources

- [AWS Auto Scaling Documentation](https://docs.aws.amazon.com/autoscaling/)
- [EC2 Launch Templates Guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-launch-templates.html)
- [CloudWatch Metrics for Auto Scaling](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-metrics.html)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)