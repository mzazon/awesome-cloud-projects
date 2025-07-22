# Infrastructure as Code for Analyzing Time-Series Data with Timestream

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Analyzing Time-Series Data with Timestream".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys a complete time-series data solution including:

- Amazon Timestream database and table with optimized retention policies
- AWS Lambda function for data ingestion and transformation
- AWS IoT Core rule for direct sensor data routing
- IAM roles and policies with least privilege access
- CloudWatch alarms for monitoring ingestion and query performance
- Automated data lifecycle management with tiered storage

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Timestream (database and table operations)
  - AWS Lambda (function creation and execution)
  - AWS IoT Core (rule creation and management)
  - IAM (role and policy management)
  - CloudWatch (alarm creation)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Estimated cost: $50-200/month depending on data volume and query frequency

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name timestream-iot-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=iot-timeseries \
                 ParameterKey=Environment,ParameterValue=production

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name timestream-iot-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name timestream-iot-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy the stack
cdk deploy

# Get deployment outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy the stack
cdk deploy

# Get deployment outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Apply infrastructure
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Configuration

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| ProjectName | Name prefix for all resources | iot-timeseries | Yes |
| Environment | Environment name (dev/staging/prod) | production | Yes |
| MemoryStoreRetentionHours | Hours to retain data in memory store | 24 | No |
| MagneticStoreRetentionDays | Days to retain data in magnetic store | 365 | No |
| LambdaMemorySize | Memory allocation for Lambda function | 256 | No |
| LambdaTimeout | Timeout for Lambda function in seconds | 60 | No |

### CDK Configuration

Both CDK implementations support environment variables for customization:

```bash
export PROJECT_NAME="my-iot-project"
export ENVIRONMENT="production"
export MEMORY_STORE_RETENTION_HOURS="12"
export MAGNETIC_STORE_RETENTION_DAYS="1095"
```

### Terraform Variables

Customize deployment by modifying `terraform/terraform.tfvars`:

```hcl
project_name = "iot-timeseries"
environment = "production"
memory_store_retention_hours = 24
magnetic_store_retention_days = 365
lambda_memory_size = 256
lambda_timeout = 60

# Optional: Custom tags
tags = {
  Project = "IoT Analytics"
  Owner   = "DataEngineering"
  CostCenter = "Engineering"
}
```

## Testing the Deployment

### 1. Verify Infrastructure

```bash
# Check Timestream database
aws timestream-write list-databases

# Check Lambda function
aws lambda list-functions --query 'Functions[?contains(FunctionName, `timestream`)]'

# Check IoT rule
aws iot list-topic-rules --query 'Rules[?contains(RuleName, `timestream`)]'
```

### 2. Test Data Ingestion

```bash
# Get Lambda function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name timestream-iot-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Create test payload
cat > test-data.json << 'EOF'
{
    "device_id": "test-sensor-001",
    "location": "test-facility",
    "sensors": {
        "temperature": 25.5,
        "humidity": 65.2,
        "pressure": 1013.25,
        "vibration": 0.05
    }
}
EOF

# Test Lambda function
aws lambda invoke \
    --function-name "${FUNCTION_NAME}" \
    --payload file://test-data.json \
    --cli-binary-format raw-in-base64-out \
    response.json

cat response.json
```

### 3. Query Time-Series Data

```bash
# Get database name from outputs
DATABASE_NAME=$(aws cloudformation describe-stacks \
    --stack-name timestream-iot-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`DatabaseName`].OutputValue' \
    --output text)

TABLE_NAME=$(aws cloudformation describe-stacks \
    --stack-name timestream-iot-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`TableName`].OutputValue' \
    --output text)

# Query recent data
aws timestream-query query \
    --query-string "SELECT device_id, location, measure_name, measure_value::double, time FROM \"${DATABASE_NAME}\".\"${TABLE_NAME}\" WHERE time >= ago(1h) ORDER BY time DESC LIMIT 10"
```

### 4. Test IoT Integration

```bash
# Publish test message to IoT Core
aws iot-data publish \
    --topic "topic/sensors" \
    --payload '{
        "device_id": "iot-sensor-001",
        "location": "production-line-1",
        "timestamp": "2024-01-01T12:00:00Z",
        "temperature": 26.5,
        "humidity": 72.0,
        "pressure": 1012.0
    }'

# Wait and query for the data
sleep 10
aws timestream-query query \
    --query-string "SELECT * FROM \"${DATABASE_NAME}\".\"${TABLE_NAME}\" WHERE device_id = 'iot-sensor-001' ORDER BY time DESC LIMIT 5"
```

## Monitoring and Observability

### CloudWatch Dashboards

The infrastructure creates CloudWatch alarms for:

- Timestream ingestion rate monitoring
- Query latency tracking
- Lambda function error rates
- IoT rule execution metrics

### Key Metrics to Monitor

1. **Ingestion Metrics**:
   - `AWS/Timestream/SuccessfulRequestLatency`
   - `AWS/Timestream/UserErrors`
   - `AWS/Timestream/SystemErrors`

2. **Query Performance**:
   - `AWS/Timestream/QueryLatency`
   - `AWS/Timestream/QueryCount`

3. **Storage Metrics**:
   - `AWS/Timestream/MagneticStoreRejectedRecordCount`
   - `AWS/Timestream/MemoryStoreRejectedRecordCount`

### Access CloudWatch Logs

```bash
# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/timestream"

# View recent Lambda logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Cost Optimization

### Storage Optimization

The infrastructure implements automatic cost optimization through:

- **Memory Store**: 24-hour retention for fast queries (higher cost, low latency)
- **Magnetic Store**: 365-day retention for historical analysis (99% cost reduction)
- **Automatic Tiering**: Data automatically moves from memory to magnetic store

### Query Optimization Tips

1. **Use Time Filters**: Always include time range filters in queries
2. **Limit Result Sets**: Use LIMIT clauses for large datasets
3. **Leverage Interpolation**: Use Timestream's built-in time-series functions
4. **Batch Queries**: Group related queries to reduce API calls

### Monitoring Costs

```bash
# Get cost and usage for Timestream
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics UnblendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name timestream-iot-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name timestream-iot-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm cleanup
./scripts/destroy.sh --verify
```

### Manual Cleanup Verification

```bash
# Verify Timestream resources are deleted
aws timestream-write list-databases

# Verify Lambda functions are deleted
aws lambda list-functions --query 'Functions[?contains(FunctionName, `timestream`)]'

# Verify IoT rules are deleted
aws iot list-topic-rules --query 'Rules[?contains(RuleName, `timestream`)]'

# Verify CloudWatch alarms are deleted
aws cloudwatch describe-alarms --alarm-names "Timestream-IngestionRate" "Timestream-QueryLatency"
```

## Troubleshooting

### Common Issues

1. **IAM Permission Errors**:
   ```bash
   # Verify required permissions
   aws iam simulate-principal-policy \
       --policy-source-arn arn:aws:iam::ACCOUNT:user/USERNAME \
       --action-names timestream:WriteRecords timestream:DescribeEndpoints \
       --resource-arns "*"
   ```

2. **Lambda Function Timeouts**:
   - Increase timeout in configuration
   - Check CloudWatch logs for specific errors
   - Verify network connectivity to Timestream

3. **Data Ingestion Failures**:
   ```bash
   # Check Lambda function errors
   aws cloudwatch get-metric-statistics \
       --namespace "AWS/Lambda" \
       --metric-name "Errors" \
       --dimensions Name=FunctionName,Value=FUNCTION_NAME \
       --start-time $(date -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
       --end-time $(date +%Y-%m-%dT%H:%M:%S) \
       --period 300 \
       --statistics Sum
   ```

4. **IoT Rule Not Triggering**:
   - Verify topic naming matches rule SQL
   - Check IoT rule metrics in CloudWatch
   - Validate JSON message format

### Debug Mode

Enable debug logging by setting environment variables:

```bash
export DEBUG=true
export LOG_LEVEL=DEBUG

# Redeploy with debug settings
./scripts/deploy.sh
```

## Security Considerations

### IAM Best Practices

The infrastructure implements least privilege access:

- Lambda execution role has minimal Timestream permissions
- IoT Core rule has specific database/table access only
- No wildcards in resource ARNs
- Separate roles for different services

### Network Security

- VPC endpoints available for private connectivity
- Security groups restrict access to necessary ports
- IAM roles prevent cross-account access

### Data Encryption

- Timestream encrypts data at rest by default
- In-transit encryption for all API communications
- CloudWatch logs encrypted with AWS managed keys

## Extensions and Integrations

### Grafana Integration

```bash
# Install Grafana Timestream plugin
grafana-cli plugins install grafana-timestream-datasource

# Configure data source with IAM role
```

### Amazon QuickSight Integration

```bash
# Create QuickSight data source
aws quicksight create-data-source \
    --aws-account-id ACCOUNT_ID \
    --data-source-id timestream-data-source \
    --name "IoT Timestream Data" \
    --type TIMESTREAM
```

### SageMaker Integration

```python
# Query Timestream from SageMaker notebook
import boto3
import pandas as pd

client = boto3.client('timestream-query')
response = client.query(QueryString="SELECT * FROM database.table")
df = pd.DataFrame(response['Rows'])
```

## Support

- For infrastructure issues, refer to the original recipe documentation
- For AWS service-specific issues, consult AWS documentation
- For Terraform issues, refer to the AWS provider documentation
- For CDK issues, consult the AWS CDK documentation

## Contributing

When modifying this infrastructure:

1. Update all IaC implementations consistently
2. Test changes in a development environment
3. Update documentation and examples
4. Validate security best practices
5. Ensure cost optimization principles are maintained