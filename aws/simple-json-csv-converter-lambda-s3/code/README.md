# Infrastructure as Code for Simple JSON to CSV Converter with Lambda and S3

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple JSON to CSV Converter with Lambda and S3". The solution creates an automated, serverless JSON-to-CSV conversion pipeline using AWS Lambda and S3 that automatically processes JSON files uploaded to an input bucket and saves converted CSV files to an output bucket.

## Architecture Overview

The solution deploys:
- **Input S3 Bucket**: Receives JSON files for processing
- **Output S3 Bucket**: Stores converted CSV files
- **Lambda Function**: Performs JSON to CSV conversion with Python runtime
- **IAM Role**: Provides Lambda with necessary S3 permissions
- **S3 Event Notification**: Triggers Lambda function when JSON files are uploaded
- **CloudWatch Logs**: Captures function execution logs for monitoring

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- AWS account with permissions for:
  - S3 (CreateBucket, PutObject, GetObject, PutBucketNotification)
  - Lambda (CreateFunction, UpdateFunctionCode, AddPermission)
  - IAM (CreateRole, AttachRolePolicy, PutRolePolicy)
  - CloudWatch Logs (CreateLogGroup, PutLogEvents)
- Basic understanding of JSON and CSV data formats
- Python 3.12 runtime support in your target region

### Tool-Specific Prerequisites

**For CloudFormation:**
- AWS CLI version 2.0 or later

**For CDK TypeScript:**
- Node.js 18.x or later
- npm or yarn package manager
- AWS CDK CLI (`npm install -g aws-cdk`)

**For CDK Python:**
- Python 3.8 or later
- pip package manager
- AWS CDK CLI (`pip install aws-cdk-lib`)

**For Terraform:**
- Terraform 1.0 or later
- AWS provider for Terraform

**For Bash Scripts:**
- bash shell environment
- AWS CLI configured with appropriate credentials

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name json-csv-converter-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name json-csv-converter-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name json-csv-converter-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to the CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in the account/region)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk output
```

### Using CDK Python (AWS)

```bash
# Navigate to the CDK Python directory
cd cdk-python/

# Create and activate virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in the account/region)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
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

# Deploy infrastructure
./scripts/deploy.sh

# The script will output resource names and ARNs upon completion
```

## Testing the Deployment

After successful deployment, test the JSON to CSV converter:

1. **Create a sample JSON file:**

```bash
cat > sample-data.json << EOF
[
  {
    "id": 1,
    "name": "John Doe",
    "email": "john@example.com",
    "department": "Engineering"
  },
  {
    "id": 2,
    "name": "Jane Smith",
    "email": "jane@example.com",
    "department": "Marketing"
  }
]
EOF
```

2. **Upload to input bucket:**

```bash
# Replace with your actual input bucket name from stack outputs
aws s3 cp sample-data.json s3://YOUR-INPUT-BUCKET-NAME/
```

3. **Verify conversion:**

```bash
# Wait a few seconds for processing
sleep 10

# Check output bucket for CSV file
aws s3 ls s3://YOUR-OUTPUT-BUCKET-NAME/

# Download and view the converted CSV file
aws s3 cp s3://YOUR-OUTPUT-BUCKET-NAME/sample-data.csv ./
cat sample-data.csv
```

Expected output should show properly formatted CSV with headers and data rows.

## Configuration Options

### Customizable Parameters

Most implementations support these customization options:

- **Environment**: Deployment environment (dev, staging, prod)
- **Lambda Memory**: Memory allocation for Lambda function (128-10240 MB)
- **Lambda Timeout**: Function timeout in seconds (1-900 seconds)
- **S3 Bucket Names**: Custom prefixes for input and output bucket names
- **Tags**: Resource tagging for cost allocation and management

### Environment Variables

The Lambda function uses these environment variables:
- `OUTPUT_BUCKET`: Name of the S3 bucket for CSV output files
- `LOG_LEVEL`: Logging level (INFO, DEBUG, ERROR)

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor Lambda function execution:

```bash
# View recent log events
aws logs describe-log-streams \
    --log-group-name /aws/lambda/YOUR-FUNCTION-NAME \
    --order-by LastEventTime --descending

# Get specific log stream events
aws logs get-log-events \
    --log-group-name /aws/lambda/YOUR-FUNCTION-NAME \
    --log-stream-name LOG-STREAM-NAME
```

### Common Issues

1. **Permission Errors**: Ensure IAM role has correct S3 permissions
2. **Function Timeout**: Increase Lambda timeout for large files
3. **Memory Issues**: Increase Lambda memory allocation for complex JSON files
4. **S3 Event Not Triggering**: Verify S3 event notification configuration

### Performance Optimization

- **Memory Allocation**: Start with 256MB, increase based on file size
- **Timeout Settings**: Set based on expected processing time
- **Batch Processing**: Consider combining multiple small files
- **Error Handling**: Implement dead letter queues for failed processing

## Cleanup

### Using CloudFormation (AWS)

```bash
# Empty S3 buckets first (required before stack deletion)
aws s3 rm s3://YOUR-INPUT-BUCKET-NAME --recursive
aws s3 rm s3://YOUR-OUTPUT-BUCKET-NAME --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name json-csv-converter-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name json-csv-converter-stack
```

### Using CDK (AWS)

```bash
# From the respective CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Cost Considerations

### AWS Free Tier Eligible

This solution uses AWS Free Tier eligible services:
- **Lambda**: 1M free requests per month + 400,000 GB-seconds
- **S3**: 5GB free storage + 20,000 GET requests + 2,000 PUT requests
- **CloudWatch**: 10 custom metrics + 5GB log ingestion

### Estimated Costs (Beyond Free Tier)

- **Lambda**: $0.0000166667 per GB-second + $0.0000002 per request
- **S3 Storage**: $0.023 per GB per month (Standard)
- **S3 Requests**: $0.0004 per 1,000 PUT requests, $0.0004 per 10,000 GET requests
- **CloudWatch Logs**: $0.50 per GB ingested

For typical usage (100 files/month, 1MB average size): **~$0.10-$0.50/month**

## Security Best Practices

The infrastructure implements security best practices:

- **Least Privilege IAM**: Lambda role has minimal required permissions
- **Bucket Separation**: Input and output buckets prevent recursive triggers
- **Encryption**: S3 buckets use server-side encryption by default
- **VPC Integration**: Optional VPC deployment for enhanced security
- **Resource Tagging**: Consistent tagging for governance and cost allocation

## Support and Customization

### Extending the Solution

Common customizations include:
- **Multiple Input Formats**: Support XML, YAML, TSV inputs
- **Data Validation**: Add schema validation before conversion
- **Batch Processing**: Combine multiple small files
- **Error Handling**: Implement dead letter queues and SNS notifications
- **Nested JSON**: Flatten complex JSON structures

### Documentation References

- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon S3 Event Notifications](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

### Getting Help

For issues with this infrastructure code:
1. Check CloudWatch Logs for Lambda function errors
2. Verify IAM permissions and S3 bucket policies
3. Review the original recipe documentation
4. Consult AWS documentation for specific service configurations
5. Consider AWS Support for production deployments

## Version History

- **v1.0**: Initial implementation with basic JSON to CSV conversion
- **v1.1**: Added support for multiple JSON structures and improved error handling
- **v1.2**: Enhanced security with least privilege IAM policies
- **v1.3**: Added comprehensive monitoring and logging capabilities

---

*Last updated: 2025-07-12*
*Recipe version: 1.1*
*Infrastructure version: 1.3*