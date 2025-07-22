# Infrastructure as Code for Auto Scaling with Load Balancers

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Auto Scaling with Load Balancers".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating EC2, Auto Scaling, ELB, and CloudWatch resources
- Existing VPC with public and private subnets across multiple AZs
- Basic understanding of load balancing and auto scaling concepts

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2 with CloudFormation permissions

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK CLI (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI (`pip install aws-cdk-lib`)

#### Terraform
- Terraform 1.5 or later
- AWS provider configured

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name auto-scaling-alb-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=VpcId,ParameterValue=vpc-xxxxxxxx \
                 ParameterKey=SubnetIds,ParameterValue="subnet-xxxxxxxx,subnet-yyyyyyyy" \
    --capabilities CAPABILITY_IAM

# Monitor deployment
aws cloudformation wait stack-create-complete \
    --stack-name auto-scaling-alb-stack

# Get load balancer DNS name
aws cloudformation describe-stacks \
    --stack-name auto-scaling-alb-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python

```bash
cd cdk-python/
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file (copy from terraform.tfvars.example)
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your VPC and subnet information

# Plan deployment
terraform plan

# Apply configuration
terraform apply

# Get load balancer DNS
terraform output load_balancer_dns
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export VPC_ID="vpc-xxxxxxxx"
export SUBNET_IDS="subnet-xxxxxxxx,subnet-yyyyyyyy,subnet-zzzzzzzz"

# Deploy infrastructure
./scripts/deploy.sh

# Test the deployment
curl http://$(cat /tmp/alb_dns.txt)
```

## Customization

### CloudFormation Parameters

- `VpcId`: The VPC where resources will be created
- `SubnetIds`: Comma-separated list of subnet IDs across multiple AZs
- `InstanceType`: EC2 instance type (default: t3.micro)
- `MinSize`: Minimum number of instances (default: 2)
- `MaxSize`: Maximum number of instances (default: 8)
- `DesiredCapacity`: Initial number of instances (default: 2)

### CDK Configuration

Modify the stack parameters in `app.ts` or `app.py`:

```typescript
// CDK TypeScript
const stack = new AutoScalingStack(app, 'AutoScalingStack', {
  vpcId: 'vpc-xxxxxxxx',
  subnetIds: ['subnet-xxxxxxxx', 'subnet-yyyyyyyy'],
  instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
  minSize: 2,
  maxSize: 8,
  desiredCapacity: 2
});
```

### Terraform Variables

Edit `terraform.tfvars`:

```hcl
vpc_id = "vpc-xxxxxxxx"
subnet_ids = ["subnet-xxxxxxxx", "subnet-yyyyyyyy", "subnet-zzzzzzzz"]
instance_type = "t3.micro"
min_size = 2
max_size = 8
desired_capacity = 2
cpu_target_value = 70.0
alb_request_target_value = 1000.0
```

## Architecture Components

This infrastructure creates the following resources:

- **Security Group**: Controls inbound/outbound traffic for web servers
- **Launch Template**: Defines EC2 instance configuration with user data
- **Application Load Balancer**: Distributes traffic across healthy instances
- **Target Group**: Groups instances for health checking and load balancing
- **Auto Scaling Group**: Manages instance lifecycle and scaling
- **Scaling Policies**: Target tracking policies for CPU and request count
- **Scheduled Actions**: Proactive scaling for predictable traffic patterns
- **CloudWatch Alarms**: Monitoring and alerting for scaling events

## Testing the Deployment

1. **Verify Auto Scaling Group**:
   ```bash
   aws autoscaling describe-auto-scaling-groups \
       --auto-scaling-group-names <ASG_NAME> \
       --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize]' \
       --output table
   ```

2. **Test Load Balancer**:
   ```bash
   # Get ALB DNS name from outputs
   ALB_DNS=$(aws cloudformation describe-stacks \
       --stack-name auto-scaling-alb-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
       --output text)
   
   # Test connectivity
   curl http://$ALB_DNS
   ```

3. **Test Auto Scaling**:
   - Access the web application through the load balancer DNS
   - Use the "Generate CPU Load" button to trigger scaling
   - Monitor scaling activities in the AWS Console or CLI

4. **Monitor Scaling Activities**:
   ```bash
   aws autoscaling describe-scaling-activities \
       --auto-scaling-group-name <ASG_NAME> \
       --max-items 5
   ```

## Cleanup

### Using CloudFormation

```bash
aws cloudformation delete-stack --stack-name auto-scaling-alb-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name auto-scaling-alb-stack
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

1. **VPC/Subnet Not Found**:
   - Verify VPC ID and subnet IDs exist in your account
   - Ensure subnets span multiple Availability Zones

2. **Insufficient Permissions**:
   - Verify your AWS credentials have permissions for EC2, Auto Scaling, ELB, and CloudWatch
   - Check IAM policies for required actions

3. **Instance Launch Failures**:
   - Check Auto Scaling Group activity history
   - Verify security group rules allow necessary traffic
   - Ensure instance type is available in selected AZs

4. **Load Balancer Not Responding**:
   - Verify target group health checks are passing
   - Check security group allows traffic on port 80
   - Wait for DNS propagation (can take several minutes)

### Debug Commands

```bash
# Check Auto Scaling Group instances
aws autoscaling describe-auto-scaling-instances \
    --query 'AutoScalingInstances[*].[InstanceId,LifecycleState,HealthStatus]' \
    --output table

# Check target group health
aws elbv2 describe-target-health \
    --target-group-arn <TARGET_GROUP_ARN>

# View scaling activities
aws autoscaling describe-scaling-activities \
    --auto-scaling-group-name <ASG_NAME> \
    --max-items 10
```

## Cost Optimization

- Use t3.micro instances for testing (eligible for AWS Free Tier)
- Set appropriate scaling policies to avoid over-provisioning
- Consider Spot Instances for non-critical workloads
- Monitor CloudWatch costs with detailed monitoring enabled
- Clean up resources promptly after testing

## Security Considerations

- Security groups are configured with minimal required access
- Instance Metadata Service v2 (IMDSv2) is enforced
- Consider using Systems Manager Session Manager instead of SSH
- Regularly update AMI to latest security patches
- Review and restrict security group rules as needed

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service documentation for specific resources
3. Verify your account limits and quotas
4. Review CloudTrail logs for API errors

## Estimated Costs

Based on us-east-1 pricing (varies by region):
- t3.micro instances: ~$0.0104/hour each
- Application Load Balancer: ~$0.0225/hour + $0.008 per LCU-hour
- Data transfer: $0.09/GB outbound (first 1GB free per month)

**Estimated monthly cost for 2-4 instances**: $20-50 USD

> **Note**: Costs may vary based on actual usage, region, and AWS pricing changes. Use the AWS Pricing Calculator for accurate estimates.