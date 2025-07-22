# Infrastructure as Code for Data Quality Monitoring with DataBrew

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Quality Monitoring with DataBrew".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS Glue DataBrew (full access)
  - Amazon S3 (read/write access)
  - AWS CloudWatch (read/write access)
  - Amazon EventBridge (full access)
  - Amazon SNS (full access)
  - AWS IAM (role creation and policy attachment)
- Sample dataset in CSV, JSON, or Parquet format
- Estimated cost: $10-20 for profile jobs and storage during deployment

## Architecture Overview

This solution deploys:
- **S3 Bucket**: For storing raw data and DataBrew results
- **IAM Role**: Service role for DataBrew with S3 access permissions
- **DataBrew Dataset**: Connection to your data source with schema detection
- **DataBrew Ruleset**: Data quality rules for validation (completeness, format, range checks)
- **DataBrew Profile Job**: Automated data profiling and quality validation
- **SNS Topic**: For data quality alerts and notifications
- **EventBridge Rule**: Event-driven automation for quality monitoring
- **CloudWatch Integration**: For monitoring and logging

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name databrew-quality-monitoring \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DataBucketName,ParameterValue=your-unique-bucket-name \
                 ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment
aws cloudformation describe-stacks \
    --stack-name databrew-quality-monitoring \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install

# Configure your parameters
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy
cdk deploy --parameters notificationEmail=your-email@example.com
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt

# Configure your parameters
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy
cdk deploy --parameters notificationEmail=your-email@example.com
```

### Using Terraform
```bash
cd terraform/
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
data_bucket_name = "your-unique-bucket-name"
aws_region = "us-east-1"
EOF

# Plan and apply
terraform plan
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh

# Set required environment variables
export NOTIFICATION_EMAIL="your-email@example.com"
export DATA_BUCKET_NAME="your-unique-bucket-name"

# Deploy
./scripts/deploy.sh
```

## Post-Deployment Setup

### 1. Upload Sample Data
```bash
# Create sample data file
cat > customer_data.csv << 'EOF'
customer_id,name,email,age,registration_date,account_balance
1,John Smith,john.smith@example.com,25,2023-01-15,1500.00
2,Jane Doe,jane.doe@example.com,32,2023-02-20,2300.50
3,Bob Johnson,,28,2023-03-10,750.25
EOF

# Upload to S3 (replace with your actual bucket name)
aws s3 cp customer_data.csv s3://your-bucket-name/raw-data/
```

### 2. Confirm Email Subscription
Check your email for an SNS subscription confirmation and click the confirmation link.

### 3. Run Profile Job
```bash
# Get the profile job name from stack outputs
PROFILE_JOB_NAME=$(aws cloudformation describe-stacks \
    --stack-name databrew-quality-monitoring \
    --query 'Stacks[0].Outputs[?OutputKey==`ProfileJobName`].OutputValue' \
    --output text)

# Start the profile job
aws databrew start-job-run --name $PROFILE_JOB_NAME

# Monitor job status
aws databrew list-job-runs --name $PROFILE_JOB_NAME
```

## Validation

### 1. Verify Resources
```bash
# Check DataBrew resources
aws databrew list-datasets
aws databrew list-rulesets
aws databrew list-jobs

# Check S3 bucket
aws s3 ls s3://your-bucket-name/ --recursive

# Check EventBridge rules
aws events list-rules --name-prefix "DataBrewQuality"
```

### 2. Test Data Quality Monitoring
```bash
# Upload data with quality issues to trigger alerts
cat > bad_data.csv << 'EOF'
customer_id,name,email,age,registration_date,account_balance
,Jane Doe,invalid-email,150,bad-date,-1000.00
EOF

aws s3 cp bad_data.csv s3://your-bucket-name/raw-data/
aws databrew start-job-run --name $PROFILE_JOB_NAME
```

### 3. Check Results
```bash
# Download profile results
aws s3 sync s3://your-bucket-name/profile-results/ ./results/

# Check for validation reports
ls -la ./results/
```

## Cleanup

### Using CloudFormation
```bash
# Empty S3 bucket first
aws s3 rm s3://your-bucket-name --recursive

# Delete stack
aws cloudformation delete-stack --stack-name databrew-quality-monitoring

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name databrew-quality-monitoring \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
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

## Customization

### Key Configuration Options

#### CloudFormation Parameters
- `DataBucketName`: S3 bucket name for data storage
- `NotificationEmail`: Email address for quality alerts
- `Environment`: Environment tag for resources (default: dev)

#### CDK Context Variables
- `notificationEmail`: Email for SNS notifications
- `environment`: Deployment environment
- `enableEncryption`: Enable S3 bucket encryption (default: true)

#### Terraform Variables
- `notification_email`: Email address for alerts
- `data_bucket_name`: S3 bucket name
- `aws_region`: AWS region for deployment
- `environment`: Environment tag
- `enable_versioning`: Enable S3 bucket versioning

### Data Quality Rules Customization

The generated infrastructure includes these default quality rules:
- **Completeness**: customer_id column > 95% complete
- **Email Format**: Valid email format > 80% of records
- **Age Range**: Age values between 0-120
- **Balance Validation**: Account balance >= 0
- **Date Format**: Valid date format for registration_date

To customize rules, modify the ruleset configuration in your chosen IaC implementation.

### Monitoring and Alerting

The solution includes:
- **EventBridge Rule**: Captures DataBrew job completion events
- **SNS Topic**: Sends email notifications for quality failures
- **CloudWatch Logs**: Stores job execution logs
- **CloudWatch Metrics**: Tracks job performance and success rates

## Cost Optimization

### Tips for Managing Costs
- Use sampling for large datasets during development
- Schedule profile jobs during off-peak hours
- Implement lifecycle policies for S3 results storage
- Monitor CloudWatch usage and adjust log retention
- Use Spot instances for compute-intensive validation jobs

### Estimated Costs
- **DataBrew Profile Jobs**: $0.48 per job (up to 20GB)
- **S3 Storage**: $0.023 per GB per month
- **SNS Notifications**: $0.50 per million notifications
- **EventBridge**: $1.00 per million events
- **CloudWatch Logs**: $0.50 per GB ingested

## Troubleshooting

### Common Issues

1. **Profile Job Fails**
   - Check IAM role permissions
   - Verify S3 bucket access
   - Validate data format and schema

2. **No Quality Alerts**
   - Confirm SNS subscription
   - Check EventBridge rule configuration
   - Verify rule patterns match events

3. **Data Quality Rules Not Triggering**
   - Review rule expressions syntax
   - Check rule thresholds
   - Validate data against rule expectations

### Debugging Commands
```bash
# Check DataBrew job logs
aws logs filter-log-events \
    --log-group-name /aws/databrew/jobs \
    --start-time $(date -d '1 hour ago' +%s)000

# View EventBridge events
aws logs filter-log-events \
    --log-group-name /aws/events/rule/DataBrewQualityValidation \
    --start-time $(date -d '1 hour ago' +%s)000

# Check SNS topic subscriptions
aws sns list-subscriptions-by-topic \
    --topic-arn arn:aws:sns:region:account:topic-name
```

## Security Considerations

### Best Practices Implemented
- **Least Privilege IAM**: Service roles with minimal required permissions
- **Encryption**: S3 bucket encryption at rest
- **Access Logging**: CloudTrail integration for audit trails
- **Network Security**: VPC endpoints for private connectivity (optional)
- **Data Privacy**: Automatic data masking for sensitive fields

### Additional Security Enhancements
- Enable AWS Config for compliance monitoring
- Implement bucket policies for fine-grained access control
- Use AWS KMS for advanced encryption management
- Configure VPC endpoints for private API access
- Enable AWS CloudTrail for comprehensive audit logging

## Integration Examples

### With Data Pipelines
```python
# Example: Integrate with AWS Step Functions
import boto3

def trigger_quality_check(dataset_name):
    databrew = boto3.client('databrew')
    response = databrew.start_job_run(Name=f'{dataset_name}-profile-job')
    return response['RunId']
```

### With Data Catalog
```bash
# Update Glue Data Catalog with quality metrics
aws glue put-table \
    --database-name data-quality-db \
    --table-input file://table-definition.json
```

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation
2. Review AWS Glue DataBrew documentation
3. Consult AWS support for service-specific issues
4. Check CloudFormation/CDK/Terraform documentation for deployment issues

## Additional Resources

- [AWS Glue DataBrew Documentation](https://docs.aws.amazon.com/databrew/)
- [Data Quality Rules Reference](https://docs.aws.amazon.com/databrew/latest/dg/profile.data-quality-rules.html)
- [EventBridge Integration Guide](https://docs.aws.amazon.com/databrew/latest/dg/jobs.eventbridge.html)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)