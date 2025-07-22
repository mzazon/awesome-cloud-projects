# Infrastructure as Code for Website Uptime Monitoring with Route 53

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Website Uptime Monitoring with Route 53".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for Route 53, CloudWatch, and SNS
- Valid email address for receiving notifications
- Basic understanding of DNS and HTTP protocols

### Required AWS Permissions

Your AWS user/role needs the following permissions:
- `route53:CreateHealthCheck`
- `route53:DeleteHealthCheck`
- `route53:GetHealthCheck`
- `route53:ChangeTagsForResource`
- `cloudwatch:PutMetricAlarm`
- `cloudwatch:DeleteAlarms`
- `cloudwatch:PutDashboard`
- `cloudwatch:DeleteDashboards`
- `sns:CreateTopic`
- `sns:DeleteTopic`
- `sns:Subscribe`
- `sns:GetTopicAttributes`

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name website-uptime-monitoring \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=WebsiteUrl,ParameterValue=https://example.com \
        ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name website-uptime-monitoring

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name website-uptime-monitoring \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment variables
export WEBSITE_URL="https://example.com"
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the stack
cdk deploy --require-approval never

# Get outputs
cdk ls --long
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure environment variables
export WEBSITE_URL="https://example.com"
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the stack
cdk deploy --require-approval never

# Get outputs
cdk ls --long
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
website_url = "https://example.com"
notification_email = "your-email@example.com"
environment = "dev"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export WEBSITE_URL="https://example.com"
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Configuration Options

### Common Variables

All implementations support these configuration options:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `website_url` | URL to monitor (must be publicly accessible) | - | Yes |
| `notification_email` | Email address for alerts | - | Yes |
| `health_check_interval` | Check interval in seconds (30 or 300) | 30 | No |
| `failure_threshold` | Number of failures before alerting | 3 | No |
| `environment` | Environment tag (dev/staging/prod) | dev | No |
| `enable_latency_measurement` | Enable latency metrics | true | No |

### Advanced Configuration

#### Health Check Regions
Some implementations support configuring specific AWS regions for health checks:

```bash
# Example for Terraform
terraform apply -var="health_check_regions=[\"us-east-1\",\"eu-west-1\",\"ap-southeast-1\"]"
```

#### Custom Dashboard
Dashboard widgets and layout can be customized in the implementation files.

#### SNS Topic Configuration
Additional SNS subscribers (SMS, HTTP endpoints) can be added after deployment.

## Post-Deployment Steps

1. **Confirm SNS Subscription**: Check your email and confirm the SNS subscription
2. **Verify Health Check**: Wait 2-3 minutes for the health check to initialize
3. **Test Notifications**: Use the AWS console to manually trigger an alarm
4. **Access Dashboard**: View the CloudWatch dashboard using the output URL

## Monitoring and Maintenance

### Health Check Status
```bash
# Check health check status
aws route53 get-health-check --health-check-id <HEALTH_CHECK_ID>

# View CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Route53 \
    --metric-name HealthCheckStatus \
    --dimensions Name=HealthCheckId,Value=<HEALTH_CHECK_ID> \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

### Dashboard Access
```bash
# Get dashboard URL from outputs
aws cloudformation describe-stacks \
    --stack-name website-uptime-monitoring \
    --query 'Stacks[0].Outputs[?OutputKey==`DashboardUrl`].OutputValue' \
    --output text
```

### Cost Monitoring
- Standard health checks: $0.50/month each
- Calculated health checks: $1.00/month each
- CloudWatch alarms: $0.10/month each
- SNS notifications: $0.50/million notifications

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name website-uptime-monitoring

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name website-uptime-monitoring
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy --force
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Health Check Fails Immediately**
   - Verify the website URL is publicly accessible
   - Check firewall and security group rules
   - Ensure SSL certificate is valid for HTTPS endpoints

2. **No Email Notifications**
   - Confirm SNS subscription in your email
   - Check spam folder for AWS notifications
   - Verify email address in deployment parameters

3. **Dashboard Shows No Data**
   - Wait 5-10 minutes for metrics to populate
   - Verify health check is in "Success" status
   - Check CloudWatch region (Route 53 metrics are in us-east-1)

4. **Permission Errors**
   - Review required IAM permissions above
   - Ensure AWS CLI is configured with appropriate credentials
   - Check AWS CloudTrail logs for specific permission denials

### Debugging Commands

```bash
# Check Route 53 health check status
aws route53 list-health-checks --query 'HealthChecks[?Config.FullyQualifiedDomainName==`example.com`]'

# View CloudWatch alarm history
aws cloudwatch describe-alarm-history --alarm-name <ALARM_NAME>

# List SNS subscriptions
aws sns list-subscriptions-by-topic --topic-arn <TOPIC_ARN>

# Test website accessibility
curl -I -w "%{http_code}\n" -o /dev/null -s <WEBSITE_URL>
```

## Customization

### Extending the Solution

1. **Multiple Endpoints**: Modify the code to monitor multiple websites
2. **Calculated Health Checks**: Combine multiple health checks with Boolean logic
3. **Additional Metrics**: Add custom CloudWatch metrics and alarms
4. **Automated Remediation**: Integrate with Lambda functions for auto-remediation
5. **Slack Integration**: Add Slack notifications via SNS HTTP endpoints

### Integration Examples

```bash
# Add SMS notifications
aws sns subscribe \
    --topic-arn <SNS_TOPIC_ARN> \
    --protocol sms \
    --notification-endpoint +1234567890

# Create additional health check for API endpoint
aws route53 create-health-check \
    --caller-reference "api-monitor-$(date +%s)" \
    --health-check-config Type=HTTPS,ResourcePath=/api/health,FullyQualifiedDomainName=api.example.com,Port=443
```

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service documentation for Route 53, CloudWatch, and SNS
3. Validate your AWS permissions and service limits
4. Use AWS Support for service-specific issues

## Security Considerations

- Health checks are public and don't require authentication
- SNS topics use email subscriptions with confirmation
- CloudWatch dashboards are private to your AWS account
- No sensitive data is stored in the infrastructure
- All resources are tagged for proper governance

## Version Compatibility

- **AWS CLI**: v2.0+
- **CDK**: v2.0+
- **Terraform**: v1.0+
- **CloudFormation**: All versions
- **Node.js**: v14+ (for CDK TypeScript)
- **Python**: v3.7+ (for CDK Python)