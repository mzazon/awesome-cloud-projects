# Infrastructure as Code for Simple Website Uptime Monitoring with Route53 and SNS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Website Uptime Monitoring with Route53 and SNS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates an automated uptime monitoring system using:

- **Route53 Health Check**: Monitors website availability from global locations
- **SNS Topic**: Delivers email notifications for alerts
- **CloudWatch Alarms**: Triggers notifications on health check status changes
- **Email Subscription**: Receives uptime/downtime alerts

## Prerequisites

- AWS CLI installed and configured (version 2.0 or higher)
- Appropriate AWS permissions for Route53, SNS, and CloudWatch
- A publicly accessible website URL to monitor (HTTP or HTTPS)
- Valid email address for receiving alerts
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0 or higher

> **Cost Estimate**: Approximately $0.50-$2.00 per month for basic monitoring

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name uptime-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=WebsiteUrl,ParameterValue=https://example.com \
                 ParameterKey=AdminEmail,ParameterValue=admin@example.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name uptime-monitoring-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name uptime-monitoring-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment variables (optional)
export WEBSITE_URL=https://example.com
export ADMIN_EMAIL=admin@example.com

# Deploy the stack
cdk bootstrap  # First time only
cdk deploy

# View stack outputs
cdk outputs
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment and install dependencies
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Configure environment variables (optional)
export WEBSITE_URL=https://example.com
export ADMIN_EMAIL=admin@example.com

# Deploy the stack
cdk bootstrap  # First time only
cdk deploy

# View stack outputs
cdk outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
website_url = "https://example.com"
admin_email = "admin@example.com"
aws_region  = "us-east-1"
EOF

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export WEBSITE_URL=https://example.com
export ADMIN_EMAIL=admin@example.com
export AWS_REGION=us-east-1

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output resource ARNs and confirmation steps
```

## Configuration Parameters

All implementations support the following configuration parameters:

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `website_url` | The website URL to monitor (HTTP or HTTPS) | - | Yes |
| `admin_email` | Email address for receiving alerts | - | Yes |
| `aws_region` | AWS region for deployment | us-east-1 | No |
| `health_check_interval` | Health check frequency (10 or 30 seconds) | 30 | No |
| `failure_threshold` | Number of failures before alarm | 3 | No |
| `enable_recovery_notifications` | Send notifications when site recovers | true | No |

## Post-Deployment Steps

1. **Confirm Email Subscription**: Check your email inbox for an AWS SNS confirmation message and click the confirmation link to activate alert delivery.

2. **Verify Health Check**: Monitor the health check status in the AWS Route53 console to ensure it's functioning correctly.

3. **Test Monitoring**: You can test the system by temporarily blocking access to your website or using the AWS CLI to check alarm states.

## Validation Commands

After deployment, verify the system is working:

```bash
# Check health check status
aws route53 get-health-check-status --health-check-id <HEALTH_CHECK_ID>

# Verify SNS subscription
aws sns list-subscriptions-by-topic --topic-arn <TOPIC_ARN>

# Check CloudWatch alarms
aws cloudwatch describe-alarms --alarm-names "Website-Down-*"

# View recent health check metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Route53 \
    --metric-name HealthCheckStatus \
    --dimensions Name=HealthCheckId,Value=<HEALTH_CHECK_ID> \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Minimum,Maximum
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name uptime-monitoring-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name uptime-monitoring-stack
```

### Using CDK

```bash
# TypeScript
cd cdk-typescript/
cdk destroy

# Python
cd cdk-python/
source .venv/bin/activate
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

1. **Email Not Confirmed**: If you're not receiving alerts, check that you've confirmed the SNS email subscription.

2. **Health Check False Positives**: If you're getting false alarms, consider increasing the failure threshold or check your website's response time.

3. **Permission Errors**: Ensure your AWS credentials have the necessary permissions for Route53, SNS, and CloudWatch.

4. **Website Not Accessible**: Verify your website URL is publicly accessible and returns HTTP 200 responses.

### Debug Commands

```bash
# Check health check details
aws route53 get-health-check --health-check-id <HEALTH_CHECK_ID>

# View alarm history
aws cloudwatch describe-alarm-history \
    --alarm-name "Website-Down-<NAME>" \
    --max-records 10

# Test SNS topic
aws sns publish \
    --topic-arn <TOPIC_ARN> \
    --message "Test notification from uptime monitoring system"
```

## Customization

### Advanced Configuration

You can extend this solution by:

1. **Multiple Websites**: Modify the templates to monitor multiple URLs
2. **Different Notification Channels**: Add SMS or Slack notifications
3. **Custom Health Check Paths**: Monitor specific endpoints beyond the root path
4. **Response Time Monitoring**: Add alarms for website performance metrics
5. **Multi-Region Monitoring**: Deploy health checks from multiple AWS regions

### Security Considerations

- The solution follows AWS security best practices with least privilege IAM roles
- Email addresses are stored securely within AWS SNS
- Health checks use HTTPS when available for encrypted monitoring
- CloudWatch alarms prevent notification spam with appropriate thresholds

## Cost Optimization

- Route53 health checks: $0.50 per health check per month
- CloudWatch alarms: $0.10 per alarm per month (first 10 alarms free)
- SNS notifications: $0.50 per 1 million notifications
- Total estimated cost: $0.50-$2.00 per month for basic monitoring

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation in the parent directory
2. Check AWS service documentation for Route53, SNS, and CloudWatch
3. Verify your AWS account permissions and service limits
4. Use the AWS CLI debug mode for detailed error information: `aws --debug <command>`

## Version Information

- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12
- **CDK Version**: Latest stable (v2.x)
- **Terraform AWS Provider**: ~> 5.0
- **CloudFormation Template Version**: 2010-09-09