# Infrastructure as Code for Simple SSL Certificate Monitoring with Certificate Manager and SNS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple SSL Certificate Monitoring with Certificate Manager and SNS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured
- Appropriate AWS permissions for:
  - Certificate Manager (ACM)
  - Simple Notification Service (SNS)
  - CloudWatch (alarms and metrics)
  - IAM (for service roles if needed)
- An existing SSL certificate in AWS Certificate Manager
- Valid email address for receiving alert notifications

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name ssl-cert-monitoring \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
                 ParameterKey=CertificateArn,ParameterValue=arn:aws:acm:region:account:certificate/cert-id \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name ssl-cert-monitoring \
    --query 'Stacks[0].StackStatus'

# Get outputs after deployment
aws cloudformation describe-stacks \
    --stack-name ssl-cert-monitoring \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure deployment parameters
export NOTIFICATION_EMAIL=your-email@example.com
export CERTIFICATE_ARN=arn:aws:acm:region:account:certificate/cert-id

# Deploy the stack
cdk bootstrap  # First time only
cdk deploy

# View stack outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment and install dependencies
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Configure deployment parameters
export NOTIFICATION_EMAIL=your-email@example.com
export CERTIFICATE_ARN=arn:aws:acm:region:account:certificate/cert-id

# Deploy the stack
cdk bootstrap  # First time only
cdk deploy

# View stack outputs
cdk ls --long
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
certificate_arn = "arn:aws:acm:region:account:certificate/cert-id"
aws_region = "us-east-1"
environment = "dev"
EOF

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

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export CERTIFICATE_ARN=arn:aws:acm:region:account:certificate/cert-id
export AWS_REGION=us-east-1

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment
aws sns list-topics --query 'Topics[?contains(TopicArn, `ssl-cert-alerts`)]'
aws cloudwatch describe-alarms --query 'MetricAlarms[?contains(AlarmName, `SSL-Certificate-Expiring`)]'
```

## Configuration Parameters

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `notification_email` | Email address for receiving certificate expiration alerts | Yes | - |
| `certificate_arn` | ARN of the SSL certificate to monitor | Yes | - |
| `alarm_threshold_days` | Number of days before expiration to trigger alarm | No | 30 |
| `aws_region` | AWS region for deployment | No | Current CLI region |
| `environment` | Environment tag for resources | No | dev |

## Post-Deployment Steps

1. **Confirm Email Subscription**: Check your email inbox for an SNS subscription confirmation and click the confirmation link.

2. **Verify Certificate Metrics**: Wait up to 24 hours for ACM to publish DaysToExpiry metrics to CloudWatch.

3. **Test Notifications**: 
   ```bash
   # Send a test notification
   SNS_TOPIC_ARN=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `ssl-cert-alerts`)].TopicArn' --output text)
   aws sns publish \
       --topic-arn ${SNS_TOPIC_ARN} \
       --message "Test: SSL Certificate Monitoring System Active" \
       --subject "SSL Certificate Alert Test"
   ```

4. **Monitor Alarm Status**:
   ```bash
   # Check alarm state
   aws cloudwatch describe-alarms \
       --query 'MetricAlarms[?contains(AlarmName, `SSL-Certificate-Expiring`)][AlarmName,StateValue,StateReason]' \
       --output table
   ```

## Monitoring and Maintenance

### Viewing Certificate Status
```bash
# List all monitored certificates
aws acm list-certificates --certificate-statuses ISSUED

# Get specific certificate details
aws acm describe-certificate --certificate-arn YOUR_CERTIFICATE_ARN

# View certificate expiration metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/CertificateManager \
    --metric-name DaysToExpiry \
    --dimensions Name=CertificateArn,Value=YOUR_CERTIFICATE_ARN \
    --start-time $(date -d '7 days ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 86400 \
    --statistics Minimum
```

### Adding Additional Certificates
```bash
# For Terraform - add to terraform.tfvars
additional_certificates = [
  "arn:aws:acm:region:account:certificate/cert-id-2",
  "arn:aws:acm:region:account:certificate/cert-id-3"
]

# Then apply changes
terraform plan
terraform apply
```

### Updating Alarm Thresholds
```bash
# Update alarm threshold to 60 days
aws cloudwatch put-metric-alarm \
    --alarm-name "SSL-Certificate-Expiring-SUFFIX" \
    --threshold 60 \
    [other alarm parameters remain the same]
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name ssl-cert-monitoring

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name ssl-cert-monitoring \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted
```

## Troubleshooting

### Common Issues

1. **Missing Certificate Metrics**: ACM publishes DaysToExpiry metrics twice daily. Wait up to 24 hours after certificate creation or alarm setup.

2. **Email Not Received**: Check spam folder and ensure email address is correct. Verify SNS subscription status:
   ```bash
   aws sns list-subscriptions-by-topic --topic-arn YOUR_TOPIC_ARN
   ```

3. **Alarm in INSUFFICIENT_DATA State**: This is normal for new alarms. CloudWatch needs metric data points to evaluate the alarm condition.

4. **Permission Errors**: Ensure your AWS credentials have permissions for ACM, SNS, CloudWatch, and IAM operations.

### Debugging Commands

```bash
# Check CloudWatch alarm history
aws cloudwatch describe-alarm-history \
    --alarm-name "SSL-Certificate-Expiring-SUFFIX"

# Verify SNS topic configuration
aws sns get-topic-attributes --topic-arn YOUR_TOPIC_ARN

# Check ACM certificate status
aws acm describe-certificate --certificate-arn YOUR_CERTIFICATE_ARN \
    --query 'Certificate.[Status,DomainName,NotAfter]'
```

## Security Considerations

- SNS topics are configured with appropriate access policies
- CloudWatch alarms use least privilege IAM permissions
- Email addresses in SNS subscriptions should be from trusted domains
- Consider using SNS message filtering for complex notification routing
- Regularly review and rotate access credentials

## Cost Optimization

- CloudWatch alarms cost approximately $0.10/month per alarm
- SNS email notifications are free for the first 1,000 notifications/month
- ACM certificates are free when used with AWS services
- Consider consolidating multiple certificate monitoring into fewer alarms where appropriate

## Customization

### Adding Multiple Certificates
Modify the infrastructure code to include additional certificate ARNs in the monitoring configuration. Each implementation type supports multiple certificates through configuration arrays or loops.

### Custom Notification Channels
Extend the SNS topic to include additional endpoints:
- SMS notifications for critical alerts
- Slack/Teams integration via HTTP endpoints
- Lambda functions for automated remediation
- PagerDuty or other incident management systems

### Advanced Monitoring
Enhance the solution with additional metrics:
- Certificate chain validation
- Certificate authority monitoring
- Domain validation status tracking
- Integration with AWS Config for compliance monitoring

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Refer to the original recipe documentation
3. Consult AWS documentation for specific services:
   - [AWS Certificate Manager](https://docs.aws.amazon.com/acm/)
   - [Amazon CloudWatch](https://docs.aws.amazon.com/cloudwatch/)
   - [Amazon SNS](https://docs.aws.amazon.com/sns/)
4. Review AWS service quotas and limits
5. Check AWS Service Health Dashboard for service issues