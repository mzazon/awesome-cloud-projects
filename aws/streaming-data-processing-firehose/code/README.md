# Infrastructure as Code for Processing Streaming Data with Kinesis Data Firehose

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Processing Streaming Data with Kinesis Data Firehose".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a comprehensive real-time data processing pipeline using:

- **Kinesis Data Firehose**: Managed streaming data delivery service
- **Lambda Functions**: Data transformation and error handling
- **S3 Storage**: Durable data lake with Parquet conversion
- **OpenSearch Service**: Real-time search and analytics
- **CloudWatch**: Monitoring and alerting
- **SQS**: Dead letter queue for failed records
- **IAM Roles**: Secure cross-service permissions

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - Kinesis Data Firehose
  - Lambda
  - S3
  - OpenSearch Service
  - CloudWatch
  - SQS
  - IAM
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.5+ (for Terraform implementation)

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name kinesis-firehose-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name kinesis-firehose-pipeline \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name kinesis-firehose-pipeline \
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
cdk deploy

# View outputs
cdk output
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
cdk deploy

# View outputs
cdk output
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

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# and deploy all resources automatically
```

## Testing the Deployment

After deployment, test the pipeline with sample data:

```bash
# Get the Firehose stream name from outputs
FIREHOSE_STREAM_NAME=$(aws cloudformation describe-stacks \
    --stack-name kinesis-firehose-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`FirehoseStreamName`].OutputValue' \
    --output text)

# Send test data
echo '{"event_id":"test001","user_id":"user123","event_type":"purchase","amount":150.50}' | \
    base64 | \
    xargs -I {} aws firehose put-record \
        --delivery-stream-name $FIREHOSE_STREAM_NAME \
        --record Data={}

# Monitor delivery
aws firehose describe-delivery-stream \
    --delivery-stream-name $FIREHOSE_STREAM_NAME \
    --query 'DeliveryStreamDescription.DeliveryStreamStatus'
```

## Monitoring and Troubleshooting

### Check CloudWatch Logs

```bash
# Lambda transformation logs
aws logs describe-log-groups \
    --log-group-name-prefix /aws/lambda/

# Firehose delivery logs
aws logs describe-log-groups \
    --log-group-name-prefix /aws/kinesisfirehose/
```

### Monitor Metrics

```bash
# Check delivery metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/KinesisFirehose \
    --metric-name DeliveryToS3.Records \
    --dimensions Name=DeliveryStreamName,Value=$FIREHOSE_STREAM_NAME \
    --start-time $(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S') \
    --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
    --period 300 \
    --statistics Sum
```

### Verify Data Delivery

```bash
# Check S3 bucket contents
S3_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name kinesis-firehose-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text)

aws s3 ls s3://$S3_BUCKET/transformed-data/ --recursive

# Check OpenSearch indices
OPENSEARCH_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name kinesis-firehose-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`OpenSearchEndpoint`].OutputValue' \
    --output text)

curl -X GET "https://$OPENSEARCH_ENDPOINT/_cat/indices?v"
```

## Customization

### Environment Variables

Customize the deployment by setting these environment variables before deployment:

```bash
# Environment designation
export ENVIRONMENT=production

# Custom resource naming
export RESOURCE_PREFIX=mycompany

# Regional settings
export AWS_REGION=us-east-1

# Buffer settings for Firehose
export BUFFER_SIZE_MB=5
export BUFFER_INTERVAL_SECONDS=300

# OpenSearch configuration
export OPENSEARCH_INSTANCE_TYPE=t3.medium.search
export OPENSEARCH_INSTANCE_COUNT=2
```

### Parameter Customization

Each implementation supports customization through parameters:

#### CloudFormation Parameters

- `Environment`: Environment name (dev, staging, production)
- `BufferSizeMB`: Firehose buffer size in MB (1-128)
- `BufferIntervalSeconds`: Firehose buffer interval in seconds (60-900)
- `OpenSearchInstanceType`: OpenSearch instance type
- `EnableCompression`: Enable data compression (true/false)

#### CDK Context Values

Configure in `cdk.json`:

```json
{
  "context": {
    "environment": "dev",
    "bufferSizeMB": 5,
    "bufferIntervalSeconds": 300,
    "openSearchInstanceType": "t3.small.search",
    "enableDataTransformation": true
  }
}
```

#### Terraform Variables

Configure in `terraform.tfvars`:

```hcl
environment = "dev"
buffer_size_mb = 5
buffer_interval_seconds = 300
opensearch_instance_type = "t3.small.search"
opensearch_instance_count = 1
enable_compression = true
```

## Cost Optimization

### Estimated Monthly Costs

- **Kinesis Data Firehose**: ~$0.029 per GB ingested
- **Lambda**: ~$0.0000002 per request + compute time
- **S3 Storage**: ~$0.023 per GB stored
- **OpenSearch**: ~$0.088 per hour per t3.small.search instance
- **CloudWatch**: ~$0.50 per million API requests

### Cost Optimization Tips

1. **Adjust Buffer Settings**: Larger buffers reduce API costs but increase latency
2. **Enable Compression**: Reduces storage costs by 60-80%
3. **Use Parquet Format**: Reduces storage costs and improves query performance
4. **Monitor Dead Letter Queues**: Avoid costs from failed record processing
5. **Implement Data Lifecycle Policies**: Automatically transition older data to cheaper storage classes

## Security Considerations

### IAM Permissions

The infrastructure follows the principle of least privilege:

- Firehose service role has minimal permissions for S3, Lambda, and OpenSearch
- Lambda functions have only necessary permissions for their specific tasks
- OpenSearch domain uses fine-grained access control

### Network Security

- OpenSearch domain enforces HTTPS
- VPC deployment option available for enhanced security
- Security groups restrict access to necessary ports only

### Data Encryption

- S3 encryption at rest using AWS KMS
- Firehose encryption in transit
- OpenSearch encryption at rest and in transit

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name kinesis-firehose-pipeline

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name kinesis-firehose-pipeline \
    --query 'Stacks[0].StackStatus'
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

# Follow prompts to confirm resource deletion
```

## Common Issues and Solutions

### Issue: Firehose delivery failures

**Solution**: Check IAM permissions and destination availability

```bash
# Check delivery stream errors
aws firehose describe-delivery-stream \
    --delivery-stream-name $FIREHOSE_STREAM_NAME \
    --query 'DeliveryStreamDescription.Destinations[0].S3DestinationDescription.ProcessingConfiguration.Processors[0].Parameters'
```

### Issue: Lambda transformation timeouts

**Solution**: Increase Lambda timeout and memory allocation

```bash
# Update Lambda configuration
aws lambda update-function-configuration \
    --function-name $LAMBDA_FUNCTION_NAME \
    --timeout 300 \
    --memory-size 256
```

### Issue: OpenSearch indexing errors

**Solution**: Verify domain status and access policies

```bash
# Check OpenSearch domain status
aws opensearch describe-domain \
    --domain-name $OPENSEARCH_DOMAIN \
    --query 'DomainStatus.Processing'
```

## Performance Tuning

### Firehose Optimization

- **Buffer Size**: Larger buffers (64-128 MB) for high-throughput scenarios
- **Compression**: Enable GZIP compression for cost and performance benefits
- **Parallel Processing**: Use multiple delivery streams for higher throughput

### Lambda Optimization

- **Memory Allocation**: Increase memory for CPU-intensive transformations
- **Timeout Settings**: Set appropriate timeouts based on processing complexity
- **Concurrency**: Configure reserved concurrency for predictable performance

### OpenSearch Optimization

- **Instance Types**: Use compute-optimized instances for heavy analytics workloads
- **Shard Configuration**: Optimize shard count and size for your data patterns
- **Index Templates**: Use appropriate mappings and settings for your data structure

## Integration Examples

### API Gateway Integration

```bash
# Create API Gateway to send data to Firehose
aws apigateway create-rest-api \
    --name firehose-api \
    --description "API for sending data to Firehose"
```

### Application Integration

```python
# Python example for sending data
import boto3
import json

firehose = boto3.client('firehose')

def send_event(event_data):
    response = firehose.put_record(
        DeliveryStreamName='your-stream-name',
        Record={'Data': json.dumps(event_data)}
    )
    return response['RecordId']
```

## Support and Documentation

- [AWS Kinesis Data Firehose Documentation](https://docs.aws.amazon.com/firehose/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [Amazon OpenSearch Service Documentation](https://docs.aws.amazon.com/opensearch-service/)
- [Original Recipe Documentation](../real-time-data-processing-kinesis-data-firehose.md)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Follow AWS best practices and security guidelines
3. Update documentation for any parameter changes
4. Ensure compatibility across all implementation types