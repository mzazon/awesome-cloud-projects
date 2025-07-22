# Infrastructure as Code for IoT Data Ingestion with IoT Core

This directory contains Infrastructure as Code (IaC) implementations for the recipe "IoT Data Ingestion with IoT Core".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This IaC deploys a complete IoT data ingestion pipeline including:

- AWS IoT Core with device registry and security policies
- Lambda function for real-time data processing
- DynamoDB table for scalable data storage
- SNS topic for alert notifications
- IoT Rules Engine for message routing
- CloudWatch for monitoring and metrics
- Proper IAM roles and security configurations

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - IoT Core (full access)
  - Lambda (create functions, manage execution roles)
  - DynamoDB (create tables, read/write operations)
  - SNS (create topics, publish messages)
  - IAM (create roles and policies)
  - CloudWatch (create log groups, put metrics)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.5+ (for Terraform implementation)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name iot-data-ingestion-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=iot-pipeline \
        ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name iot-data-ingestion-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name iot-data-ingestion-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters projectName=iot-pipeline

# View stack outputs
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

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters projectName=iot-pipeline

# View stack outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
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

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# and display deployment progress
```

## Configuration Options

### Environment Variables

All implementations support these environment variables:

```bash
export AWS_REGION="us-east-1"                    # AWS region for deployment
export PROJECT_NAME="iot-pipeline"               # Project name prefix
export ENVIRONMENT="dev"                         # Environment (dev/staging/prod)
export IOT_THING_TYPE="SensorDevice"            # IoT Thing type name
export ALERT_EMAIL="alerts@company.com"         # Email for SNS notifications
export ENABLE_ENHANCED_MONITORING="true"        # Enable detailed CloudWatch monitoring
```

### Parameters

#### CloudFormation Parameters

- `ProjectName`: Prefix for resource names (default: iot-pipeline)
- `Environment`: Environment name (default: dev)
- `IoTThingType`: IoT Thing type (default: SensorDevice)
- `AlertEmail`: Email for SNS notifications (optional)
- `EnableEnhancedMonitoring`: Enable detailed monitoring (default: true)

#### CDK Parameters

Both TypeScript and Python CDK implementations accept the same parameters via context:

```bash
cdk deploy -c projectName=my-iot -c environment=prod -c alertEmail=admin@company.com
```

#### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
project_name = "iot-pipeline"
environment = "dev"
aws_region = "us-east-1"
iot_thing_type = "SensorDevice"
alert_email = "alerts@company.com"
enable_enhanced_monitoring = true
lambda_timeout = 60
dynamodb_billing_mode = "PAY_PER_REQUEST"
```

## Post-Deployment Setup

After successful deployment, follow these steps to complete the setup:

### 1. Create IoT Device Certificates

```bash
# Get the IoT Thing name from stack outputs
IOT_THING_NAME=$(aws cloudformation describe-stacks \
    --stack-name iot-data-ingestion-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`IoTThingName`].OutputValue' \
    --output text)

# Create device certificates
aws iot create-keys-and-certificate \
    --set-as-active \
    --certificate-pem-outfile device-cert.pem \
    --public-key-outfile device-public.key \
    --private-key-outfile device-private.key

# Download Amazon Root CA
curl -o amazon-root-ca.pem \
    https://www.amazontrust.com/repository/AmazonRootCA1.pem
```

### 2. Configure Device

Use the generated certificates to configure your IoT device with the IoT endpoint:

```bash
# Get IoT endpoint
IOT_ENDPOINT=$(aws iot describe-endpoint \
    --endpoint-type iot:Data-ATS \
    --query 'endpointAddress' --output text)

echo "Configure your device with endpoint: $IOT_ENDPOINT"
```

### 3. Test the Pipeline

```bash
# Publish test message
aws iot-data publish \
    --topic "topic/sensor/data" \
    --payload '{
        "deviceId": "'$IOT_THING_NAME'",
        "timestamp": '$(date +%s)',
        "temperature": 25.5,
        "humidity": 60.2,
        "location": "test-room"
    }'

# Verify data in DynamoDB
DYNAMODB_TABLE=$(aws cloudformation describe-stacks \
    --stack-name iot-data-ingestion-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`DynamoDBTableName`].OutputValue' \
    --output text)

aws dynamodb scan --table-name $DYNAMODB_TABLE --max-items 5
```

## Monitoring and Troubleshooting

### CloudWatch Dashboards

The deployment creates CloudWatch dashboards for monitoring:

- **IoT Metrics**: Device connections, message volume, rule executions
- **Lambda Metrics**: Function invocations, duration, errors
- **DynamoDB Metrics**: Read/write capacity, throttling, errors

### Log Groups

Monitor these CloudWatch log groups:

- `/aws/lambda/iot-processor-*`: Lambda function logs
- `/aws/iot/rules/*`: IoT Rules Engine logs
- `/aws/apigateway/*`: API Gateway logs (if applicable)

### Common Issues

1. **Certificate Authentication Failures**
   - Verify certificate is active and properly attached
   - Check IoT policy permissions
   - Ensure correct IoT endpoint is used

2. **Lambda Function Errors**
   - Check CloudWatch logs for detailed error messages
   - Verify IAM permissions for DynamoDB and SNS access
   - Monitor Lambda timeout and memory settings

3. **DynamoDB Throttling**
   - Monitor consumed capacity metrics
   - Consider switching to provisioned capacity for predictable workloads
   - Review partition key distribution

## Security Considerations

### IAM Permissions

The deployment follows least-privilege principles:

- Lambda execution role has minimal required permissions
- IoT policy restricts device access to specific topics
- DynamoDB access limited to specific table operations

### Network Security

- All communications use TLS/SSL encryption
- IoT device certificates provide mutual authentication
- VPC endpoints can be configured for enhanced security

### Data Protection

- DynamoDB encryption at rest is enabled
- Lambda environment variables are encrypted
- SNS topics use server-side encryption

## Cost Optimization

### Pricing Considerations

- **IoT Core**: Pay per message and connection
- **Lambda**: Pay per invocation and execution time
- **DynamoDB**: Pay-per-request or provisioned capacity
- **SNS**: Pay per message delivery

### Cost Optimization Tips

1. Use DynamoDB on-demand billing for variable workloads
2. Optimize Lambda memory allocation for performance/cost balance
3. Implement message filtering to reduce unnecessary processing
4. Use CloudWatch metrics to identify optimization opportunities

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name iot-data-ingestion-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name iot-data-ingestion-stack \
    --query 'Stacks[0].StackStatus'
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

### Manual Cleanup

If automated cleanup fails, manually delete these resources:

1. IoT certificates and policies
2. CloudWatch log groups
3. Any remaining S3 buckets (if created)
4. IAM roles and policies

## Customization

### Adding New IoT Rules

To add additional IoT rules for different data processing:

1. **CloudFormation**: Add new `AWS::IoT::TopicRule` resources
2. **CDK**: Create additional `iot.TopicRule` constructs
3. **Terraform**: Add new `aws_iot_topic_rule` resources

### Scaling Considerations

For high-volume production deployments:

1. Enable DynamoDB auto-scaling or use provisioned capacity
2. Configure Lambda reserved concurrency
3. Implement DLQ for failed message processing
4. Add CloudWatch alarms for operational metrics

### Integration Extensions

Extend the pipeline with additional AWS services:

- **Kinesis Data Streams**: For high-throughput data ingestion
- **QuickSight**: For real-time dashboards and analytics
- **SageMaker**: For machine learning on IoT data
- **Timestream**: For time-series data optimization

## Support

For issues with this infrastructure code:

1. Check CloudWatch logs for detailed error information
2. Refer to the original recipe documentation
3. Consult AWS IoT Core documentation
4. Review AWS Well-Architected IoT best practices

## Additional Resources

- [AWS IoT Core Documentation](https://docs.aws.amazon.com/iot/)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [IoT Security Best Practices](https://docs.aws.amazon.com/iot/latest/developerguide/security-best-practices.html)