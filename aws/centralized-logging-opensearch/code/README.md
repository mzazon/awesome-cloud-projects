# Infrastructure as Code for Centralized Logging with OpenSearch Service

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Centralized Logging with OpenSearch Service".

## Overview

This solution deploys a comprehensive centralized logging architecture using Amazon OpenSearch Service as the core analytics engine, integrated with CloudWatch Logs, Lambda functions for log processing, and Kinesis Data Streams for scalable ingestion. The infrastructure automatically collects logs from multiple sources, transforms and enriches log data, and provides powerful search and visualization capabilities.

## Architecture Components

- **Amazon OpenSearch Service**: Core analytics engine with OpenSearch Dashboards
- **Amazon Kinesis Data Streams**: Real-time log data ingestion
- **AWS Lambda**: Log processing and enrichment functions
- **Amazon Kinesis Data Firehose**: Reliable delivery to OpenSearch
- **Amazon CloudWatch Logs**: Log aggregation and subscription filters
- **Amazon S3**: Backup storage for failed log deliveries
- **IAM Roles**: Secure service-to-service permissions

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- AWS CLI installed and configured with appropriate permissions
- AWS account with administrator access for initial setup
- Basic understanding of JSON log formats and OpenSearch concepts
- Estimated cost: $50-100/month for small-to-medium log volumes

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2.x or higher
- IAM permissions for CloudFormation stack operations

#### CDK TypeScript
- Node.js 18.x or higher
- AWS CDK CLI (`npm install -g aws-cdk`)
- TypeScript compiler (`npm install -g typescript`)

#### CDK Python
- Python 3.8 or higher
- AWS CDK CLI (`pip install aws-cdk-lib`)
- Virtual environment recommended

#### Terraform
- Terraform 1.0 or higher
- AWS Provider 5.x or higher

#### Bash Scripts
- Bash 4.0 or higher
- `jq` command-line JSON processor
- `aws` CLI with appropriate credentials

### Required IAM Permissions

Your AWS credentials must have permissions for:
- OpenSearch Service domain creation and management
- Kinesis streams and Firehose delivery streams
- Lambda function creation and event source mappings
- CloudWatch Logs subscription filters
- IAM role and policy management
- S3 bucket creation and management

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name centralized-logging-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=DomainName,ParameterValue=my-logging-domain \
                 ParameterKey=KinesisShardCount,ParameterValue=2

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name centralized-logging-stack \
    --query 'Stacks[0].StackStatus'

# Get OpenSearch endpoint
aws cloudformation describe-stacks \
    --stack-name centralized-logging-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`OpenSearchEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters domainName=my-logging-domain

# View outputs
cdk outputs
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters domain-name=my-logging-domain

# View outputs
cdk outputs
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan -var="domain_name=my-logging-domain"

# Deploy infrastructure
terraform apply -var="domain_name=my-logging-domain"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration
# The script will create all necessary resources and configure log forwarding
```

## Configuration Options

### Key Parameters

| Parameter | Description | Default | Valid Values |
|-----------|-------------|---------|--------------|
| DomainName | OpenSearch domain name | `central-logging-{random}` | 3-28 characters, lowercase |
| InstanceType | OpenSearch instance type | `t3.small.search` | Any valid OpenSearch instance type |
| InstanceCount | Number of data nodes | `3` | 1-80 |
| MasterInstanceType | Master node instance type | `t3.small.search` | Any valid OpenSearch instance type |
| VolumeSize | EBS volume size per node (GB) | `20` | 10-3584 |
| KinesisShardCount | Number of Kinesis shards | `2` | 1-100 |
| RetentionDays | Log retention in days | `30` | 1-3653 |

### Security Configuration

The infrastructure implements security best practices:
- Encryption at rest and in transit for OpenSearch
- TLS 1.2 minimum for all connections
- IAM-based access control with least privilege
- VPC security groups with minimal required access
- CloudTrail logging for API calls

## Post-Deployment Setup

### 1. Access OpenSearch Dashboards

```bash
# Get the OpenSearch endpoint (replace with your stack name)
OPENSEARCH_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name centralized-logging-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`OpenSearchEndpoint`].OutputValue' \
    --output text)

echo "Access OpenSearch Dashboards at: https://$OPENSEARCH_ENDPOINT/_dashboards"
```

### 2. Configure Index Patterns

1. Navigate to OpenSearch Dashboards
2. Go to Management > Index Patterns
3. Create index pattern: `logs-*`
4. Select `@timestamp` as the time field

### 3. Create Basic Visualizations

The system creates time-based indices (`logs-YYYY-MM-DD`) automatically. You can start creating dashboards immediately after log data begins flowing.

### 4. Set Up Log Sources

The infrastructure automatically configures subscription filters for existing CloudWatch Log Groups. For new log groups:

```bash
# Add subscription filter to new log group
LOG_GROUP_NAME="/aws/lambda/my-new-function"
KINESIS_STREAM_ARN=$(aws cloudformation describe-stacks \
    --stack-name centralized-logging-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`KinesisStreamArn`].OutputValue' \
    --output text)

aws logs put-subscription-filter \
    --log-group-name $LOG_GROUP_NAME \
    --filter-name "CentralLoggingFilter" \
    --filter-pattern "" \
    --destination-arn $KINESIS_STREAM_ARN \
    --role-arn $(aws cloudformation describe-stacks \
        --stack-name centralized-logging-stack \
        --query 'Stacks[0].Outputs[?OutputKey==`CloudWatchLogsRoleArn`].OutputValue' \
        --output text)
```

## Validation and Testing

### 1. Verify Infrastructure Deployment

```bash
# Check OpenSearch domain status
aws opensearch describe-domain --domain-name your-domain-name

# Check Kinesis stream status
aws kinesis describe-stream --stream-name your-stream-name

# Check Lambda function status
aws lambda get-function --function-name LogProcessor-your-suffix
```

### 2. Generate Test Logs

```bash
# Create test log group
aws logs create-log-group --log-group-name /aws/test/centralized-logging

# Generate test log entries
for i in {1..5}; do
    aws logs put-log-events \
        --log-group-name /aws/test/centralized-logging \
        --log-stream-name "test-stream-$(date +%Y-%m-%d)" \
        --log-events timestamp=$(date +%s)000,message="{\"level\":\"INFO\",\"message\":\"Test log $i\",\"service\":\"test-app\"}"
done
```

### 3. Query Logs in OpenSearch

```bash
# Search for recent logs (requires AWS CLI v2 with SigV4)
curl -X GET "https://your-opensearch-endpoint/logs-$(date +%Y.%m.%d)/_search" \
    -H "Content-Type: application/json" \
    -d '{"query":{"match_all":{}},"size":10}' \
    --aws-sigv4 "aws:amz:us-east-1:es"
```

## Monitoring and Alerting

### Key Metrics to Monitor

- **OpenSearch cluster health**: Cluster status, node count, storage utilization
- **Kinesis stream metrics**: Incoming records, processing errors, throttling
- **Lambda function metrics**: Invocations, errors, duration
- **Firehose delivery metrics**: Delivery success rate, backup object count

### Setting Up Alerts

The infrastructure includes basic CloudWatch alarms. Additional recommended alerts:

```bash
# High error rate alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "LogProcessing-HighErrorRate" \
    --alarm-description "Alert when log processing error rate is high" \
    --metric-name Errors \
    --namespace AWS/Lambda \
    --statistic Sum \
    --period 300 \
    --threshold 10 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2
```

## Troubleshooting

### Common Issues

1. **Logs not appearing in OpenSearch**
   - Check subscription filter configuration
   - Verify Lambda function execution logs
   - Check Firehose delivery stream status

2. **High costs**
   - Review OpenSearch instance sizing
   - Implement log filtering to reduce volume
   - Configure appropriate retention policies

3. **Performance issues**
   - Scale Kinesis shards based on throughput
   - Optimize Lambda function memory allocation
   - Consider OpenSearch instance upgrades

### Debug Commands

```bash
# Check Lambda function logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/LogProcessor-your-suffix \
    --start-time $(date -d '1 hour ago' +%s)000

# Check Firehose delivery errors
aws logs filter-log-events \
    --log-group-name /aws/kinesisfirehose/your-delivery-stream \
    --filter-pattern "ERROR"
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name centralized-logging-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name centralized-logging-stack \
    --query 'Stacks[0].StackStatus'
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
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually delete resources in this order:

1. CloudWatch Logs subscription filters
2. Lambda event source mappings
3. Lambda functions
4. Kinesis Data Firehose delivery stream
5. Kinesis Data Stream
6. OpenSearch Service domain
7. S3 backup bucket (after emptying)
8. IAM roles and policies

## Customization

### Modifying Log Processing

To customize log processing logic:

1. Edit the Lambda function code in your chosen IaC implementation
2. Modify the `enrich_log_event` function for custom enrichment
3. Add new parsing logic for specific log formats
4. Redeploy the infrastructure

### Adding New Log Sources

To add new AWS services as log sources:

1. Create CloudWatch Log Groups for the services
2. Add subscription filters pointing to the Kinesis stream
3. Optionally modify Lambda processing for service-specific parsing

### Scaling Configuration

For high-volume environments:

- Increase Kinesis shard count
- Scale OpenSearch cluster vertically or horizontally
- Optimize Lambda function memory and timeout
- Consider multiple delivery streams for different log types

## Cost Optimization

### Estimated Monthly Costs

| Component | Small (10GB/month) | Medium (100GB/month) | Large (1TB/month) |
|-----------|-------------------|---------------------|-------------------|
| OpenSearch Service | $30-50 | $100-150 | $500-800 |
| Kinesis Data Streams | $5-10 | $20-30 | $100-150 |
| Lambda Processing | $1-2 | $5-10 | $30-50 |
| Kinesis Data Firehose | $1-2 | $5-10 | $30-50 |
| **Total** | **$37-64** | **$130-200** | **$660-1050** |

### Cost Reduction Strategies

1. **Implement log filtering** at CloudWatch Logs level
2. **Use OpenSearch reserved instances** for predictable workloads
3. **Enable OpenSearch UltraWarm** for older data
4. **Optimize Lambda memory allocation** based on actual usage
5. **Set up log retention policies** to automatically delete old data

## Security Considerations

### Data Protection
- All data is encrypted in transit and at rest
- Access logs are generated for audit trails
- Network access is restricted to necessary protocols

### Access Control
- IAM roles follow least privilege principle
- OpenSearch access is controlled via IAM policies
- VPC security groups restrict network access

### Compliance
- Infrastructure supports GDPR data deletion requirements
- Audit trails are maintained in CloudTrail
- Data residency is controlled by AWS region selection

## Support and Resources

### Documentation Links
- [Amazon OpenSearch Service Developer Guide](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/)
- [Amazon Kinesis Data Streams Developer Guide](https://docs.aws.amazon.com/kinesis/latest/dev/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [CloudWatch Logs User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/)

### Getting Help
- For infrastructure issues, refer to the original recipe documentation
- For AWS service issues, consult the AWS documentation
- For cost optimization, use AWS Cost Explorer and Trusted Advisor

### Contributing
When modifying this infrastructure:
1. Test changes in a development environment
2. Update documentation to reflect changes
3. Follow AWS security best practices
4. Consider backward compatibility

---

*This infrastructure code was generated based on the recipe "Centralized Logging with OpenSearch Service". For the complete step-by-step implementation guide, refer to the original recipe documentation.*