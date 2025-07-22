# Infrastructure as Code for Implementing Predictive Scaling for EC2 with Auto Scaling and Machine Learning

This directory contains Infrastructure as Code (IaC) implementations for the recipe Implementing Predictive Scaling for EC2 with Auto Scaling and Machine Learning.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a complete predictive scaling solution that includes:

- VPC with public subnets across multiple Availability Zones
- Auto Scaling Group with launch template for EC2 instances
- Predictive scaling policy using machine learning forecasting
- Target tracking scaling policy for reactive scaling
- CloudWatch dashboard for monitoring scaling behavior
- IAM roles and security groups with least privilege access

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with permissions to create:
  - EC2 instances, VPCs, subnets, and security groups
  - Auto Scaling groups and scaling policies
  - IAM roles and instance profiles
  - CloudWatch dashboards and metrics
- For CDK implementations: Node.js 16+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $20-50 per month depending on instance types and scale

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name predictive-scaling-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=EnvironmentName,ParameterValue=production
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npx cdk bootstrap  # First time only
npx cdk deploy
```

### Using CDK Python
```bash
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt
cdk bootstrap  # First time only
cdk deploy
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Configuration Options

### Key Parameters

- **Environment Name**: Prefix for resource naming (default: "predictive-scaling")
- **Instance Type**: EC2 instance type for Auto Scaling group (default: "t3.micro")
- **Min/Max/Desired Capacity**: Auto Scaling group size limits (default: 2/10/2)
- **Target CPU Utilization**: Target for scaling policies (default: 50%)
- **Availability Zones**: Number of AZs to use (default: 2)

### Predictive Scaling Configuration

- **Mode**: Initially set to "ForecastOnly" for evaluation, then "ForecastAndScale"
- **Scheduling Buffer Time**: Lead time for instance launches (default: 300 seconds)
- **Max Capacity Breach Behavior**: How to handle capacity limit breaches
- **Max Capacity Buffer**: Additional capacity percentage above max (default: 10%)

## Monitoring and Validation

### CloudWatch Dashboard

The implementation creates a CloudWatch dashboard with:
- Auto Scaling group CPU utilization trends
- Instance count over time
- Scaling activity history

Access the dashboard at:
```
https://console.aws.amazon.com/cloudwatch/home?region=<your-region>#dashboards:
```

### Validation Commands

After deployment, validate the setup:

```bash
# Check Auto Scaling group status
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names <asg-name>

# View scaling policies
aws autoscaling describe-policies \
    --auto-scaling-group-name <asg-name>

# Get predictive scaling forecast (after 24+ hours)
aws autoscaling get-predictive-scaling-forecast \
    --policy-arn <predictive-policy-arn>

# Monitor scaling activities
aws autoscaling describe-scaling-activities \
    --auto-scaling-group-name <asg-name> \
    --max-items 10
```

## Important Notes

### Predictive Scaling Considerations

1. **Historical Data Requirement**: Predictive scaling requires at least 24 hours of metric history. For optimal accuracy, allow 14 days of data collection.

2. **Forecast-Only Mode**: Initially deploy in "ForecastOnly" mode to evaluate forecast accuracy before enabling automatic scaling.

3. **Hybrid Scaling**: The solution combines predictive scaling (proactive) with target tracking scaling (reactive) for comprehensive load management.

4. **Machine Learning Learning Period**: The ML algorithms improve over time as they collect more data about your workload patterns.

### Cost Optimization

- Start with smaller instance types (t3.micro) for testing
- Monitor the CloudWatch dashboard to understand scaling patterns
- Adjust min/max capacity based on actual usage patterns
- Consider using Spot Instances for cost savings in non-critical environments

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name predictive-scaling-stack
```

### Using CDK
```bash
# From the respective CDK directory
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

## Troubleshooting

### Common Issues

1. **Insufficient Historical Data**: If predictive scaling policies fail to create, ensure your Auto Scaling group has been running for at least 24 hours with metric data.

2. **IAM Permissions**: Ensure the deployment role has permissions for Auto Scaling, EC2, CloudWatch, and IAM operations.

3. **Capacity Limits**: If scaling doesn't occur as expected, check service quotas and ensure max capacity settings allow for growth.

4. **Instance Launch Failures**: Verify security groups, subnets, and instance types are correctly configured for your region.

### Validation Steps

1. Verify all resources are created successfully
2. Check that instances are launching in the Auto Scaling group
3. Confirm CloudWatch metrics are being collected
4. Validate that scaling policies are active
5. Monitor the CloudWatch dashboard for at least 48 hours to observe patterns

## Advanced Configuration

### Custom Metrics

To use custom CloudWatch metrics for predictive scaling:

1. Modify the predictive scaling policy configuration
2. Specify custom metric specifications instead of predefined ones
3. Ensure custom metrics have sufficient historical data

### Multi-Metric Scaling

For more sophisticated scaling based on multiple metrics:

1. Create additional target tracking policies
2. Configure different target values for different metrics
3. Monitor the combined effect on scaling behavior

### Seasonal Patterns

For workloads with seasonal patterns:

1. Allow longer data collection periods (30+ days)
2. Consider using CloudWatch metric math for complex calculations
3. Monitor forecast accuracy during seasonal transitions

## Security Best Practices

- IAM roles follow least privilege principle
- Security groups restrict access to necessary ports only
- All resources are tagged for proper governance
- Instance profiles limit EC2 permissions to CloudWatch access only
- VPC configuration isolates resources appropriately

## Support and Documentation

- [AWS Auto Scaling Predictive Scaling Documentation](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-predictive-scaling.html)
- [Amazon CloudWatch User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)
- [AWS Auto Scaling Best Practices](https://docs.aws.amazon.com/autoscaling/ec2/userguide/auto-scaling-benefits.html)

For issues with this infrastructure code, refer to the original recipe documentation or the AWS documentation links above.