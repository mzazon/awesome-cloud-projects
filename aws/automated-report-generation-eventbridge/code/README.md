# Infrastructure as Code for Automated Report Generation with EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Report Generation with EventBridge".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions for:
  - S3 bucket creation and management
  - Lambda function creation and execution
  - EventBridge Scheduler management
  - IAM role and policy creation
  - Amazon SES email configuration
- A verified email address in Amazon SES for sending reports
- Basic understanding of AWS serverless services

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions

#### CDK TypeScript
- Node.js (version 14.x or later)
- npm or yarn package manager
- AWS CDK CLI (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.7 or later
- pip package manager
- AWS CDK CLI (`pip install aws-cdk-lib`)

#### Terraform
- Terraform (version 1.0 or later)
- AWS provider for Terraform

## Architecture Overview

This solution creates an automated reporting system with the following components:

- **S3 Buckets**: Separate buckets for source data and generated reports
- **Lambda Function**: Processes data and generates business reports
- **EventBridge Scheduler**: Triggers report generation on a daily schedule
- **IAM Roles**: Secure permissions for service interactions
- **SES Integration**: Email delivery for report distribution

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name automated-reports-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=VerifiedEmailAddress,ParameterValue=your-verified-email@example.com \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name automated-reports-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name automated-reports-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Set required environment variables
export VERIFIED_EMAIL=your-verified-email@example.com

# Deploy the stack
cdk deploy --parameters verifiedEmail=${VERIFIED_EMAIL}

# View stack outputs
cdk output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Set required environment variables
export VERIFIED_EMAIL=your-verified-email@example.com

# Deploy the stack
cdk deploy --parameters verifiedEmail=${VERIFIED_EMAIL}

# View stack outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
verified_email_address = "your-verified-email@example.com"
aws_region = "us-east-1"
project_name = "automated-reports"
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
export VERIFIED_EMAIL=your-verified-email@example.com
export AWS_REGION=us-east-1

# Deploy infrastructure
./scripts/deploy.sh

# Upload sample data (included in deployment script)
# The script will automatically upload sample sales and inventory data

# Test the Lambda function
aws lambda invoke \
    --function-name $(cat .deployment-outputs | grep LAMBDA_FUNCTION | cut -d'=' -f2) \
    --payload '{}' \
    response.json && cat response.json
```

## Configuration Options

### Environment Variables

- `VERIFIED_EMAIL`: Your verified Amazon SES email address (required)
- `AWS_REGION`: AWS region for deployment (default: us-east-1)
- `PROJECT_NAME`: Prefix for resource naming (default: automated-reports)

### Customizable Parameters

#### Schedule Configuration
- **Daily Schedule**: Default is 9:00 AM UTC daily
- **Custom Schedule**: Modify the cron expression in the EventBridge schedule
- **Timezone Support**: EventBridge Scheduler supports timezone-aware scheduling

#### Report Customization
- **Data Sources**: Modify Lambda function to process different S3 data sources
- **Report Format**: Extend Lambda to generate PDF, Excel, or HTML reports
- **Email Template**: Customize email body and formatting in Lambda function

#### Storage Configuration
- **S3 Lifecycle Policies**: Configure automatic archival of old reports
- **Encryption**: Enable S3 bucket encryption for sensitive data
- **Cross-Region Replication**: Set up replication for disaster recovery

## Validation & Testing

### Verify Deployment

```bash
# Check S3 buckets
aws s3 ls | grep report

# Verify Lambda function
aws lambda get-function --function-name automated-reports-lambda

# Check EventBridge schedule
aws scheduler get-schedule --name daily-reports-schedule

# Test Lambda execution
aws lambda invoke \
    --function-name automated-reports-lambda \
    --payload '{}' \
    test-response.json

# Check generated report
aws s3 ls s3://report-output-bucket/reports/
```

### Monitor Operations

```bash
# View Lambda logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/automated-reports

# Check EventBridge schedule state
aws scheduler get-schedule --name daily-reports-schedule --query 'State'

# Monitor S3 bucket usage
aws s3api list-objects-v2 --bucket report-output-bucket --query 'Contents[].{Key:Key,Size:Size,LastModified:LastModified}'
```

## Sample Data

The deployment includes sample data for testing:

### Sales Data (`sample_sales.csv`)
```csv
Date,Product,Sales,Region
2025-01-01,Product A,1000,North
2025-01-01,Product B,1500,South
2025-01-02,Product A,1200,North
2025-01-02,Product B,800,South
```

### Inventory Data (`sample_inventory.csv`)
```csv
Product,Stock,Warehouse,Last_Updated
Product A,250,Warehouse 1,2025-01-03
Product B,180,Warehouse 1,2025-01-03
Product A,300,Warehouse 2,2025-01-03
Product B,220,Warehouse 2,2025-01-03
```

## Cost Optimization

### Estimated Monthly Costs
- **S3 Storage**: $0.023 per GB for standard storage
- **Lambda Execution**: $0.20 per 1M requests + $0.0000166667 per GB-second
- **EventBridge Scheduler**: $1.00 per million schedule evaluations
- **SES Email**: $0.10 per 1,000 emails (after free tier)

### Cost Reduction Strategies
- Use S3 Intelligent Tiering for automatic cost optimization
- Configure Lambda memory allocation based on actual usage
- Implement S3 lifecycle policies for report archival
- Use SES bulk email features for large recipient lists

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name automated-reports-stack

# Verify deletion
aws cloudformation describe-stacks --stack-name automated-reports-stack
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

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
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
# The script will remove all created resources
```

### Manual Cleanup (if needed)

```bash
# Empty S3 buckets before deletion
aws s3 rm s3://report-data-bucket --recursive
aws s3 rm s3://report-output-bucket --recursive

# Delete S3 buckets
aws s3 rb s3://report-data-bucket
aws s3 rb s3://report-output-bucket

# Remove SES verified email (optional)
aws ses delete-verified-email-address --email-address your-verified-email@example.com
```

## Troubleshooting

### Common Issues

#### Email Not Verified
**Problem**: Reports not being sent via email
**Solution**: Verify your email address in Amazon SES
```bash
aws ses verify-email-identity --email-address your-email@example.com
aws ses get-identity-verification-attributes --identities your-email@example.com
```

#### Lambda Timeout
**Problem**: Lambda function times out during report generation
**Solution**: Increase timeout and memory allocation
```bash
aws lambda update-function-configuration \
    --function-name automated-reports-lambda \
    --timeout 300 \
    --memory-size 512
```

#### S3 Access Denied
**Problem**: Lambda cannot access S3 buckets
**Solution**: Verify IAM role permissions
```bash
aws iam get-role-policy \
    --role-name ReportGeneratorRole \
    --policy-name ReportGeneratorPolicy
```

#### Schedule Not Triggering
**Problem**: EventBridge schedule not executing Lambda
**Solution**: Check schedule state and IAM permissions
```bash
aws scheduler get-schedule --name daily-reports-schedule
aws iam list-attached-role-policies --role-name EventBridgeSchedulerRole
```

### Debug Commands

```bash
# Check Lambda execution logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/automated-reports-lambda \
    --start-time $(date -d '1 hour ago' +%s)000

# Test S3 access
aws s3 ls s3://report-data-bucket --recursive

# Verify SES configuration
aws ses get-send-quota
aws ses get-send-statistics
```

## Security Considerations

### Best Practices Implemented
- **Least Privilege IAM**: Roles have minimal required permissions
- **Encryption**: S3 buckets use server-side encryption
- **VPC**: Consider deploying Lambda in VPC for additional isolation
- **Monitoring**: CloudWatch logs capture all execution details

### Additional Security Enhancements
- Enable AWS CloudTrail for API logging
- Configure S3 bucket policies for additional access control
- Use AWS KMS for custom encryption keys
- Implement resource-based policies for Lambda functions

## Customization

### Modifying Report Schedule

```bash
# Update EventBridge schedule (example: every 6 hours)
aws scheduler update-schedule \
    --name daily-reports-schedule \
    --schedule-expression "cron(0 */6 * * ? *)"
```

### Adding Data Sources

1. Upload new data files to the data bucket
2. Modify the Lambda function to process additional file types
3. Update IAM permissions if accessing external data sources

### Custom Report Formats

1. Install additional Python libraries in Lambda deployment package
2. Modify the `generate_report()` function for different output formats
3. Update email attachment handling for new file types

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check AWS service documentation for specific services
3. Review CloudWatch logs for runtime errors
4. Use AWS Support for service-specific issues

## Version Information

- **Recipe Version**: 1.0
- **Last Updated**: 2025-07-12
- **AWS Services**: EventBridge Scheduler, Lambda, S3, SES, IAM
- **Supported Regions**: All AWS regions with EventBridge Scheduler support