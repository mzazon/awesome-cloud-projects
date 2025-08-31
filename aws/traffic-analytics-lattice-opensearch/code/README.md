# Infrastructure as Code for Traffic Analytics with VPC Lattice and OpenSearch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Traffic Analytics with VPC Lattice and OpenSearch". This solution creates a comprehensive traffic analytics platform that captures VPC Lattice access logs, processes them through Kinesis Data Firehose, transforms them via Lambda, and stores them in OpenSearch Service for real-time analytics and visualization.

## Solution Overview

The infrastructure deploys:
- **OpenSearch Service Domain**: For traffic analytics and visualization
- **Kinesis Data Firehose**: For reliable streaming data delivery
- **Lambda Function**: For real-time log transformation and enrichment
- **VPC Lattice Service Network**: For demo traffic generation
- **S3 Bucket**: For backup storage and error handling
- **IAM Roles and Policies**: For secure service integration
- **Access Log Subscription**: For automatic traffic capture

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit with TypeScript
- **CDK Python**: AWS Cloud Development Kit with Python
- **Terraform**: Multi-cloud infrastructure as code using AWS provider
- **Scripts**: Bash deployment and cleanup scripts with comprehensive error handling

## Prerequisites

### General Requirements
- AWS CLI v2 installed and configured with appropriate credentials
- An AWS account with permissions for OpenSearch, VPC Lattice, Kinesis, Lambda, S3, and IAM
- Understanding of service mesh concepts and streaming data processing
- Estimated cost: $20-40 per day for OpenSearch domain, minimal costs for other services

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2 with CloudFormation permissions
- Ability to create IAM roles and policies

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK CLI v2 (`npm install -g aws-cdk`)
- TypeScript compiler (`npm install -g typescript`)

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI v2 (`pip install aws-cdk-lib`)
- Virtual environment recommended

#### Terraform
- Terraform 1.0 or later
- AWS provider 5.0 or later

#### Bash Scripts
- Bash shell environment
- jq for JSON processing
- curl for API testing

## Quick Start

### Using CloudFormation

```bash
# Create the infrastructure stack
aws cloudformation create-stack \
    --stack-name traffic-analytics-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=OpenSearchDomainName,ParameterValue=traffic-analytics-$(date +%s)

# Monitor stack creation (takes 10-15 minutes for OpenSearch)
aws cloudformation wait stack-create-complete \
    --stack-name traffic-analytics-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name traffic-analytics-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk output
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
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

# Deploy infrastructure
./scripts/deploy.sh

# The script will output important endpoints and ARNs
```

## Post-Deployment Configuration

After deployment, follow these steps to complete the setup:

### 1. Configure OpenSearch Dashboards

```bash
# Get OpenSearch endpoint from outputs
OPENSEARCH_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name traffic-analytics-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`OpenSearchEndpoint`].OutputValue' \
    --output text)

# Access OpenSearch Dashboards
echo "OpenSearch Dashboards: https://${OPENSEARCH_ENDPOINT}/_dashboards"
```

### 2. Generate Test Traffic

```bash
# Create a simple test service target (if not exists)
echo "Configure your VPC Lattice services to generate traffic"
echo "The access logs will automatically flow to OpenSearch"
```

### 3. Create Index Patterns

In OpenSearch Dashboards:
1. Go to Management → Index Patterns
2. Create index pattern: `vpc-lattice-traffic*`
3. Select `@timestamp` as time field
4. Create visualizations and dashboards

## Validation and Testing

### Check Infrastructure Status

```bash
# Verify OpenSearch domain health
curl -X GET "https://${OPENSEARCH_ENDPOINT}/_cluster/health" | jq '.'

# Check Firehose delivery stream
aws firehose describe-delivery-stream \
    --delivery-stream-name $(aws cloudformation describe-stacks \
        --stack-name traffic-analytics-stack \
        --query 'Stacks[0].Outputs[?OutputKey==`FirehoseStreamName`].OutputValue' \
        --output text)

# Test Lambda function
aws lambda invoke \
    --function-name $(aws cloudformation describe-stacks \
        --stack-name traffic-analytics-stack \
        --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
        --output text) \
    --payload '{}' \
    response.json
```

### Send Test Data

```bash
# Send a test record to Firehose
echo '{"test_message": "VPC Lattice traffic analytics test", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", "responseCode": 200, "responseTimeMs": 150}' | \
aws firehose put-record \
    --delivery-stream-name $(aws cloudformation describe-stacks \
        --stack-name traffic-analytics-stack \
        --query 'Stacks[0].Outputs[?OutputKey==`FirehoseStreamName`].OutputValue' \
        --output text) \
    --record Data=blob://dev/stdin
```

### Query OpenSearch

```bash
# Search for test data (wait 1-2 minutes after sending)
curl -X GET "https://${OPENSEARCH_ENDPOINT}/vpc-lattice-traffic*/_search?pretty" \
    -H "Content-Type: application/json" \
    -d '{"query": {"match": {"test_message": "analytics"}}}'
```

## Monitoring and Observability

### CloudWatch Metrics

Monitor these key metrics:
- OpenSearch cluster status and performance
- Kinesis Firehose delivery success rate
- Lambda function error rate and duration
- VPC Lattice service health

### CloudWatch Logs

Check these log groups:
- `/aws/lambda/[function-name]` - Lambda execution logs
- `/aws/kinesisfirehose/[stream-name]` - Firehose delivery logs
- `/aws/opensearch/domains/[domain-name]` - OpenSearch logs

### Sample CloudWatch Dashboard

```bash
# Create a basic monitoring dashboard
aws cloudwatch put-dashboard \
    --dashboard-name "TrafficAnalyticsDashboard" \
    --dashboard-body file://dashboard-config.json
```

## Customization

### Environment Variables

Modify these parameters in your chosen IaC tool:

- `OpenSearchInstanceType`: Change OpenSearch instance size (default: t3.small.search)
- `OpenSearchInstanceCount`: Number of OpenSearch instances (default: 1)
- `FirehoseBufferSize`: Firehose buffer size in MB (default: 1)
- `FirehoseBufferInterval`: Firehose buffer interval in seconds (default: 60)
- `LambdaMemorySize`: Lambda memory allocation (default: 256MB)
- `LambdaTimeout`: Lambda timeout in seconds (default: 60)

### Security Customization

For production deployments:

1. **VPC Configuration**: Deploy OpenSearch in VPC for enhanced security
2. **Fine-grained Access Control**: Enable OpenSearch FGAC with SAML/OIDC
3. **Network Security**: Use VPC endpoints for service communication
4. **Encryption**: Ensure encryption at rest and in transit for all services

### Performance Tuning

1. **OpenSearch Sizing**: Scale based on log volume and query requirements
2. **Firehose Buffering**: Adjust buffer settings for latency vs. efficiency
3. **Lambda Concurrency**: Set reserved concurrency for predictable performance
4. **Index Lifecycle**: Implement ILM policies for cost optimization

## Cleanup

### Using CloudFormation

```bash
# Delete the stack (this will remove all resources)
aws cloudformation delete-stack --stack-name traffic-analytics-stack

# Monitor deletion progress
aws cloudformation wait stack-delete-complete \
    --stack-name traffic-analytics-stack
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy --force
```

### Using Terraform

```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm when prompted to delete resources
```

## Troubleshooting

### Common Issues

1. **OpenSearch Creation Timeout**
   - OpenSearch domains take 10-15 minutes to create
   - Check CloudFormation events for detailed status

2. **Firehose Delivery Failures**
   - Verify IAM permissions for OpenSearch and S3 access
   - Check Firehose error logs in CloudWatch

3. **Lambda Transformation Errors**
   - Review Lambda logs for JSON parsing errors
   - Verify Lambda has correct IAM permissions

4. **No Data in OpenSearch**
   - Ensure VPC Lattice access logs are configured
   - Check that services are generating traffic
   - Verify Firehose delivery stream status

### Debug Commands

```bash
# Check all resource statuses
aws cloudformation describe-stack-resources \
    --stack-name traffic-analytics-stack

# View recent CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda"

# Test Firehose connectivity
aws firehose test-delivery-stream \
    --delivery-stream-name [stream-name]
```

## Cost Optimization

### Production Considerations

1. **OpenSearch Reserved Instances**: Use RIs for predictable workloads
2. **S3 Lifecycle Policies**: Archive old backup data to cheaper storage classes
3. **Index Lifecycle Management**: Move old indices to UltraWarm storage
4. **Right-sizing**: Monitor and adjust instance types based on usage

### Estimated Costs (us-east-1)

- OpenSearch t3.small.search: ~$30/month
- Kinesis Firehose: $0.029 per GB ingested
- Lambda: $0.20 per million requests + $0.0000166667 per GB-second
- S3 Standard storage: $0.023 per GB/month
- VPC Lattice: $0.025 per million requests

## Advanced Configuration

### Multi-Region Deployment

For high availability across regions:

```bash
# Deploy in multiple regions
export AWS_REGION=us-east-1
./scripts/deploy.sh

export AWS_REGION=us-west-2
./scripts/deploy.sh
```

### Integration with Existing Infrastructure

To integrate with existing VPC Lattice networks:

1. Modify the VPC Lattice resources to reference existing networks
2. Update IAM policies for cross-account access if needed
3. Configure appropriate security groups and network ACLs

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../traffic-analytics-lattice-opensearch.md)
2. Review AWS service documentation:
   - [VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
   - [OpenSearch Service Developer Guide](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/)
   - [Kinesis Data Firehose Developer Guide](https://docs.aws.amazon.com/firehose/latest/dev/)
3. Check AWS Service Health Dashboard for service issues
4. Review CloudTrail logs for API call failures

## Contributing

To improve this infrastructure code:

1. Test changes thoroughly in a development environment
2. Update documentation to reflect any modifications
3. Ensure security best practices are maintained
4. Validate cost implications of changes