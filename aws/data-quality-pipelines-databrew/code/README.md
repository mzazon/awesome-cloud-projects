# Infrastructure as Code for Data Quality Pipelines with DataBrew

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Quality Pipelines with DataBrew".

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
  - Amazon EventBridge (full access)
  - Amazon S3 (full access)
  - AWS Lambda (full access)
  - IAM (role creation and policy attachment)
- Sample dataset for testing (CSV or JSON format)
- Estimated cost: $10-15 for DataBrew jobs, Lambda executions, and S3 storage during testing

## Quick Start

### Using CloudFormation

```bash
# Create the stack
aws cloudformation create-stack \
    --stack-name data-quality-pipeline-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketName,ParameterValue=my-data-quality-bucket-$(date +%s) \
                 ParameterKey=DatasetName,ParameterValue=customer-data-$(date +%s) \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name data-quality-pipeline-stack

# Check stack status
aws cloudformation describe-stacks \
    --stack-name data-quality-pipeline-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View deployed resources
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View deployed resources
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# View deployed resources
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will:
# 1. Create unique resource names
# 2. Deploy all required AWS resources
# 3. Configure data quality rules
# 4. Set up event-driven automation
# 5. Provide validation commands
```

## Architecture Overview

The deployed infrastructure includes:

- **S3 Buckets**: Raw data storage and quality report outputs
- **DataBrew Dataset**: Connection to S3 data source
- **DataBrew Ruleset**: Data quality validation rules
- **DataBrew Profile Job**: Automated quality assessment execution
- **EventBridge Rule**: Event routing for validation failures
- **Lambda Function**: Automated response to quality issues
- **IAM Roles**: Secure service-to-service permissions

## Configuration Options

### CloudFormation Parameters

- `BucketName`: S3 bucket name for data storage
- `DatasetName`: DataBrew dataset identifier
- `RulesetName`: Data quality ruleset name
- `ProfileJobName`: DataBrew profile job name
- `LambdaFunctionName`: Event processing function name

### CDK Configuration

Modify the configuration in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// CDK TypeScript example
const config = {
  bucketName: 'my-data-quality-bucket',
  datasetName: 'customer-data',
  environment: 'development'
};
```

### Terraform Variables

Configure variables in `terraform.tfvars`:

```hcl
# Terraform variables
bucket_name = "my-data-quality-bucket"
dataset_name = "customer-data"
aws_region = "us-east-1"
environment = "development"
```

## Testing the Deployment

After deployment, test the data quality pipeline:

1. **Upload sample data**:
   ```bash
   # Create test data with quality issues
   cat > test-data.csv << 'EOF'
   customer_id,name,email,age,purchase_amount
   1,John Doe,john.doe@email.com,35,299.99
   2,Jane Smith,invalid-email,28,159.50
   3,Bob Johnson,,42,
   EOF
   
   # Upload to S3 bucket
   aws s3 cp test-data.csv s3://YOUR_BUCKET_NAME/raw-data/
   ```

2. **Trigger profile job**:
   ```bash
   # Start data quality assessment
   aws databrew start-job-run --name YOUR_PROFILE_JOB_NAME
   ```

3. **Monitor results**:
   ```bash
   # Check job status
   aws databrew describe-job-run --name YOUR_PROFILE_JOB_NAME --run-id YOUR_RUN_ID
   
   # Check Lambda logs for event processing
   aws logs filter-log-events \
     --log-group-name /aws/lambda/YOUR_LAMBDA_FUNCTION_NAME \
     --start-time $(date -d '10 minutes ago' +%s)000
   ```

## Monitoring and Alerts

The deployed infrastructure includes:

- **CloudWatch Logs**: Lambda function execution logs
- **EventBridge Events**: Automated event routing for quality failures
- **DataBrew Reports**: Comprehensive quality assessment reports in S3
- **SNS Integration**: Optional email notifications for quality issues

## Security Considerations

The infrastructure implements security best practices:

- **IAM Roles**: Least privilege access for all services
- **S3 Bucket Policies**: Restricted access to data and reports
- **Lambda Permissions**: Minimal required permissions
- **EventBridge Rules**: Precise event filtering
- **Encryption**: Data encrypted at rest and in transit

## Cost Optimization

To optimize costs:

- **DataBrew Jobs**: Configure appropriate node capacity (default: 5 nodes)
- **Lambda Timeout**: Set appropriate timeout values (default: 60 seconds)
- **S3 Lifecycle**: Configure lifecycle policies for old reports
- **EventBridge**: Use precise event filtering to minimize processing

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name data-quality-pipeline-stack

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name data-quality-pipeline-stack
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

# Destroy all resources
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete all DataBrew resources
# 2. Remove EventBridge rules and Lambda functions
# 3. Clean up IAM roles and policies
# 4. Empty and delete S3 buckets
# 5. Remove local temporary files
```

## Troubleshooting

### Common Issues

1. **IAM Permission Errors**:
   - Ensure your AWS credentials have sufficient permissions
   - Check CloudTrail logs for specific permission denials

2. **DataBrew Job Failures**:
   - Verify S3 bucket permissions
   - Check data format compatibility
   - Review CloudWatch logs for detailed error messages

3. **EventBridge Not Triggering**:
   - Verify event pattern matching
   - Check Lambda function permissions
   - Review EventBridge rule configuration

4. **Lambda Function Errors**:
   - Check function logs in CloudWatch
   - Verify IAM permissions for SNS and S3 access
   - Ensure timeout values are appropriate

### Debug Commands

```bash
# Check DataBrew job status
aws databrew describe-job-run --name JOB_NAME --run-id RUN_ID

# View Lambda function logs
aws logs tail /aws/lambda/FUNCTION_NAME --follow

# Test EventBridge rule
aws events test-event-pattern \
    --event-pattern file://event-pattern.json \
    --event file://test-event.json

# Verify S3 bucket contents
aws s3 ls s3://BUCKET_NAME --recursive
```

## Customization

### Adding Custom Quality Rules

Extend the DataBrew ruleset with additional validation rules:

```json
{
  "Name": "CustomValidation",
  "CheckExpression": ":col1 matches \"^[A-Z]{2}[0-9]{4}$\"",
  "SubstitutionMap": {
    ":col1": "`product_code`"
  },
  "Threshold": {
    "Value": 95.0,
    "Type": "GREATER_THAN_OR_EQUAL",
    "Unit": "PERCENTAGE"
  }
}
```

### Extending Lambda Function

Add custom remediation logic to the Lambda function:

```python
def custom_remediation(event_details):
    """Implement custom data quality remediation logic"""
    # Add your custom remediation code here
    # Examples: data quarantine, stakeholder notification, workflow triggers
    pass
```

### Adding SNS Notifications

Configure SNS topic for email alerts:

```bash
# Create SNS topic
aws sns create-topic --name data-quality-alerts

# Subscribe to topic
aws sns subscribe \
    --topic-arn arn:aws:sns:region:account:data-quality-alerts \
    --protocol email \
    --notification-endpoint your-email@example.com
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation:
   - [AWS Glue DataBrew Documentation](https://docs.aws.amazon.com/databrew/)
   - [Amazon EventBridge Documentation](https://docs.aws.amazon.com/eventbridge/)
   - [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
3. Review CloudWatch logs for detailed error messages
4. Consult AWS support for service-specific issues

## Additional Resources

- [AWS Glue DataBrew Pricing](https://aws.amazon.com/glue/pricing/)
- [EventBridge Event Patterns](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-patterns.html)
- [Data Quality Best Practices](https://docs.aws.amazon.com/wellarchitected/latest/analytics-lens/data-quality.html)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)