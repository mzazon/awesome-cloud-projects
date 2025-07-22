# Infrastructure as Code for Delivering Scheduled Reports with App Runner and SES

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Delivering Scheduled Reports with App Runner and SES".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates a serverless email reporting system that includes:

- **AWS App Runner Service**: Containerized Flask application for report generation
- **Amazon SES**: Email delivery service with verified sender identity
- **EventBridge Scheduler**: Automated daily report scheduling at 9 AM UTC
- **CloudWatch**: Monitoring, logging, and alerting for the entire system
- **IAM Roles**: Least-privilege access for App Runner and EventBridge Scheduler

## Prerequisites

- AWS CLI v2 installed and configured
- Docker installed locally (for testing containerized application)
- AWS account with appropriate permissions:
  - App Runner: `apprunner:*`
  - SES: `ses:*`
  - EventBridge Scheduler: `scheduler:*`
  - CloudWatch: `cloudwatch:*`
  - IAM: `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PassRole`
- Verified email address or domain in Amazon SES
- GitHub account for source code repository integration
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Configuration

Before deployment, you'll need to configure these values:

- **SES_VERIFIED_EMAIL**: Your verified email address for sending reports
- **GITHUB_REPO_URL**: Your GitHub repository URL containing the Flask application
- **AWS_REGION**: Target AWS region for deployment
- **SCHEDULE_EXPRESSION**: Cron expression for report scheduling (default: daily at 9 AM UTC)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name scheduled-email-reports \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=SESVerifiedEmail,ParameterValue=your-email@example.com \
        ParameterKey=GitHubRepoUrl,ParameterValue=https://github.com/username/repo \
    --capabilities CAPABILITY_IAM

# Wait for deployment completion
aws cloudformation wait stack-create-complete \
    --stack-name scheduled-email-reports

# Get outputs
aws cloudformation describe-stacks \
    --stack-name scheduled-email-reports \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure deployment parameters
export SES_VERIFIED_EMAIL="your-email@example.com"
export GITHUB_REPO_URL="https://github.com/username/repo"

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure deployment parameters
export SES_VERIFIED_EMAIL="your-email@example.com"
export GITHUB_REPO_URL="https://github.com/username/repo"

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
ses_verified_email = "your-email@example.com"
github_repo_url   = "https://github.com/username/repo"
aws_region        = "us-east-1"
schedule_expression = "cron(0 9 * * ? *)"
EOF

# Review deployment plan
terraform plan

# Deploy infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export SES_VERIFIED_EMAIL="your-email@example.com"
export GITHUB_REPO_URL="https://github.com/username/repo"
export AWS_REGION="us-east-1"

# Deploy the solution
./scripts/deploy.sh

# View deployment outputs
./scripts/deploy.sh --status
```

## Verification

After deployment, verify the solution is working:

1. **Check App Runner Service**:
   ```bash
   # Get service URL from deployment outputs
   SERVICE_URL=$(aws apprunner describe-service \
       --service-name email-reports-service \
       --query 'Service.ServiceUrl' --output text)
   
   # Test health endpoint
   curl https://${SERVICE_URL}/health
   ```

2. **Test Report Generation**:
   ```bash
   # Manually trigger report generation
   curl -X POST https://${SERVICE_URL}/generate-report \
       -H "Content-Type: application/json"
   ```

3. **Verify Email Delivery**:
   Check your email inbox for the generated business report.

4. **Monitor CloudWatch**:
   ```bash
   # Check custom metrics
   aws cloudwatch get-metric-statistics \
       --namespace EmailReports \
       --metric-name ReportsGenerated \
       --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
       --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
       --period 3600 \
       --statistics Sum
   ```

## Customization

### Report Scheduling

Modify the schedule expression to change report timing:

- **Daily at 6 AM UTC**: `cron(0 6 * * ? *)`
- **Weekdays at 9 AM UTC**: `cron(0 9 ? * MON-FRI *)`
- **Weekly on Mondays**: `cron(0 9 ? * MON *)`
- **Monthly on the 1st**: `cron(0 9 1 * ? *)`

### Application Configuration

The Flask application can be customized by modifying:

- Report data sources (connect to databases or APIs)
- Email templates and formatting
- Recipient lists and personalization
- Report frequency and scheduling logic

### Monitoring and Alerting

Customize CloudWatch alarms by adjusting:

- Threshold values for failure detection
- Notification targets (SNS topics, email addresses)
- Evaluation periods and comparison operators
- Dashboard widgets and metrics

### Security Configuration

Enhance security by:

- Implementing VPC endpoints for private communication
- Adding WAF rules for App Runner service protection
- Configuring SES sending authorization policies
- Implementing secrets management for sensitive configuration

## Troubleshooting

### Common Issues

1. **App Runner Service Not Starting**:
   - Check CloudWatch logs: `/aws/apprunner/{service-name}`
   - Verify Docker container builds successfully locally
   - Ensure GitHub repository is accessible and contains proper files

2. **Email Not Sending**:
   - Verify SES email address is verified
   - Check if AWS account is in SES sandbox mode
   - Review IAM permissions for SES access

3. **Schedule Not Triggering**:
   - Verify EventBridge Scheduler permissions
   - Check cron expression syntax
   - Review CloudWatch logs for scheduler execution

4. **Permission Errors**:
   - Ensure deployment user has sufficient IAM permissions
   - Verify IAM roles have correct trust policies
   - Check resource-based policies for cross-service access

### Debugging Commands

```bash
# Check App Runner service status
aws apprunner describe-service --service-name email-reports-service

# View application logs
aws logs tail /aws/apprunner/email-reports-service --follow

# Check SES statistics
aws ses get-send-statistics

# Verify EventBridge schedule
aws scheduler get-schedule --name daily-report-schedule

# Check CloudWatch metrics
aws cloudwatch list-metrics --namespace EmailReports
```

## Cost Optimization

### Estimated Costs

- **App Runner**: ~$5-10/month for 0.25 vCPU, 0.5 GB memory with light usage
- **SES**: $0.10 per 1,000 emails sent
- **EventBridge Scheduler**: $1.00 per 1 million invocations
- **CloudWatch**: ~$1-3/month for logs and metrics storage

### Cost Reduction Tips

1. **Right-size App Runner**: Start with minimal CPU/memory and scale as needed
2. **Optimize Logging**: Configure log retention periods appropriately
3. **Monitor Usage**: Use AWS Cost Explorer to track spending
4. **Regional Considerations**: Deploy in regions with lower costs if latency permits

## Security Best Practices

### Implemented Security Controls

- **Least Privilege IAM**: Roles have minimal required permissions
- **Encryption in Transit**: HTTPS for all API communications
- **VPC Security**: App Runner service runs in AWS-managed secure environment
- **Email Authentication**: SES handles SPF, DKIM, and DMARC automatically

### Additional Security Recommendations

1. **Enable AWS CloudTrail** for API call auditing
2. **Implement AWS Config** for compliance monitoring
3. **Use AWS Secrets Manager** for sensitive configuration
4. **Enable VPC Flow Logs** for network monitoring
5. **Implement AWS WAF** for application protection

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name scheduled-email-reports

# Wait for deletion completion
aws cloudformation wait stack-delete-complete --stack-name scheduled-email-reports
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
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

## Support and Documentation

### AWS Service Documentation

- [AWS App Runner Developer Guide](https://docs.aws.amazon.com/apprunner/latest/dg/)
- [Amazon SES Developer Guide](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/)
- [EventBridge Scheduler User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/using-eventbridge-scheduler.html)
- [Amazon CloudWatch User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)

### Infrastructure as Code Documentation

- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/latest/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS service-specific documentation
3. Consult the original recipe documentation
4. Contact your AWS support team for service-specific issues

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment first
2. Update documentation to reflect any changes
3. Follow AWS security best practices
4. Validate code with appropriate linting tools
5. Update version numbers and changelog entries