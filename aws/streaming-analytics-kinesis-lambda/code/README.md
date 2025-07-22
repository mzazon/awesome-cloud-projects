# Infrastructure as Code for Streaming Analytics with Kinesis and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Streaming Analytics with Kinesis and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a serverless real-time analytics pipeline consisting of:

- **Amazon Kinesis Data Streams**: For data ingestion and streaming
- **AWS Lambda**: For serverless stream processing
- **Amazon DynamoDB**: For storing processed analytics results
- **IAM Roles and Policies**: For secure service-to-service communication
- **CloudWatch Alarms**: For monitoring and alerting

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- Administrator access or permissions for:
  - Kinesis Data Streams
  - Lambda functions
  - DynamoDB tables
  - IAM roles and policies
  - CloudWatch alarms
- For CDK implementations: Node.js 14+ and AWS CDK CLI installed
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $5-15 for full deployment depending on data volume

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name serverless-analytics-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=StreamName,ParameterValue=real-time-analytics-stream \
                 ParameterKey=LambdaFunctionName,ParameterValue=kinesis-stream-processor \
                 ParameterKey=DynamoDBTableName,ParameterValue=analytics-results

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name serverless-analytics-pipeline

# View stack outputs
aws cloudformation describe-stacks \
    --stack-name serverless-analytics-pipeline \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
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

# The script will create all resources and display important ARNs and endpoints
```

## Testing the Pipeline

After deployment, you can test the pipeline using the provided test data producer:

```bash
# Create a test data producer (this creates the same producer from the recipe)
cat << 'EOF' > test_producer.py
import boto3
import json
import time
import random
from datetime import datetime

kinesis = boto3.client('kinesis')

def generate_sample_events():
    event_types = ['page_view', 'purchase', 'user_signup', 'click']
    device_types = ['desktop', 'mobile', 'tablet']
    
    events = []
    
    for i in range(10):
        event = {
            'eventType': random.choice(event_types),
            'userId': f'user_{random.randint(1000, 9999)}',
            'sessionId': f'session_{random.randint(100000, 999999)}',
            'deviceType': random.choice(device_types),
            'timestamp': datetime.now().isoformat(),
            'location': {
                'country': random.choice(['US', 'UK', 'DE', 'FR', 'JP']),
                'city': random.choice(['New York', 'London', 'Berlin', 'Paris', 'Tokyo'])
            }
        }
        
        if event['eventType'] == 'page_view':
            event.update({
                'pageUrl': f'/page/{random.randint(1, 100)}',
                'loadTime': random.randint(500, 3000),
                'sessionLength': random.randint(10, 1800),
                'pagesViewed': random.randint(1, 10)
            })
        elif event['eventType'] == 'purchase':
            event.update({
                'amount': round(random.uniform(10.99, 299.99), 2),
                'currency': 'USD',
                'itemsCount': random.randint(1, 5)
            })
        elif event['eventType'] == 'user_signup':
            event.update({
                'signupMethod': random.choice(['email', 'social', 'phone']),
                'campaignSource': random.choice(['google', 'facebook', 'direct', 'email'])
            })
        
        events.append(event)
    
    return events

def send_events_to_kinesis(stream_name, events):
    for event in events:
        try:
            response = kinesis.put_record(
                StreamName=stream_name,
                Data=json.dumps(event),
                PartitionKey=event['userId']
            )
            print(f"Sent event {event['eventType']} - Shard: {response['ShardId']}")
            time.sleep(0.1)
            
        except Exception as e:
            print(f"Error sending event: {str(e)}")

if __name__ == "__main__":
    stream_name = "real-time-analytics-stream"
    
    print("Generating and sending sample events...")
    
    for batch in range(3):
        print(f"\nSending batch {batch + 1}...")
        events = generate_sample_events()
        send_events_to_kinesis(stream_name, events)
        time.sleep(2)
    
    print("\nCompleted sending test events!")
EOF

# Install boto3 and run the producer
pip3 install boto3
python3 test_producer.py
```

## Monitoring and Validation

### Check Lambda Function Logs

```bash
# View recent Lambda function logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/kinesis-stream-processor" \
    --start-time $(date -d '10 minutes ago' +%s)000
```

### Query DynamoDB Results

```bash
# Scan the analytics results table
aws dynamodb scan \
    --table-name analytics-results \
    --max-items 5

# Query for specific event types
aws dynamodb scan \
    --table-name analytics-results \
    --filter-expression "eventType = :et" \
    --expression-attribute-values '{":et":{"S":"page_view"}}' \
    --max-items 3
```

### Check CloudWatch Metrics

```bash
# View custom analytics metrics
aws cloudwatch get-metric-statistics \
    --namespace RealTimeAnalytics \
    --metric-name EventsProcessed \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum

# Check Lambda invocation metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=kinesis-stream-processor \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name serverless-analytics-pipeline

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name serverless-analytics-pipeline
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Confirm when prompted for destructive actions
```

## Customization

### Environment Variables

You can customize the deployment by modifying the following parameters:

- **KINESIS_STREAM_NAME**: Name for the Kinesis Data Stream (default: "real-time-analytics-stream")
- **LAMBDA_FUNCTION_NAME**: Name for the Lambda function (default: "kinesis-stream-processor")
- **DYNAMODB_TABLE_NAME**: Name for the DynamoDB table (default: "analytics-results")
- **LAMBDA_MEMORY_SIZE**: Memory allocation for Lambda function (default: 512 MB)
- **LAMBDA_TIMEOUT**: Timeout for Lambda function (default: 300 seconds)
- **KINESIS_SHARD_COUNT**: Number of shards for Kinesis stream (default: 2)

### Terraform Variables

The Terraform implementation includes a `variables.tf` file with configurable parameters:

```bash
cd terraform/

# Create terraform.tfvars file for customization
cat << EOF > terraform.tfvars
kinesis_stream_name = "my-analytics-stream"
lambda_function_name = "my-stream-processor"
dynamodb_table_name = "my-analytics-results"
lambda_memory_size = 1024
lambda_timeout = 600
kinesis_shard_count = 4
EOF

# Apply with custom variables
terraform apply
```

### CloudFormation Parameters

For CloudFormation, modify parameters during stack creation:

```bash
aws cloudformation create-stack \
    --stack-name my-analytics-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=StreamName,ParameterValue=my-custom-stream \
                 ParameterKey=LambdaMemorySize,ParameterValue=1024 \
                 ParameterKey=KinesisShardCount,ParameterValue=4
```

## Troubleshooting

### Common Issues

1. **Lambda Function Errors**: Check CloudWatch Logs for detailed error messages
2. **DynamoDB Throttling**: Increase write capacity or check for hot partitions
3. **Kinesis Shard Limits**: Monitor shard utilization and scale as needed
4. **IAM Permission Issues**: Verify Lambda execution role has necessary permissions

### Performance Optimization

- **Increase Lambda Memory**: For higher throughput processing
- **Adjust Batch Size**: Balance between latency and cost efficiency
- **Scale Kinesis Shards**: Add shards for higher ingestion rates
- **DynamoDB Scaling**: Configure auto-scaling for variable workloads

## Security Considerations

This implementation follows AWS security best practices:

- **Least Privilege IAM**: Lambda functions have minimal required permissions
- **Encryption**: Data encrypted in transit and at rest where applicable
- **VPC Isolation**: Can be deployed within VPC for additional security
- **CloudWatch Monitoring**: Comprehensive logging and monitoring enabled

## Cost Optimization

- **Lambda**: Pay-per-invocation pricing with automatic scaling
- **DynamoDB**: On-demand billing mode for variable workloads
- **Kinesis**: Pay for provisioned shards and data retention
- **CloudWatch**: Standard monitoring included, custom metrics incur charges

## Support

For issues with this infrastructure code, refer to:

- Original recipe documentation: `../serverless-realtime-analytics-kinesis-lambda.md`
- AWS Lambda documentation: https://docs.aws.amazon.com/lambda/
- Amazon Kinesis documentation: https://docs.aws.amazon.com/kinesis/
- Amazon DynamoDB documentation: https://docs.aws.amazon.com/dynamodb/

## Version History

- v1.0: Initial implementation with CloudFormation, CDK, Terraform, and Bash scripts
- v1.1: Added comprehensive monitoring and improved error handling