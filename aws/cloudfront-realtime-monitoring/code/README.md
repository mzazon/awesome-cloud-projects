# Infrastructure as Code for CloudFront Real-Time Monitoring and Analytics

This directory contains Infrastructure as Code (IaC) implementations for the recipe "CloudFront Real-Time Monitoring and Analytics". This solution provides comprehensive real-time visibility into user behavior, performance metrics, and security threats for global content delivery networks using CloudFront real-time logs, Kinesis data streams, Lambda processing functions, and OpenSearch for analysis and visualization.

## Solution Overview

The infrastructure deploys a complete real-time monitoring and analytics pipeline that includes:

- **CloudFront Distribution** with real-time logging configuration
- **Kinesis Data Streams** for high-throughput log ingestion and processing
- **Lambda Function** for intelligent log processing and enrichment
- **OpenSearch Service** for searchable log analytics and visualization
- **DynamoDB** for operational metrics storage
- **Kinesis Data Firehose** for automated data delivery to S3 and OpenSearch
- **CloudWatch Dashboards** for real-time monitoring and alerting
- **S3 Buckets** for content delivery and log archival
- **IAM Roles and Policies** with least privilege access

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - CloudFront distributions and real-time logs
  - Kinesis Data Streams and Data Firehose
  - Lambda functions and event source mappings
  - OpenSearch Service domains
  - DynamoDB tables
  - S3 buckets and bucket policies
  - IAM roles and policies
  - CloudWatch dashboards and metrics
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Estimated Costs

- **Development/Testing**: $50-150/month (varies by traffic volume)
- **Production**: $200-1000+/month (depends on traffic patterns and retention policies)

> **Note**: Real-time logs and OpenSearch Service can incur significant costs with high traffic volumes. Monitor usage closely and adjust retention policies as needed.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name cloudfront-realtime-monitoring \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=cf-monitoring \
        ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name cloudfront-realtime-monitoring

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name cloudfront-realtime-monitoring \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# Get stack outputs
cdk ls --long
```

### Using CDK Python

```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# Get stack outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
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
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the script prompts and monitor progress
```

## Post-Deployment Steps

### 1. Generate Test Traffic

After deployment, generate some test traffic to verify the monitoring pipeline:

```bash
# Get the CloudFront domain name from stack outputs
CF_DOMAIN_NAME="your-cloudfront-domain.cloudfront.net"

# Generate test requests
curl -I https://${CF_DOMAIN_NAME}/
curl -s https://${CF_DOMAIN_NAME}/ > /dev/null
curl -s https://${CF_DOMAIN_NAME}/css/style.css > /dev/null
curl -s https://${CF_DOMAIN_NAME}/js/app.js > /dev/null
curl -s https://${CF_DOMAIN_NAME}/api/data

# Generate some 404 errors for testing
curl -s https://${CF_DOMAIN_NAME}/nonexistent-page > /dev/null
```

### 2. Access Monitoring Dashboards

- **CloudWatch Dashboard**: Available in AWS Console under CloudWatch > Dashboards
- **OpenSearch Dashboards**: Access via the OpenSearch domain endpoint (check stack outputs)

### 3. Verify Data Flow

```bash
# Check Kinesis stream metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Kinesis \
    --metric-name IncomingRecords \
    --dimensions Name=StreamName,Value=your-stream-name \
    --start-time $(date -d '10 minutes ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Sum

# Check Lambda function logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/your-function-name \
    --start-time $(date -d '5 minutes ago' '+%s')000 \
    --filter-pattern "processedRecords"
```

## Configuration

### Environment Variables

The following environment variables can be set before deployment:

```bash
export AWS_REGION="us-east-1"                    # AWS region for deployment
export PROJECT_NAME="cf-monitoring"              # Project name prefix
export ENVIRONMENT="dev"                         # Environment (dev/staging/prod)
export OPENSEARCH_INSTANCE_TYPE="t3.small.search"  # OpenSearch instance type
export LAMBDA_MEMORY_SIZE="512"                  # Lambda memory allocation
export KINESIS_SHARD_COUNT="2"                   # Kinesis shard count
```

### Customizable Parameters

Each implementation supports the following customizable parameters:

- **ProjectName**: Prefix for all resource names
- **Environment**: Environment tag for resources
- **OpenSearchInstanceType**: Instance type for OpenSearch domain
- **OpenSearchInstanceCount**: Number of OpenSearch instances
- **LambdaMemorySize**: Memory allocation for Lambda function
- **KinesisShardCount**: Number of shards for Kinesis streams
- **S3LogRetentionDays**: Retention period for S3 logs
- **DynamoDBTTLDays**: TTL for DynamoDB metrics records

## Monitoring and Alerting

### Available Metrics

The solution provides the following custom CloudWatch metrics:

- **CloudFront/RealTime**:
  - `RequestCount`: Total number of requests
  - `BytesDownloaded`: Total bytes downloaded
  - `ErrorRate4xx`: Percentage of 4xx errors
  - `ErrorRate5xx`: Percentage of 5xx errors
  - `CacheMissRate`: Percentage of cache misses

### Setting Up Alerts

Create CloudWatch alarms for monitoring:

```bash
# High error rate alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "CloudFront-High-Error-Rate" \
    --alarm-description "Alert when error rate exceeds 5%" \
    --metric-name ErrorRate4xx \
    --namespace CloudFront/RealTime \
    --statistic Average \
    --period 300 \
    --threshold 5 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2

# Low cache hit rate alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "CloudFront-Low-Cache-Hit-Rate" \
    --alarm-description "Alert when cache miss rate exceeds 50%" \
    --metric-name CacheMissRate \
    --namespace CloudFront/RealTime \
    --statistic Average \
    --period 300 \
    --threshold 50 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 3
```

## Security Considerations

### IAM Permissions

The solution implements least privilege access with:

- CloudFront service role for real-time logs delivery to Kinesis
- Lambda execution role with minimal required permissions
- Kinesis Firehose role for S3 and OpenSearch delivery
- OpenSearch domain access policies

### Data Protection

- All data in transit is encrypted using HTTPS/TLS
- S3 buckets have encryption at rest enabled
- OpenSearch domain has encryption at rest and node-to-node encryption
- DynamoDB uses AWS managed encryption

### Network Security

- OpenSearch domain is configured with restrictive access policies
- S3 bucket policies limit access to CloudFront distributions
- Lambda functions operate within AWS's secure network environment

## Troubleshooting

### Common Issues

1. **CloudFront Distribution Deployment Takes Long**
   - CloudFront distributions can take 15-30 minutes to deploy
   - Use `aws cloudfront wait distribution-deployed` to monitor progress

2. **OpenSearch Domain Creation Slow**
   - OpenSearch domains can take 10-15 minutes to create
   - Monitor progress in AWS Console or using AWS CLI

3. **No Data in Real-time Logs**
   - Verify CloudFront distribution is receiving traffic
   - Check real-time log configuration is active
   - Ensure Kinesis stream has sufficient capacity

4. **Lambda Function Errors**
   - Check CloudWatch Logs for detailed error messages
   - Verify IAM permissions for the Lambda execution role
   - Monitor Lambda metrics for invocation errors

### Debugging Commands

```bash
# Check CloudFront distribution status
aws cloudfront get-distribution --id DISTRIBUTION_ID

# Verify Kinesis stream activity
aws kinesis describe-stream --stream-name STREAM_NAME

# Check Lambda function configuration
aws lambda get-function --function-name FUNCTION_NAME

# View OpenSearch domain status
aws opensearch describe-domain --domain-name DOMAIN_NAME
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name cloudfront-realtime-monitoring

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name cloudfront-realtime-monitoring
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy --force
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually delete resources in this order:

1. CloudFront distribution (disable first, wait for deployment, then delete)
2. Real-time log configuration
3. Lambda function and event source mappings
4. Kinesis Data Firehose delivery stream
5. Kinesis Data Streams
6. OpenSearch domain
7. DynamoDB table
8. S3 buckets (empty first)
9. IAM roles and policies
10. CloudWatch dashboards and log groups

## Performance Optimization

### Scaling Considerations

- **Kinesis Shards**: Increase shard count for higher traffic volumes
- **Lambda Memory**: Adjust memory allocation based on processing requirements
- **OpenSearch Instances**: Scale instance count and type for query performance
- **DynamoDB**: Consider provisioned capacity for predictable workloads

### Cost Optimization

- **Real-time Log Sampling**: Consider sampling for high-traffic sites
- **S3 Lifecycle Policies**: Implement archival to Glacier for old logs
- **DynamoDB TTL**: Use TTL to automatically expire old metrics
- **OpenSearch Reserved Instances**: Use reserved instances for production workloads

## Support and Documentation

- [CloudFront Real-time Logs Documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/real-time-logs.html)
- [Kinesis Data Streams Documentation](https://docs.aws.amazon.com/streams/latest/dev/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [OpenSearch Service Documentation](https://docs.aws.amazon.com/opensearch-service/)
- [Original Recipe Documentation](../cloudfront-realtime-monitoring-analytics.md)

For issues with this infrastructure code, refer to the original recipe documentation or AWS service documentation.