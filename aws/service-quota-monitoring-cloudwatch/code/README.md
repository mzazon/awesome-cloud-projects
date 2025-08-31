# Infrastructure as Code for Service Quota Monitoring with CloudWatch Alarms

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Service Quota Monitoring with CloudWatch Alarms".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions for Service Quotas, CloudWatch, and SNS
- Valid email address for receiving quota notifications
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform >= 1.0

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name service-quota-monitoring \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name service-quota-monitoring \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set notification email (required)
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the infrastructure
cdk deploy --parameters notificationEmail=$NOTIFICATION_EMAIL

# Confirm email subscription when prompted
```

### Using CDK Python

```bash
cd cdk-python/

# Install dependencies
pip install -r requirements.txt

# Set notification email (required)
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the infrastructure
cdk deploy --parameters notificationEmail=$NOTIFICATION_EMAIL

# Confirm email subscription when prompted
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your email
echo 'notification_email = "your-email@example.com"' > terraform.tfvars

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# Confirm email subscription when prompted
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set notification email (required)
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the infrastructure
./scripts/deploy.sh

# Confirm email subscription when prompted
```

## Architecture Overview

This solution deploys:

- **SNS Topic**: Central notification hub for quota alerts
- **Email Subscription**: Delivers notifications to operations teams
- **CloudWatch Alarms**: Monitor service quota utilization at 80% threshold
  - EC2 Running Instances quota
  - VPC quota
  - Lambda Concurrent Executions quota

## Configuration Options

### CloudFormation Parameters

- `NotificationEmail`: Email address for quota notifications (required)
- `AlarmThreshold`: Quota utilization percentage threshold (default: 80)
- `TopicNameSuffix`: Custom suffix for SNS topic name (optional)

### CDK Context Variables

- `notificationEmail`: Email address for quota notifications (required)
- `alarmThreshold`: Quota utilization percentage threshold (default: 80)

### Terraform Variables

- `notification_email`: Email address for quota notifications (required)
- `alarm_threshold`: Quota utilization percentage threshold (default: 80)
- `aws_region`: AWS region for deployment (default: current region)

## Post-Deployment Steps

1. **Confirm Email Subscription**: Check your email and click the confirmation link from AWS SNS
2. **Test Notifications**: Use the AWS CLI to test alarm functionality:
   ```bash
   aws cloudwatch set-alarm-state \
       --alarm-name "EC2-Running-Instances-Quota-Alert" \
       --state-value ALARM \
       --state-reason "Testing notification system"
   ```
3. **Monitor Quotas**: View quota utilization in the CloudWatch console under AWS/ServiceQuotas namespace

## Validation & Testing

### Verify Deployment

```bash
# Check SNS topic and subscription
aws sns list-topics --query 'Topics[?contains(TopicArn, `service-quota-alerts`)]'

# Verify CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-names "EC2-Running-Instances-Quota-Alert" \
                  "VPC-Quota-Alert" \
                  "Lambda-Concurrent-Executions-Quota-Alert" \
    --query 'MetricAlarms[*].[AlarmName,StateValue]' \
    --output table

# Check service quota metrics
aws cloudwatch list-metrics \
    --namespace AWS/ServiceQuotas \
    --metric-name ServiceQuotaUtilization
```

### Test Notification System

```bash
# Trigger test alarm
aws cloudwatch set-alarm-state \
    --alarm-name "EC2-Running-Instances-Quota-Alert" \
    --state-value ALARM \
    --state-reason "Testing alarm notification system"

# Reset alarm state
aws cloudwatch set-alarm-state \
    --alarm-name "EC2-Running-Instances-Quota-Alert" \
    --state-value OK \
    --state-reason "Test complete"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name service-quota-monitoring

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name service-quota-monitoring \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy the infrastructure
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted
```

## Customization

### Adding Additional Service Quotas

To monitor additional AWS service quotas:

1. **Identify Quota Codes**: Use the Service Quotas console or CLI to find quota codes
   ```bash
   aws service-quotas list-service-quotas \
       --service-code <service-code> \
       --query 'Quotas[*].[QuotaCode,QuotaName]'
   ```

2. **Add CloudWatch Alarms**: Create additional alarms for new quota codes
3. **Update IaC Templates**: Add new alarm resources to your chosen IaC implementation

### Modifying Alert Thresholds

- **CloudFormation**: Update the `AlarmThreshold` parameter
- **CDK**: Modify the `alarmThreshold` context variable
- **Terraform**: Change the `alarm_threshold` variable
- **Bash Scripts**: Edit the threshold values in the deployment script

### Custom Notification Channels

Extend notifications beyond email:

1. **Slack Integration**: Add Lambda function to forward SNS messages to Slack
2. **SMS Notifications**: Add SMS subscription to the SNS topic
3. **PagerDuty Integration**: Configure SNS to trigger PagerDuty incidents
4. **Microsoft Teams**: Use Logic Apps connector for Teams notifications

## Monitoring and Maintenance

### Regular Tasks

- **Review Quota Utilization**: Check CloudWatch metrics weekly
- **Update Alert Thresholds**: Adjust based on usage patterns
- **Audit Subscriptions**: Ensure notification recipients are current
- **Test Alerts**: Monthly test of notification system

### Troubleshooting

#### Common Issues

1. **No Email Notifications**:
   - Verify email subscription is confirmed
   - Check spam/junk folders
   - Validate SNS topic permissions

2. **Alarm Not Triggering**:
   - Confirm Service Quotas publishes metrics for the service
   - Verify alarm configuration and threshold
   - Check metric availability in CloudWatch

3. **High False Positive Rate**:
   - Adjust evaluation periods
   - Modify threshold percentages
   - Use composite alarms for complex logic

#### Debug Commands

```bash
# Check alarm history
aws cloudwatch describe-alarm-history \
    --alarm-name "EC2-Running-Instances-Quota-Alert"

# View metric statistics
aws cloudwatch get-metric-statistics \
    --namespace AWS/ServiceQuotas \
    --metric-name ServiceQuotaUtilization \
    --dimensions Name=ServiceCode,Value=ec2 Name=QuotaCode,Value=L-1216C47A \
    --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Maximum
```

## Cost Considerations

### Pricing Components

- **CloudWatch Alarms**: $0.10 per alarm per month (first 10 alarms free)
- **SNS Notifications**: $0.50 per 1M email notifications
- **CloudWatch Metrics**: No additional cost for Service Quotas metrics

### Cost Optimization

- Monitor only critical service quotas to minimize alarm costs
- Use composite alarms to reduce total alarm count
- Leverage AWS Free Tier allowances where available
- Regular review and cleanup of unused alarms

## Security Best Practices

### Implemented Security Measures

- **Least Privilege IAM**: Minimal permissions for CloudWatch and SNS access
- **Encryption**: SNS topics use AWS managed encryption
- **Resource Tagging**: All resources tagged for governance and cost allocation

### Additional Security Recommendations

- **Cross-Account Access**: Use IAM roles for multi-account scenarios
- **VPC Endpoints**: Use VPC endpoints for private API access
- **CloudTrail Logging**: Enable logging for SNS and CloudWatch API calls
- **Access Logging**: Monitor who accesses notification endpoints

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# Example GitHub Actions workflow
name: Deploy Quota Monitoring
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      - name: Deploy with Terraform
        run: |
          cd terraform/
          terraform init
          terraform apply -auto-approve \
            -var="notification_email=${{ secrets.NOTIFICATION_EMAIL }}"
```

### Multi-Region Deployment

```bash
# Deploy to multiple regions using CloudFormation StackSets
aws cloudformation create-stack-set \
    --stack-set-name service-quota-monitoring-global \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=ops@company.com \
    --capabilities CAPABILITY_IAM

# Deploy to specific regions
aws cloudformation create-stack-instances \
    --stack-set-name service-quota-monitoring-global \
    --regions us-east-1 us-west-2 eu-west-1 \
    --accounts 123456789012
```

## Support and Contributing

### Getting Help

- **AWS Documentation**: [Service Quotas User Guide](https://docs.aws.amazon.com/servicequotas/latest/userguide/)
- **CloudWatch Alarms**: [CloudWatch User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)
- **SNS Notifications**: [SNS Developer Guide](https://docs.aws.amazon.com/sns/latest/dg/)

### Reporting Issues

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS service status and quotas
3. Validate IAM permissions and resource configurations
4. Refer to the original recipe documentation

### Enhancement Requests

Consider contributing improvements such as:
- Additional service quota monitoring
- Enhanced notification formatting
- Custom dashboard integration
- Automated quota increase requests
- Multi-account deployment patterns

---

*This infrastructure code accompanies the "Service Quota Monitoring with CloudWatch Alarms" recipe. For complete implementation guidance, refer to the original recipe documentation.*