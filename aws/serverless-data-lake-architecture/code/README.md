# Infrastructure as Code for Implementing Advanced Serverless Data Lake Architecture with Lambda Layers, Glue, and EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Advanced Serverless Data Lake Architecture with Lambda Layers, Glue, and EventBridge".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements an enterprise-grade serverless data lake with the following components:

- **Lambda Functions**: Data ingestion, validation, and quality monitoring
- **Lambda Layers**: Shared libraries for code reusability
- **Amazon S3**: Raw, processed, and quarantine data buckets
- **AWS Glue**: Data catalog and ETL processing
- **Amazon EventBridge**: Event-driven orchestration
- **Amazon DynamoDB**: Metadata and audit trail storage
- **AWS IAM**: Security roles and policies
- **Amazon CloudWatch**: Monitoring and logging

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating:
  - Lambda functions and layers
  - S3 buckets
  - DynamoDB tables
  - AWS Glue databases and crawlers
  - EventBridge custom buses and rules
  - IAM roles and policies
  - CloudWatch logs and metrics
- For CDK implementations: Node.js 16+ or Python 3.9+
- For Terraform: Terraform 1.0+
- Estimated cost: $15-25 for 4-6 hours of testing

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name advanced-serverless-datalake \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-datalake

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name advanced-serverless-datalake \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name advanced-serverless-datalake \
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

# Deploy the stack
cdk deploy --parameters projectName=my-datalake

# View outputs
cdk outputs
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

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters projectName=my-datalake

# View outputs
cdk outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_name = "my-datalake"
aws_region   = "us-east-1"
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

# Set environment variables
export PROJECT_NAME="my-datalake"
export AWS_REGION="us-east-1"

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
aws s3 ls | grep $PROJECT_NAME
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `'$PROJECT_NAME'`)].FunctionName'
```

## Configuration Options

### Common Parameters

- **Project Name**: Unique identifier for your data lake resources
- **AWS Region**: Target AWS region for deployment
- **Lambda Memory Size**: Memory allocation for Lambda functions (default: 512MB)
- **Lambda Timeout**: Timeout for Lambda functions (default: 300 seconds)
- **Glue Crawler Schedule**: Cron expression for Glue crawler (default: every 6 hours)

### CloudFormation Parameters

```yaml
Parameters:
  ProjectName:
    Type: String
    Default: advanced-serverless-datalake
    Description: Unique name for the data lake project
  
  LambdaMemorySize:
    Type: Number
    Default: 512
    MinValue: 128
    MaxValue: 3008
    Description: Memory size for Lambda functions
```

### Terraform Variables

```hcl
variable "project_name" {
  description = "Unique name for the data lake project"
  type        = string
  default     = "advanced-serverless-datalake"
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions"
  type        = number
  default     = 512
}
```

## Testing the Deployment

### 1. Upload Test Data

```bash
# Get the raw data bucket name
RAW_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name advanced-serverless-datalake \
    --query 'Stacks[0].Outputs[?OutputKey==`RawDataBucket`].OutputValue' \
    --output text)

# Create test JSON data
cat > test-data.json << 'EOF'
{
    "id": "12345",
    "timestamp": "2024-01-15T10:30:00Z",
    "data": {
        "temperature": 23.5,
        "humidity": 65.2,
        "location": "sensor-01"
    },
    "email": "test@example.com",
    "phone": "+1-555-123-4567"
}
EOF

# Upload test file to trigger the pipeline
aws s3 cp test-data.json s3://${RAW_BUCKET}/input/test-data.json
```

### 2. Monitor Processing

```bash
# Check CloudWatch logs for Lambda functions
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/${PROJECT_NAME}"

# Check processed data
PROCESSED_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name advanced-serverless-datalake \
    --query 'Stacks[0].Outputs[?OutputKey==`ProcessedDataBucket`].OutputValue' \
    --output text)

aws s3 ls s3://${PROCESSED_BUCKET}/validated/ --recursive
```

### 3. View Quality Metrics

```bash
# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace "DataLake/Quality" \
    --metric-name "ValidationSuccessRate" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Average
```

## Monitoring and Maintenance

### CloudWatch Dashboards

The deployment creates CloudWatch dashboards for monitoring:

- **Data Lake Pipeline**: Overall pipeline health and throughput
- **Data Quality**: Validation success rates and quality scores
- **Lambda Performance**: Function duration, errors, and memory usage

### Automated Alerts

Consider setting up CloudWatch alarms for:

- Lambda function errors
- Data validation failure rates
- S3 bucket access errors
- DynamoDB throttling

### Regular Maintenance Tasks

1. **Review quarantined data** weekly for patterns
2. **Monitor costs** using AWS Cost Explorer
3. **Update Lambda layers** when dependencies change
4. **Review and rotate IAM permissions** quarterly
5. **Test disaster recovery procedures** monthly

## Cleanup

### Using CloudFormation

```bash
# Empty S3 buckets first (CloudFormation cannot delete non-empty buckets)
aws s3 rm s3://$(aws cloudformation describe-stacks \
    --stack-name advanced-serverless-datalake \
    --query 'Stacks[0].Outputs[?OutputKey==`RawDataBucket`].OutputValue' \
    --output text) --recursive

aws s3 rm s3://$(aws cloudformation describe-stacks \
    --stack-name advanced-serverless-datalake \
    --query 'Stacks[0].Outputs[?OutputKey==`ProcessedDataBucket`].OutputValue' \
    --output text) --recursive

aws s3 rm s3://$(aws cloudformation describe-stacks \
    --stack-name advanced-serverless-datalake \
    --query 'Stacks[0].Outputs[?OutputKey==`QuarantineBucket`].OutputValue' \
    --output text) --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name advanced-serverless-datalake

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name advanced-serverless-datalake
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm when prompted
```

## Troubleshooting

### Common Issues

1. **Lambda Function Timeouts**
   - Increase timeout value in configuration
   - Check CloudWatch logs for performance bottlenecks
   - Consider increasing memory allocation

2. **S3 Access Denied Errors**
   - Verify IAM permissions are correctly configured
   - Check bucket policies and CORS settings
   - Ensure Lambda execution role has required permissions

3. **EventBridge Rules Not Triggering**
   - Verify event patterns match event structure
   - Check EventBridge custom bus configuration
   - Review Lambda function permissions for EventBridge

4. **Glue Crawler Failures**
   - Check IAM role permissions for Glue service
   - Verify S3 bucket access for crawler
   - Review crawler configuration and target paths

### Debugging Commands

```bash
# Check Lambda function status
aws lambda get-function --function-name ${PROJECT_NAME}-data-ingestion

# View recent CloudWatch logs
aws logs tail /aws/lambda/${PROJECT_NAME}-data-ingestion --follow

# Check EventBridge rule status
aws events describe-rule --name ${PROJECT_NAME}-data-ingestion-rule

# Verify DynamoDB table status
aws dynamodb describe-table --table-name ${PROJECT_NAME}-metadata
```

## Security Considerations

### IAM Roles and Policies

- Lambda functions use least-privilege IAM roles
- Cross-service permissions are scoped to specific resources
- CloudWatch logging permissions are included for observability

### Data Encryption

- S3 buckets use server-side encryption (SSE-S3)
- DynamoDB tables use encryption at rest
- Lambda environment variables are encrypted

### Network Security

- Lambda functions can be deployed in VPC for additional isolation
- S3 bucket policies restrict access to specific principals
- EventBridge custom buses provide event isolation

## Cost Optimization

### Resource Sizing

- Lambda functions use ARM64 architecture for better price-performance
- DynamoDB tables use on-demand billing for variable workloads
- S3 storage classes optimize costs based on access patterns

### Monitoring Costs

- Use AWS Cost Explorer to track spending
- Set up billing alerts for unexpected cost increases
- Review and right-size resources based on actual usage

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation for specific resources
3. Consult CloudFormation/CDK/Terraform documentation for syntax issues
4. Use AWS Support for service-specific problems

## Version Information

- **Recipe Version**: 1.2
- **Generated**: 2025-07-12
- **Compatible AWS Regions**: All commercial regions
- **Minimum AWS CLI Version**: 2.0
- **Terraform Version**: >= 1.0
- **CDK Version**: >= 2.0