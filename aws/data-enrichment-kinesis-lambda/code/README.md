# Infrastructure as Code for Streaming Data Enrichment with Kinesis

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Streaming Data Enrichment with Kinesis".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a real-time data enrichment pipeline using:

- **Amazon Kinesis Data Streams**: Scalable data ingestion
- **AWS Lambda**: Serverless data processing and enrichment
- **Amazon DynamoDB**: High-performance lookup tables
- **Amazon S3**: Durable storage for enriched data
- **Amazon CloudWatch**: Monitoring and alerting

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Kinesis Data Streams
  - Lambda functions
  - DynamoDB tables
  - S3 buckets
  - IAM roles and policies
  - CloudWatch alarms
- For CDK deployments: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform CLI 1.0+

### Required IAM Permissions

Your AWS credentials should have permissions for:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kinesis:*",
                "lambda:*",
                "dynamodb:*",
                "s3:*",
                "iam:*",
                "cloudwatch:*",
                "logs:*"
            ],
            "Resource": "*"
        }
    ]
}
```

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name data-enrichment-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name data-enrichment-pipeline

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name data-enrichment-pipeline \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to TypeScript CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk ls
```

### Using CDK Python

```bash
# Navigate to Python CDK directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk ls
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

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
# The script will provide output with resource identifiers
```

## Testing the Pipeline

After deployment, test the data enrichment pipeline:

### 1. Send Test Data

```bash
# Get the Kinesis stream name from stack outputs
STREAM_NAME=$(aws cloudformation describe-stacks \
    --stack-name data-enrichment-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`StreamName`].OutputValue' \
    --output text)

# Send test clickstream event
aws kinesis put-record \
    --stream-name ${STREAM_NAME} \
    --partition-key "user123" \
    --data '{
        "event_type": "page_view",
        "user_id": "user123",
        "page": "/product/abc123",
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "session_id": "session_xyz"
    }'
```

### 2. Verify Processing

```bash
# Check Lambda function logs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name data-enrichment-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`FunctionName`].OutputValue' \
    --output text)

aws logs filter-log-events \
    --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
    --start-time $(date -d '10 minutes ago' +%s)000
```

### 3. Check Enriched Data

```bash
# List enriched data in S3
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name data-enrichment-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text)

aws s3 ls s3://${BUCKET_NAME}/enriched-data/ --recursive
```

## Configuration Options

### CloudFormation Parameters

- `Environment`: Deployment environment (dev, staging, prod)
- `StreamShardCount`: Number of Kinesis shards (default: 2)
- `LambdaMemorySize`: Lambda memory allocation (default: 256 MB)
- `LambdaTimeout`: Lambda timeout in seconds (default: 60)

### CDK Context Variables

Configure in `cdk.json`:

```json
{
    "app": "node app.js",
    "context": {
        "environment": "dev",
        "streamShardCount": 2,
        "lambdaMemorySize": 256,
        "lambdaTimeout": 60
    }
}
```

### Terraform Variables

Configure in `terraform.tfvars`:

```hcl
environment = "dev"
stream_shard_count = 2
lambda_memory_size = 256
lambda_timeout = 60
```

## Monitoring and Alerting

The deployment includes CloudWatch alarms for:

- Lambda function errors
- Kinesis stream incoming records
- DynamoDB throttling events
- S3 PUT errors

Access CloudWatch dashboard:
```bash
aws cloudwatch list-dashboards
```

## Security Considerations

This implementation follows AWS security best practices:

- IAM roles with least privilege access
- Encryption at rest for DynamoDB and S3
- Encryption in transit for all service communications
- VPC endpoints for private communication (where applicable)
- CloudTrail logging enabled for all API calls

## Cost Optimization

To optimize costs:

1. **Kinesis**: Use on-demand pricing or adjust shard count based on throughput
2. **Lambda**: Optimize memory allocation and execution time
3. **DynamoDB**: Use on-demand billing or provisioned capacity based on usage patterns
4. **S3**: Implement lifecycle policies for data archival

Estimated monthly costs for development workload:
- Kinesis Data Streams: $15-25
- Lambda: $5-10
- DynamoDB: $5-15
- S3: $1-5
- CloudWatch: $1-3

## Troubleshooting

### Common Issues

1. **Lambda function timeouts**:
   - Increase timeout value in configuration
   - Optimize function code performance
   - Check DynamoDB response times

2. **Kinesis throttling**:
   - Increase shard count
   - Implement exponential backoff in producers
   - Monitor shard utilization metrics

3. **DynamoDB throttling**:
   - Switch to on-demand billing mode
   - Increase read/write capacity units
   - Implement proper partition key distribution

### Debug Commands

```bash
# Check Kinesis stream status
aws kinesis describe-stream --stream-name ${STREAM_NAME}

# Monitor Lambda function metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Duration \
    --dimensions Name=FunctionName,Value=${FUNCTION_NAME} \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300 \
    --statistics Average,Maximum

# Check DynamoDB table status
aws dynamodb describe-table --table-name ${TABLE_NAME}
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name data-enrichment-pipeline

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name data-enrichment-pipeline
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

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Follow prompts for confirmation
```

## Customization

### Adding New Enrichment Sources

To add additional data sources for enrichment:

1. **DynamoDB**: Create additional tables in the IaC templates
2. **Lambda**: Modify the function code to query multiple sources
3. **IAM**: Update permissions to include new resources

### Scaling Considerations

For production workloads:

1. **Kinesis**: Increase shard count based on throughput requirements
2. **Lambda**: Consider provisioned concurrency for consistent performance
3. **DynamoDB**: Use Global Secondary Indexes (GSI) for complex queries
4. **S3**: Implement partitioning strategy for large datasets

### Integration with Other Services

This pipeline can be extended to integrate with:

- **Amazon OpenSearch**: For real-time search and analytics
- **Amazon Redshift**: For data warehousing and analytics
- **Amazon QuickSight**: For business intelligence dashboards
- **AWS Glue**: For ETL and data catalog management

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../data-enrichment-kinesis-lambda.md)
2. Review AWS service documentation:
   - [Kinesis Data Streams](https://docs.aws.amazon.com/kinesis/latest/dev/)
   - [Lambda](https://docs.aws.amazon.com/lambda/latest/dg/)
   - [DynamoDB](https://docs.aws.amazon.com/dynamodb/latest/developerguide/)
3. Check AWS CloudFormation/CDK/Terraform provider documentation
4. Review CloudWatch logs for detailed error information

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update documentation for any new parameters or outputs
3. Ensure security best practices are maintained
4. Update cost estimates if resource configurations change