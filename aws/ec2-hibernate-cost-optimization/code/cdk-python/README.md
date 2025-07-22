# EC2 Hibernation Cost Optimization - CDK Python

This CDK Python application implements EC2 hibernation for cost optimization, creating an EC2 instance with hibernation capabilities along with CloudWatch monitoring and SNS notifications.

## Overview

This solution demonstrates how to:
- Deploy EC2 instances with hibernation enabled
- Configure CloudWatch alarms for CPU utilization monitoring
- Set up SNS notifications for cost optimization alerts
- Implement security best practices with encrypted EBS volumes and IAM roles

## Architecture

The CDK application creates:
- **VPC**: Custom VPC with public and private subnets
- **EC2 Instance**: m5.large instance with hibernation enabled
- **Security Group**: Allows SSH access (port 22)
- **Key Pair**: RSA key pair for EC2 access
- **CloudWatch Alarms**: Low and high CPU utilization monitoring
- **SNS Topic**: Email notifications for alerts
- **IAM Roles**: EC2 instance role with necessary permissions

## Prerequisites

- AWS CLI v2 installed and configured
- Python 3.8 or later
- Node.js (for CDK CLI)
- AWS CDK v2 installed globally: `npm install -g aws-cdk`

## Installation

1. **Clone the repository and navigate to the CDK Python directory:**
   ```bash
   cd aws/ec2-hibernate-cost-optimization/code/cdk-python/
   ```

2. **Create a virtual environment:**
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK (if not already done):**
   ```bash
   cdk bootstrap
   ```

## Configuration

You can customize the deployment by setting context variables in `cdk.json` or using environment variables:

### Environment Variables
```bash
export NOTIFICATION_EMAIL="your-email@example.com"
export CDK_DEFAULT_REGION="us-east-1"
export CDK_DEFAULT_ACCOUNT="123456789012"
```

### CDK Context
Edit `cdk.json` to change default values:
```json
{
  "context": {
    "notification_email": "your-email@example.com",
    "stack_name": "MyHibernationStack"
  }
}
```

## Deployment

1. **Synthesize the CDK application:**
   ```bash
   cdk synth
   ```

2. **Deploy the stack:**
   ```bash
   cdk deploy
   ```

3. **Confirm email subscription:**
   - Check your email for SNS subscription confirmation
   - Click the confirmation link to receive notifications

## Usage

After deployment, you can use the following commands to manage hibernation:

### Connect to the instance:
```bash
# Use the SSH command from stack outputs
ssh -i <key-pair-name>.pem ec2-user@<public-ip>
```

### Hibernate the instance:
```bash
aws ec2 stop-instances --instance-ids <instance-id> --hibernate
```

### Resume the instance:
```bash
aws ec2 start-instances --instance-ids <instance-id>
```

### Monitor hibernation status:
```bash
aws ec2 describe-instances --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].State.Name'
```

## Stack Outputs

The stack provides the following outputs:
- **InstanceId**: EC2 instance identifier
- **KeyPairName**: Key pair name for SSH access
- **PublicIP**: Instance public IP address
- **PrivateIP**: Instance private IP address
- **SNSTopicArn**: SNS topic ARN for notifications
- **SSHCommand**: Ready-to-use SSH command
- **HibernateCommand**: Command to hibernate the instance
- **ResumeCommand**: Command to resume the instance

## Cost Optimization Benefits

### Hibernation Cost Savings:
- **During hibernation**: Only pay for EBS storage (~$0.10/GB/month)
- **During operation**: Pay for compute + storage
- **Potential savings**: 60-70% for workloads used 8 hours/day

### CloudWatch Monitoring:
- **Low CPU alarm**: Triggers when CPU < 10% for 30 minutes
- **High CPU alarm**: Triggers when CPU > 80% for 10 minutes
- **Automated notifications**: Get alerted when hibernation might be beneficial

## Security Features

- **Encrypted EBS volumes**: All data encrypted at rest
- **IAM roles**: Least privilege access for EC2 instances
- **Security groups**: SSH access only (customize for production)
- **VPC**: Isolated network environment
- **IMDSv2**: Enforced for enhanced security

## Customization

### Instance Type
Change the instance type in `app.py`:
```python
instance_type=ec2.InstanceType.of(
    ec2.InstanceClass.M5, ec2.InstanceSize.XLARGE  # Change size
),
```

### Alarm Thresholds
Modify CloudWatch alarm thresholds:
```python
threshold=5,  # Lower threshold for more sensitive monitoring
evaluation_periods=12,  # Longer evaluation period
```

### Additional Services
Add more monitoring or automation:
- Lambda functions for automated hibernation
- EventBridge rules for scheduled hibernation
- CloudWatch dashboards for visualization

## Testing

### Validate Hibernation:
1. Deploy the stack
2. SSH to the instance and create test files
3. Hibernate the instance using the provided command
4. Resume the instance and verify files are preserved

### Monitor Alarms:
1. Generate CPU load to test high CPU alarm
2. Let instance idle to test low CPU alarm
3. Verify SNS notifications are received

## Troubleshooting

### Common Issues:

1. **Hibernation not supported**:
   - Verify instance type supports hibernation
   - Check AMI compatibility
   - Ensure EBS volume is encrypted

2. **Email notifications not received**:
   - Check email subscription confirmation
   - Verify SNS topic permissions
   - Check spam/junk folders

3. **SSH connection failed**:
   - Verify security group rules
   - Check key pair permissions (chmod 400)
   - Ensure instance is in running state

### Debugging Commands:
```bash
# Check hibernation configuration
aws ec2 describe-instances --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].HibernationOptions'

# Verify alarm state
aws cloudwatch describe-alarms --alarm-names <alarm-name>

# Check SNS subscription
aws sns list-subscriptions-by-topic --topic-arn <topic-arn>
```

## Cleanup

To avoid ongoing costs, destroy the stack when testing is complete:

```bash
cdk destroy
```

This will remove all resources created by the stack, including:
- EC2 instance and associated resources
- CloudWatch alarms
- SNS topic and subscriptions
- VPC and networking components
- IAM roles and policies

## Advanced Features

### Automated Hibernation
Extend the solution with Lambda functions:
```python
# Add Lambda function for scheduled hibernation
hibernation_lambda = _lambda.Function(
    self, "HibernationLambda",
    runtime=_lambda.Runtime.PYTHON_3_9,
    handler="hibernation.handler",
    code=_lambda.Code.from_asset("lambda"),
)
```

### Cost Tracking
Add cost monitoring:
```python
# CloudWatch custom metrics for cost tracking
cost_metric = cloudwatch.Metric(
    namespace="EC2/Hibernation",
    metric_name="CostSavings",
    dimensions_map={"InstanceId": instance.instance_id},
)
```

### Multi-AZ Deployment
Deploy across multiple availability zones:
```python
# Create instances in multiple AZs
for i, az in enumerate(vpc.availability_zones):
    instance = ec2.Instance(
        self, f"HibernationInstance{i+1}",
        vpc_subnets=ec2.SubnetSelection(
            availability_zones=[az]
        ),
        # ... other configuration
    )
```

## Best Practices

1. **Production Considerations**:
   - Restrict SSH access to specific IP ranges
   - Use Systems Manager Session Manager instead of SSH
   - Implement automated hibernation schedules
   - Monitor hibernation success/failure rates

2. **Cost Optimization**:
   - Use Spot Instances where appropriate
   - Right-size instances based on workload requirements
   - Implement automated scaling policies
   - Regular cost analysis and optimization

3. **Security**:
   - Enable CloudTrail for API logging
   - Use AWS Config for compliance monitoring
   - Implement least privilege IAM policies
   - Regular security assessments

## Support

For issues and questions:
- Check AWS CDK documentation: https://docs.aws.amazon.com/cdk/
- AWS EC2 hibernation guide: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Hibernate.html
- CDK Python API reference: https://docs.aws.amazon.com/cdk/api/v2/python/

## License

This project is licensed under the MIT License - see the LICENSE file for details.