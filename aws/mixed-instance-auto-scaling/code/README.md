# Infrastructure as Code for Mixed Instance Auto Scaling Groups

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Mixed Instance Auto Scaling Groups".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with permissions for EC2, Auto Scaling, CloudWatch, ELB, IAM, and SNS
- VPC with multiple subnets across different Availability Zones
- Basic understanding of EC2 instance types and Spot Instance concepts
- Estimated cost: $20-50/month for test workloads (significant savings vs On-Demand only)

> **Note**: Spot Instance pricing can vary significantly. Monitor your Spot Instance usage and set appropriate maximum prices to control costs while maintaining availability.

## Architecture Overview

This solution deploys:
- Auto Scaling Group with mixed instance policy (m5, c5, r5 families)
- Launch Template with security and monitoring configurations
- Application Load Balancer with health checking
- Security Groups with web traffic rules
- IAM roles for CloudWatch and Systems Manager integration
- SNS notifications for scaling events
- CloudWatch scaling policies for CPU and network metrics

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name mixed-instances-asg-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=VpcId,ParameterValue=vpc-xxxxxxxxx \
                 ParameterKey=SubnetIds,ParameterValue="subnet-xxxxx,subnet-yyyyy,subnet-zzzzz"
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npm run build

# Deploy with default VPC
cdk deploy

# Deploy with custom VPC
cdk deploy --parameters vpcId=vpc-xxxxxxxxx \
           --parameters subnetIds=subnet-xxxxx,subnet-yyyyy,subnet-zzzzz
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt

# Deploy with default VPC
cdk deploy

# Deploy with custom VPC
cdk deploy --parameters vpcId=vpc-xxxxxxxxx \
           --parameters subnetIds=subnet-xxxxx,subnet-yyyyy,subnet-zzzzz
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan

# Deploy with default VPC
terraform apply

# Deploy with custom VPC (modify terraform.tfvars)
terraform apply -var="vpc_id=vpc-xxxxxxxxx" \
                -var="subnet_ids=[\"subnet-xxxxx\",\"subnet-yyyyy\",\"subnet-zzzzz\"]"
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# Follow prompts for VPC and subnet configuration
```

## Configuration Options

### Instance Type Configuration

The mixed instance policy supports multiple instance families:
- **m5 family**: General purpose (large, xlarge)
- **c5 family**: Compute optimized (large, xlarge)
- **r5 family**: Memory optimized (large, xlarge)

### Capacity Distribution

- **On-Demand Base Capacity**: 1 instance minimum
- **On-Demand Percentage**: 20% above base capacity
- **Spot Allocation Strategy**: Diversified across 4 instance pools
- **Capacity Rebalancing**: Enabled for Spot Instance management

### Scaling Configuration

- **Min Size**: 2 instances
- **Max Size**: 10 instances
- **Desired Capacity**: 4 instances
- **Target CPU Utilization**: 70%
- **Target Network Utilization**: 1MB/s

## Cost Optimization

This solution provides significant cost savings through:
- Up to 90% savings with Spot Instances
- Intelligent allocation across multiple instance types
- Automatic capacity rebalancing to minimize interruptions
- Target tracking scaling to optimize resource usage

## Monitoring and Notifications

The deployment includes:
- CloudWatch custom metrics for detailed monitoring
- SNS notifications for scaling events
- Application Load Balancer health checks
- Instance lifecycle event tracking

## Validation

After deployment, verify the solution by:

1. **Check Auto Scaling Group status**:
   ```bash
   aws autoscaling describe-auto-scaling-groups \
       --auto-scaling-group-names [ASG-NAME] \
       --query 'AutoScalingGroups[0].[AutoScalingGroupName,DesiredCapacity,MinSize,MaxSize]'
   ```

2. **Verify mixed instance types**:
   ```bash
   aws autoscaling describe-auto-scaling-instances \
       --query "AutoScalingInstances[?AutoScalingGroupName=='[ASG-NAME]'].[InstanceId,InstanceType,AvailabilityZone,LifecycleState]" \
       --output table
   ```

3. **Test web application**:
   ```bash
   # Get load balancer DNS name from outputs
   curl -s http://[ALB-DNS-NAME] | grep -E "(Instance ID|Instance Type|Purchase Type)"
   ```

4. **Monitor cost savings**:
   ```bash
   # View Spot vs On-Demand distribution
   # Check CloudWatch metrics for cost analysis
   ```

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name mixed-instances-asg-stack
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
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Customization

### Common Customizations

1. **Instance Types**: Modify the instance type overrides to include additional families (e.g., t3, m6i)
2. **Capacity Targets**: Adjust min/max size and desired capacity based on workload requirements
3. **Spot Percentage**: Change the On-Demand percentage to balance cost vs. availability
4. **Scaling Policies**: Modify target utilization values or add custom metrics
5. **Health Checks**: Customize health check intervals and thresholds

### Variable Definitions

#### CloudFormation Parameters
- `VpcId`: Target VPC for deployment
- `SubnetIds`: Comma-separated list of subnets across AZs
- `InstanceTypes`: List of instance types for mixed policy
- `OnDemandPercentage`: Percentage of On-Demand instances above base

#### CDK Context Variables
- `vpcId`: Target VPC ID (optional, uses default VPC if not specified)
- `subnetIds`: List of subnet IDs for deployment
- `environment`: Environment tag for resources

#### Terraform Variables
- `vpc_id`: VPC ID for deployment
- `subnet_ids`: List of subnet IDs across availability zones
- `instance_types`: Map of instance types and their weights
- `min_size`: Minimum Auto Scaling group size
- `max_size`: Maximum Auto Scaling group size
- `desired_capacity`: Initial desired capacity

### Advanced Configuration

1. **Custom AMI**: Replace the Amazon Linux 2 AMI with a custom image
2. **User Data**: Modify the instance initialization script
3. **Load Balancer**: Add HTTPS listener with SSL certificate
4. **Monitoring**: Integrate with external monitoring solutions
5. **Networking**: Deploy in private subnets with NAT Gateway

## Security Considerations

- Security groups follow least privilege principle
- IAM roles use AWS managed policies
- EC2 instances use IMDSv2 for metadata access
- Load balancer security groups restrict access appropriately
- All resources are tagged for governance and billing

## Troubleshooting

### Common Issues

1. **Insufficient Spot Capacity**: Increase instance type diversity or adjust Spot allocation strategy
2. **Health Check Failures**: Verify security group rules and application startup time
3. **Scaling Issues**: Check CloudWatch metrics and scaling policy configuration
4. **Access Issues**: Verify VPC and subnet configuration for internet access

### Debugging Commands

```bash
# Check Auto Scaling activities
aws autoscaling describe-scaling-activities --auto-scaling-group-name [ASG-NAME]

# View Spot Instance interruption notices
aws ec2 describe-spot-fleet-instances --spot-fleet-request-id [FLEET-ID]

# Monitor CloudWatch metrics
aws cloudwatch get-metric-statistics --namespace AWS/AutoScaling \
    --metric-name GroupDesiredCapacity --dimensions Name=AutoScalingGroupName,Value=[ASG-NAME]
```

## Performance Considerations

- Use Application Load Balancer for better health checking and routing
- Enable detailed monitoring for faster scaling decisions
- Configure appropriate cooldown periods to prevent thrashing
- Monitor instance launch times across different instance types

## Best Practices

1. **Diversification**: Use multiple instance families and sizes
2. **Availability Zones**: Deploy across multiple AZs for resilience
3. **Health Checks**: Use ELB health checks for application-aware scaling
4. **Monitoring**: Set up comprehensive CloudWatch alarms
5. **Cost Management**: Regularly review Spot pricing and utilization

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../auto-scaling-groups-mixed-instance-types-spot-instances.md)
- [AWS Auto Scaling User Guide](https://docs.aws.amazon.com/autoscaling/ec2/userguide/)
- [AWS Spot Instance Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html)
- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Please review and modify according to your organization's security and compliance requirements.