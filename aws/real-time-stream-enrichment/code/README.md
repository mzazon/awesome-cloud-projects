# Infrastructure as Code for Real-Time Stream Enrichment with Kinesis and EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Stream Enrichment with Kinesis and EventBridge".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates a serverless real-time data enrichment pipeline that:

- Ingests streaming data via Kinesis Data Firehose
- Processes events through Kinesis Data Streams
- Enriches data using Lambda functions with DynamoDB lookups
- Orchestrates the pipeline with EventBridge Pipes
- Stores enriched data in S3 with automatic partitioning

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Kinesis Data Streams and Firehose
  - EventBridge Pipes
  - Lambda functions
  - DynamoDB tables
  - S3 buckets
  - IAM roles and policies
- Node.js 18+ (for CDK TypeScript)
- Python 3.11+ (for CDK Python)
- Terraform 1.5+ (for Terraform implementation)
- Estimated cost: $10-15 for 2 hours of testing

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name stream-enrichment-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=RandomSuffix,ParameterValue=$(date +%s)

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name stream-enrichment-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name stream-enrichment-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply -auto-approve

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
echo "Deployment completed. Check AWS Console for resource status."
```

## Testing the Pipeline

After deployment, test the enrichment pipeline:

```bash
# Set variables (adjust based on your deployment)
export STREAM_NAME="raw-events-$(date +%s)"
export TABLE_NAME="reference-data-$(date +%s)"

# Add test data to DynamoDB
aws dynamodb put-item \
    --table-name ${TABLE_NAME} \
    --item '{
        "productId": {"S": "PROD-001"},
        "productName": {"S": "Smart Sensor"},
        "category": {"S": "IoT Devices"},
        "price": {"N": "49.99"}
    }'

# Send test event to Kinesis
aws kinesis put-record \
    --stream-name ${STREAM_NAME} \
    --data $(echo '{"eventId":"test-001","productId":"PROD-001","quantity":5}' | base64) \
    --partition-key "PROD-001"

# Monitor Lambda logs
aws logs tail /aws/lambda/enrich-events-* --follow --since 5m
```

## Monitoring and Troubleshooting

### CloudWatch Metrics

Monitor key metrics:

```bash
# Lambda invocations
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=enrich-events-* \
    --statistics Sum \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300

# Kinesis incoming records
aws cloudwatch get-metric-statistics \
    --namespace AWS/Kinesis \
    --metric-name IncomingRecords \
    --dimensions Name=StreamName,Value=raw-events-* \
    --statistics Sum \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300
```

### Common Issues

1. **EventBridge Pipes not processing events**:
   - Check IAM permissions for the Pipes execution role
   - Verify Kinesis stream is active and receiving data
   - Review CloudWatch logs for error messages

2. **Lambda enrichment failures**:
   - Check Lambda function logs in CloudWatch
   - Verify DynamoDB table permissions
   - Ensure reference data exists in DynamoDB

3. **Data not appearing in S3**:
   - Check Firehose delivery stream status
   - Verify S3 bucket permissions
   - Review Firehose error logs

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name stream-enrichment-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name stream-enrichment-stack
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy --force

# Clean up CDK assets (optional)
cdk bootstrap --show-template > /dev/null
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -auto-approve

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Confirm all resources are deleted
echo "Cleanup completed. Verify in AWS Console that all resources are removed."
```

## Customization

### Key Parameters

Each implementation supports customization through variables:

- **Region**: AWS region for deployment
- **Environment**: Environment tag (dev, staging, prod)
- **Retention**: Data retention periods for logs and streams
- **Capacity**: DynamoDB table capacity settings
- **Buffer**: Firehose buffering configuration

### CloudFormation Parameters

```yaml
Parameters:
  Environment:
    Type: String
    Default: dev
  RandomSuffix:
    Type: String
    Description: Unique suffix for resource names
```

### CDK Context Variables

```json
{
  "environment": "dev",
  "retentionDays": 7,
  "bufferSizeMB": 5,
  "bufferIntervalSeconds": 300
}
```

### Terraform Variables

```hcl
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 7
}
```

## Security Considerations

This implementation follows AWS security best practices:

- **Least Privilege**: IAM roles have minimal required permissions
- **Encryption**: Data encrypted at rest and in transit
- **Network Security**: Resources deployed in appropriate subnets
- **Monitoring**: CloudWatch logs enabled for all services
- **Access Control**: Resource-based policies restrict access

## Cost Optimization

To minimize costs:

- Use Kinesis Data Streams on-demand mode
- Configure appropriate Firehose buffer settings
- Set DynamoDB to on-demand billing
- Enable S3 Intelligent Tiering for long-term storage
- Monitor CloudWatch metrics to right-size resources

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation
3. Verify IAM permissions and resource configurations
4. Monitor CloudWatch logs for error details
5. Consult AWS support for service-specific issues

## Additional Resources

- [AWS Kinesis Data Streams Developer Guide](https://docs.aws.amazon.com/kinesis/latest/dev/)
- [EventBridge Pipes User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-pipes.html)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/)