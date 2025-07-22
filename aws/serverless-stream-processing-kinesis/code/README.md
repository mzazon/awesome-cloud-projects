# Infrastructure as Code for Processing Serverless Streams with Kinesis and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Processing Serverless Streams with Kinesis and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a serverless real-time data processing pipeline that includes:

- Amazon Kinesis Data Stream with multiple shards for high-throughput data ingestion
- AWS Lambda function for real-time data processing
- IAM roles with least-privilege permissions
- S3 bucket for storing processed data
- CloudWatch integration for monitoring and logging
- Event source mapping for automatic Lambda triggering

## Prerequisites

### General Requirements
- AWS CLI v2 installed and configured with appropriate permissions
- AWS account with permissions for:
  - Amazon Kinesis (CreateStream, DescribeStream, PutRecord, GetRecords)
  - AWS Lambda (CreateFunction, InvokeFunction, CreateEventSourceMapping)
  - IAM (CreateRole, AttachRolePolicy, PassRole)
  - Amazon S3 (CreateBucket, PutObject, GetObject)
  - Amazon CloudWatch (CreateLogGroup, PutLogEvents)

### Tool-Specific Prerequisites

#### CloudFormation
- No additional tools required (uses AWS CLI)

#### CDK TypeScript
- Node.js 16.x or later
- AWS CDK CLI: `npm install -g aws-cdk`
- TypeScript: `npm install -g typescript`

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI: `npm install -g aws-cdk`
- pip for dependency management

#### Terraform
- Terraform >= 1.0
- AWS provider >= 4.0

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name kinesis-lambda-processing \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=StreamName,ParameterValue=realtime-data-stream \
                 ParameterKey=LambdaFunctionName,ParameterValue=kinesis-data-processor \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name kinesis-lambda-processing

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name kinesis-lambda-processing \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for configuration values and deploy all resources
```

## Testing the Pipeline

After deployment, you can test the real-time processing pipeline:

### 1. Send Test Data
```bash
# Install Python dependencies for testing
pip install boto3

# Create a simple test data generator
cat > test_data_generator.py << 'EOF'
import boto3
import json
import time
import random
from datetime import datetime

def send_test_data(stream_name, num_records=10):
    kinesis = boto3.client('kinesis')
    
    for i in range(num_records):
        test_data = {
            "device_id": f"device_{random.randint(1, 100)}",
            "temperature": round(random.uniform(18.0, 35.0), 2),
            "humidity": round(random.uniform(30.0, 80.0), 2),
            "timestamp": datetime.utcnow().isoformat(),
            "battery_level": random.randint(10, 100)
        }
        
        kinesis.put_record(
            StreamName=stream_name,
            Data=json.dumps(test_data),
            PartitionKey=test_data['device_id']
        )
        
        print(f"Sent record {i+1}: {test_data['device_id']}")
        time.sleep(0.5)

if __name__ == "__main__":
    send_test_data("realtime-data-stream")  # Use your stream name
EOF

# Run the test
python test_data_generator.py
```

### 2. Verify Processing
```bash
# Check Lambda function logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/kinesis-data-processor" \
    --start-time $(date -d '10 minutes ago' +%s)000

# List processed files in S3
aws s3 ls s3://YOUR_BUCKET_NAME/processed-data/ --recursive

# Download and view a processed file
aws s3 cp s3://YOUR_BUCKET_NAME/processed-data/ . --recursive --include "*.json"
```

## Monitoring and Observability

### CloudWatch Metrics
Monitor key metrics for your pipeline:

```bash
# Lambda function metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=kinesis-data-processor \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Sum

# Kinesis stream metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Kinesis \
    --metric-name IncomingRecords \
    --dimensions Name=StreamName,Value=realtime-data-stream \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Sum
```

### Setting Up Alarms
```bash
# Create alarm for Lambda errors
aws cloudwatch put-metric-alarm \
    --alarm-name "Lambda-Processing-Errors" \
    --alarm-description "Alarm for Lambda function errors" \
    --metric-name Errors \
    --namespace AWS/Lambda \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --dimensions Name=FunctionName,Value=kinesis-data-processor
```

## Customization

### Configuration Parameters

Each implementation supports customization through variables/parameters:

#### Common Configuration Options
- **Stream Name**: Kinesis stream identifier
- **Shard Count**: Number of shards for parallel processing (affects throughput)
- **Lambda Memory**: Memory allocation for Lambda function (128MB - 10GB)
- **Lambda Timeout**: Maximum execution time (up to 15 minutes)
- **Batch Size**: Number of records per Lambda invocation (1-10,000)
- **S3 Bucket Name**: Destination for processed data
- **Environment**: Deployment environment (dev, staging, prod)

#### CloudFormation Parameters
Edit the `Parameters` section in `cloudformation.yaml`:
```yaml
Parameters:
  StreamShardCount:
    Type: Number
    Default: 3
    MinValue: 1
    MaxValue: 1000
    Description: Number of shards for the Kinesis stream
```

#### CDK Configuration
Edit the configuration in the CDK app files:
```typescript
// cdk-typescript/app.ts
const config = {
  streamShardCount: 3,
  lambdaMemory: 256,
  lambdaTimeout: Duration.seconds(60),
  batchSize: 100
};
```

#### Terraform Variables
Edit `terraform/variables.tf` or create `terraform.tfvars`:
```hcl
stream_shard_count = 3
lambda_memory_size = 256
lambda_timeout = 60
batch_size = 100
```

### Advanced Configuration

#### Enhanced Error Handling
Add dead letter queue support:
```bash
# Create DLQ (add to your IaC)
aws sqs create-queue --queue-name kinesis-processing-dlq

# Update Lambda configuration to use DLQ
aws lambda update-function-configuration \
    --function-name kinesis-data-processor \
    --dead-letter-config TargetArn=arn:aws:sqs:region:account:kinesis-processing-dlq
```

#### Performance Optimization
- **Increase Lambda concurrency**: Set reserved concurrency based on shard count
- **Optimize batch size**: Balance latency vs. throughput requirements
- **Enable Enhanced Fan-Out**: For multiple consumers requiring dedicated throughput
- **Implement data compression**: Reduce network overhead for large records

## Cost Optimization

### Resource Costs
- **Kinesis Data Streams**: $0.015 per shard hour + $0.014 per 1M PUT payload units
- **Lambda**: $0.0000166667 per GB-second + $0.20 per 1M requests
- **S3**: $0.023 per GB stored (Standard class)
- **CloudWatch**: Logs and metrics charges apply

### Cost Reduction Tips
1. **Right-size Lambda memory**: Start with 256MB and adjust based on performance metrics
2. **Optimize shard count**: Monitor utilization and scale based on actual throughput
3. **Implement data retention**: Set appropriate S3 lifecycle policies
4. **Use S3 storage classes**: Archive old processed data to cheaper storage tiers

## Cleanup

### Using CloudFormation
```bash
# Delete the stack (this removes all resources)
aws cloudformation delete-stack --stack-name kinesis-lambda-processing

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name kinesis-lambda-processing
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification
Verify all resources are deleted:
```bash
# Check for remaining Kinesis streams
aws kinesis list-streams

# Check for Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `kinesis`)]'

# Check for S3 buckets
aws s3 ls | grep processed-data

# Check for IAM roles
aws iam list-roles --query 'Roles[?contains(RoleName, `kinesis`)]'
```

## Troubleshooting

### Common Issues

#### Lambda Function Not Triggering
1. Check event source mapping status:
```bash
aws lambda list-event-source-mappings \
    --function-name kinesis-data-processor
```

2. Verify IAM permissions for Lambda execution role
3. Check Kinesis stream is ACTIVE and receiving data

#### Processing Errors
1. Check Lambda function logs:
```bash
aws logs filter-log-events \
    --log-group-name "/aws/lambda/kinesis-data-processor" \
    --start-time $(date -d '1 hour ago' +%s)000
```

2. Monitor CloudWatch metrics for error rates
3. Verify S3 bucket permissions and policies

#### Performance Issues
1. Monitor Lambda duration and memory usage
2. Check Kinesis iterator age metrics
3. Consider increasing Lambda memory or timeout
4. Optimize batch size and batching window

### Support Resources
- [AWS Kinesis Documentation](https://docs.aws.amazon.com/kinesis/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest)

## Support

For issues with this infrastructure code, refer to:
1. The original recipe documentation
2. AWS service documentation
3. Provider-specific documentation (CloudFormation, CDK, Terraform)
4. AWS Support (for account-specific issues)

---

**Note**: This infrastructure code implements the complete solution described in the recipe "Processing Serverless Streams with Kinesis and Lambda". For detailed explanation of the architecture and business use case, refer to the original recipe documentation.