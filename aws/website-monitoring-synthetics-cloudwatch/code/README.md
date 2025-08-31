# Infrastructure as Code for Website Monitoring with CloudWatch Synthetics

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Website Monitoring with CloudWatch Synthetics". This solution provides proactive website monitoring using automated canary testing that simulates real user interactions, capturing performance metrics, visual evidence, and error conditions before they impact customers.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

The solution deploys:
- CloudWatch Synthetics Canary for automated website monitoring
- S3 bucket for storing canary artifacts (screenshots, HAR files, logs)
- IAM role with appropriate permissions for canary execution
- CloudWatch alarms for failure and response time monitoring
- SNS topic for email notifications
- CloudWatch dashboard for monitoring visualization

## Prerequisites

- AWS CLI installed and configured (v2.15 or later)
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)
- Appropriate AWS permissions for:
  - CloudWatch Synthetics
  - S3 bucket creation and management
  - IAM role creation
  - CloudWatch alarms and dashboards
  - SNS topic management

## Configuration

All implementations support the following customizable parameters:

- `WebsiteUrl`: The website URL to monitor (default: https://example.com)
- `NotificationEmail`: Email address for alerts
- `CanarySchedule`: Monitoring frequency (default: rate(5 minutes))
- `ResponseTimeThreshold`: Alert threshold in milliseconds (default: 10000)
- `SuccessThreshold`: Success percentage threshold (default: 90)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name website-monitoring-synthetics \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=WebsiteUrl,ParameterValue=https://your-website.com \
                 ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name website-monitoring-synthetics \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name website-monitoring-synthetics \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment variables (optional)
export WEBSITE_URL=https://your-website.com
export NOTIFICATION_EMAIL=your-email@example.com

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy
cdk deploy

# Get outputs
cdk outputs
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # Linux/macOS
# .venv\Scripts\activate   # Windows

# Install dependencies
pip install -r requirements.txt

# Configure environment variables (optional)
export WEBSITE_URL=https://your-website.com
export NOTIFICATION_EMAIL=your-email@example.com

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy
cdk deploy

# Get outputs
cdk outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file (optional)
cat > terraform.tfvars << EOF
website_url = "https://your-website.com"
notification_email = "your-email@example.com"
canary_name = "my-website-monitor"
EOF

# Preview changes
terraform plan

# Deploy
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export WEBSITE_URL=https://your-website.com
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Post-Deployment Steps

1. **Confirm SNS Subscription**: Check your email for SNS subscription confirmation and click the confirmation link.

2. **Verify Canary Status**: 
   ```bash
   aws synthetics get-canary --name [canary-name]
   ```

3. **Access Dashboard**: Navigate to the CloudWatch console to view the monitoring dashboard.

4. **Review S3 Artifacts**: Check the S3 bucket for generated screenshots and logs:
   ```bash
   aws s3 ls s3://[bucket-name]/canary-artifacts/ --recursive
   ```

## Monitoring and Alerts

The solution creates the following monitoring components:

- **Success Rate Alarm**: Triggers when success percentage falls below 90%
- **Response Time Alarm**: Triggers when average response time exceeds 10 seconds
- **CloudWatch Dashboard**: Visualizes canary metrics and test results
- **SNS Notifications**: Email alerts for alarm conditions

## Cost Considerations

Estimated monthly costs (us-east-1):
- CloudWatch Synthetics: ~$53.57/month (5-minute intervals, after free tier)
- S3 Storage: ~$0.023/GB/month for artifacts
- CloudWatch Logs: ~$0.50/GB ingested
- SNS: $0.50 per million email notifications

> **Note**: CloudWatch Synthetics includes 100 free canary runs per month. Costs increase with more frequent monitoring or multiple canaries.

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name website-monitoring-synthetics

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name website-monitoring-synthetics \
    --query 'Stacks[0].StackStatus'
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
./scripts/destroy.sh
```

## Customization

### Canary Script Modifications

To modify the monitoring logic, update the canary script in your chosen implementation:

- **Custom Page Elements**: Add specific DOM element checks
- **User Interactions**: Simulate form submissions, clicks, or navigation
- **Performance Metrics**: Add custom timing measurements
- **Error Handling**: Implement specific error detection logic

### Advanced Configuration

- **Multi-Region Monitoring**: Deploy canaries in multiple AWS regions
- **Custom Metrics**: Add business-specific CloudWatch metrics
- **Integration Testing**: Extend scripts for end-to-end user journeys
- **Alerting Escalation**: Implement tiered alerting with different thresholds

### Security Enhancements

- **VPC Endpoint**: Deploy canary within VPC for private resource monitoring
- **Encryption**: Enable S3 bucket encryption for artifact storage
- **IAM Restrictions**: Further restrict canary execution permissions
- **Access Logging**: Enable CloudTrail for audit compliance

## Troubleshooting

### Common Issues

1. **Canary Fails to Start**:
   - Verify IAM role permissions
   - Check S3 bucket accessibility
   - Validate canary script syntax

2. **No Metrics Appearing**:
   - Confirm canary is running
   - Check CloudWatch Logs for errors
   - Verify metric namespace and dimensions

3. **Alerts Not Received**:
   - Confirm SNS subscription
   - Check email spam filters
   - Verify alarm configuration

### Debug Commands

```bash
# Check canary runs
aws synthetics get-canary-runs --name [canary-name] --max-results 5

# View canary logs
aws logs describe-log-groups --log-group-name-prefix /aws/synthetics

# Check S3 artifacts
aws s3 ls s3://[bucket-name]/canary-artifacts/ --recursive --human-readable
```

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check AWS CloudWatch Synthetics documentation
3. Review AWS support resources for specific services
4. Consult the AWS Well-Architected Framework for operational excellence

## Additional Resources

- [AWS CloudWatch Synthetics User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Synthetics_Canaries.html)
- [Synthetics Canary Blueprints](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Synthetics_Library.html)
- [AWS Well-Architected Operational Excellence](https://docs.aws.amazon.com/wellarchitected/latest/operational-excellence-pillar/welcome.html)
- [Puppeteer Documentation](https://pptr.dev/) for advanced canary scripting