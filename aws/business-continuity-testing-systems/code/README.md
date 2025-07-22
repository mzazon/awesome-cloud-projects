# Infrastructure as Code for Business Continuity Testing with Systems Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Business Continuity Testing with Systems Manager".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - IAM roles and policies
  - Systems Manager automation documents
  - Lambda functions
  - EventBridge rules
  - S3 buckets
  - CloudWatch dashboards
  - SNS topics
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Architecture Overview

This infrastructure deploys a comprehensive business continuity testing framework that includes:

- **Systems Manager Automation Documents**: For backup validation, database recovery, and application failover testing
- **Lambda Functions**: For test orchestration, compliance reporting, and manual test execution
- **EventBridge Rules**: For scheduled automated testing (daily, weekly, monthly)
- **S3 Bucket**: For storing test results and compliance reports
- **CloudWatch Dashboard**: For monitoring test execution and results
- **SNS Topic**: For notifications and alerts
- **IAM Roles**: With least privilege permissions for automation

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name bc-testing-framework \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=admin@example.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name bc-testing-framework \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name bc-testing-framework \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy BCTestingFrameworkStack \
    --parameters notificationEmail=admin@example.com

# View outputs
cdk ls
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy BCTestingFrameworkStack \
    --parameters notificationEmail=admin@example.com

# View outputs
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "admin@example.com"
project_name = "bc-testing-framework"
environment = "prod"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL="admin@example.com"
export PROJECT_NAME="bc-testing-framework"
export AWS_REGION="us-east-1"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name bc-testing-framework
```

## Configuration

### Common Parameters

All implementations support these configuration parameters:

- **Notification Email**: Email address for BC testing alerts and reports
- **Project Name**: Name prefix for all resources (default: bc-testing-framework)
- **Environment**: Environment tag for resources (dev/staging/prod)
- **Testing Schedules**: Cron expressions for automated testing
  - Daily: `rate(1 day)`
  - Weekly: `cron(0 2 ? * SUN *)`
  - Monthly: `cron(0 1 1 * ? *)`

### Environment Variables (Bash Scripts)

```bash
export NOTIFICATION_EMAIL="your-email@example.com"    # Required
export PROJECT_NAME="bc-testing-framework"           # Optional
export AWS_REGION="us-east-1"                        # Optional
export ENVIRONMENT="prod"                            # Optional
export DAILY_TEST_SCHEDULE="rate(1 day)"             # Optional
export WEEKLY_TEST_SCHEDULE="cron(0 2 ? * SUN *)"    # Optional
export MONTHLY_TEST_SCHEDULE="cron(0 1 1 * ? *)"     # Optional
```

## Deployed Resources

### Core Infrastructure

1. **IAM Role**: `BCTestingRole-{random-id}` - Execution role for automation
2. **S3 Bucket**: `bc-testing-results-{random-id}` - Test results storage
3. **SNS Topic**: `bc-alerts-{random-id}` - Notifications

### Systems Manager Automation Documents

1. **BC-BackupValidation**: Validates backup integrity and restore capabilities
2. **BC-DatabaseRecovery**: Tests database backup and recovery procedures
3. **BC-ApplicationFailover**: Tests application failover to secondary region

### Lambda Functions

1. **bc-test-orchestrator**: Coordinates test execution based on schedules
2. **bc-compliance-reporter**: Generates monthly compliance reports
3. **bc-manual-test-executor**: Enables on-demand test execution

### EventBridge Rules

1. **bc-daily-tests**: Triggers daily basic tests
2. **bc-weekly-tests**: Triggers weekly comprehensive tests
3. **bc-monthly-tests**: Triggers monthly full DR tests
4. **bc-compliance-reporting**: Triggers monthly compliance reporting

### Monitoring

1. **CloudWatch Dashboard**: BC-Testing-{project-id} - Centralized monitoring
2. **CloudWatch Log Groups**: For Lambda function logs
3. **CloudWatch Alarms**: For critical test failures (optional)

## Usage

### Manual Test Execution

Execute tests manually using the deployed Lambda function:

```bash
# Execute backup validation only
aws lambda invoke \
    --function-name bc-manual-test-executor-{project-id} \
    --payload '{"testType":"manual","components":["backup"]}' \
    result.json

# Execute comprehensive test
aws lambda invoke \
    --function-name bc-manual-test-executor-{project-id} \
    --payload '{"testType":"comprehensive","components":["backup","database","application"]}' \
    result.json
```

### Monitoring Test Results

1. **CloudWatch Dashboard**: View real-time metrics and logs
2. **S3 Bucket**: Access detailed test results and compliance reports
3. **SNS Notifications**: Receive email alerts for test completion/failures

### Accessing Test Results

```bash
# List test results
aws s3 ls s3://bc-testing-results-{project-id}/test-results/ --recursive

# Download specific test result
aws s3 cp s3://bc-testing-results-{project-id}/test-results/daily/{test-id}/results.json ./

# List compliance reports
aws s3 ls s3://bc-testing-results-{project-id}/compliance-reports/ --recursive
```

## Customization

### Testing Schedules

Modify the EventBridge rule schedules in your IaC implementation:

- **Daily Tests**: Basic backup validation
- **Weekly Tests**: Backup + database recovery validation
- **Monthly Tests**: Comprehensive testing including application failover

### Test Components

Customize which components are tested by modifying the Lambda function environment variables:

- `TEST_INSTANCE_ID`: EC2 instance for backup testing
- `DB_INSTANCE_ID`: RDS instance for database testing
- `PRIMARY_ALB_ARN`: Primary load balancer for failover testing
- `SECONDARY_ALB_ARN`: Secondary load balancer for failover testing
- `HOSTED_ZONE_ID`: Route 53 hosted zone for DNS failover
- `DOMAIN_NAME`: Domain name for application testing

### Notification Configuration

Update the SNS topic subscription to use your email address or integrate with other notification systems (Slack, Microsoft Teams, etc.).

## Security Considerations

- IAM roles follow least privilege principle
- S3 bucket has versioning and lifecycle policies enabled
- Lambda functions use encrypted environment variables for sensitive data
- Systems Manager automation documents include security validations
- All resources are tagged for governance and cost allocation

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure AWS CLI has sufficient permissions for all services
2. **Resource Name Conflicts**: Use unique project names or adjust random ID generation
3. **Schedule Expression Errors**: Validate cron expressions before deployment
4. **Lambda Timeout Issues**: Increase timeout values for complex test scenarios

### Debug Commands

```bash
# Check automation document status
aws ssm describe-document --name BC-BackupValidation-{project-id}

# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/bc-

# Check EventBridge rule status
aws events list-rules --name-prefix bc-

# Verify S3 bucket configuration
aws s3api get-bucket-versioning --bucket bc-testing-results-{project-id}
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name bc-testing-framework

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name bc-testing-framework \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to CDK directory (TypeScript or Python)
cd cdk-typescript/  # or cd cdk-python/

# Destroy the stack
cdk destroy BCTestingFrameworkStack

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Execute cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup

If automated cleanup fails, manually remove resources:

```bash
# Delete S3 bucket contents first
aws s3 rm s3://bc-testing-results-{project-id} --recursive

# Then delete other resources
aws sns delete-topic --topic-arn {sns-topic-arn}
aws cloudwatch delete-dashboards --dashboard-names BC-Testing-{project-id}
```

## Cost Estimation

Monthly cost breakdown (US East region):

- **Lambda Executions**: $5-15 (depending on test frequency)
- **S3 Storage**: $1-5 (test results and reports)
- **CloudWatch**: $5-10 (dashboard and logs)
- **Systems Manager**: $0 (automation executions included)
- **EventBridge**: $1 (rule executions)
- **SNS**: $1 (notifications)

**Total Estimated Monthly Cost**: $13-32

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS service documentation for specific resources
3. Verify IAM permissions and resource limits
4. Check CloudWatch logs for detailed error messages

## Contributing

When modifying this infrastructure code:

1. Follow AWS best practices for security and cost optimization
2. Update documentation for any configuration changes
3. Test changes in a non-production environment
4. Validate all IaC implementations work consistently

## License

This infrastructure code is provided as-is for educational and reference purposes. Ensure compliance with your organization's policies and AWS best practices before production deployment.