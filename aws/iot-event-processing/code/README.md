# Infrastructure as Code for IoT Event Processing with Rules Engine

This directory contains Infrastructure as Code (IaC) implementations for the recipe "IoT Event Processing with Rules Engine".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an IoT Rules Engine that processes sensor data from temperature sensors, motor controllers, and security cameras. The architecture includes:

- **AWS IoT Core**: MQTT broker and Rules Engine for message processing
- **DynamoDB**: Telemetry data storage with device ID and timestamp partitioning
- **Lambda**: Custom event processing and data enrichment functions
- **SNS**: Real-time alerting and notification system
- **CloudWatch**: Comprehensive logging and monitoring
- **IAM**: Least-privilege security roles and policies

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - IoT Core (rules, things, policies)
  - Lambda (functions, permissions)
  - DynamoDB (tables, read/write operations)
  - SNS (topics, publishing)
  - IAM (roles, policies)
  - CloudWatch (logs, metrics)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name iot-rules-engine-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Environment,ParameterValue=dev \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --tags Key=Project,Value=IoTRulesEngine

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name iot-rules-engine-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name iot-rules-engine-stack \
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
cdk deploy --parameters Environment=dev

# View outputs
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

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters Environment=dev

# View outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="environment=dev"

# Apply configuration
terraform apply -var="environment=dev"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployed resources
aws iot list-topic-rules
aws dynamodb list-tables
aws lambda list-functions
```

## Testing the Deployment

### 1. Verify IoT Rules

```bash
# List created rules
aws iot list-topic-rules --query 'rules[?contains(ruleName, `Rule`)].ruleName'

# Get rule details
aws iot get-topic-rule --rule-name TemperatureAlertRule
```

### 2. Test Temperature Monitoring

```bash
# Publish test temperature data
aws iot-data publish \
    --topic "factory/temperature" \
    --payload '{"deviceId":"temp-sensor-01","temperature":80,"location":"production-floor"}'

# Check DynamoDB for stored data
aws dynamodb scan \
    --table-name factory-telemetry-* \
    --filter-expression "contains(deviceId, :device)" \
    --expression-attribute-values '{":device":{"S":"temp-sensor-01"}}'
```

### 3. Test Motor Status Monitoring

```bash
# Publish motor error event
aws iot-data publish \
    --topic "factory/motors" \
    --payload '{"deviceId":"motor-ctrl-02","motorStatus":"error","vibration":6.5,"location":"assembly-line"}'

# Check Lambda function logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/factory-event-processor-*" \
    --filter-pattern "Processing event"
```

### 4. Test Security Events

```bash
# Publish security intrusion event
aws iot-data publish \
    --topic "factory/security" \
    --payload '{"deviceId":"security-cam-03","eventType":"intrusion","severity":"high","location":"entrance-door"}'

# Check SNS topic for notifications
aws sns get-topic-attributes \
    --topic-arn "arn:aws:sns:*:*:factory-alerts-*"
```

## Monitoring and Troubleshooting

### CloudWatch Logs

```bash
# View IoT Rules Engine logs
aws logs filter-log-events \
    --log-group-name "/aws/iot/rules" \
    --start-time $(date -d '1 hour ago' +%s)000

# View Lambda function logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/factory-event-processor-*" \
    --start-time $(date -d '1 hour ago' +%s)000
```

### CloudWatch Metrics

```bash
# Check rule execution metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/IoT \
    --metric-name RuleMessageMatched \
    --dimensions Name=RuleName,Value=TemperatureAlertRule \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

### Common Issues

1. **Permission Errors**: Ensure IAM roles have correct permissions for IoT, Lambda, DynamoDB, and SNS
2. **Rule Not Firing**: Check CloudWatch logs for rule execution errors
3. **Lambda Timeout**: Verify Lambda function timeout settings and memory allocation
4. **DynamoDB Throttling**: Monitor DynamoDB metrics and adjust read/write capacity if needed

## Customization

### Environment Variables

All implementations support these customizable parameters:

- `environment`: Deployment environment (dev, staging, prod)
- `project_name`: Project identifier for resource naming
- `retention_days`: CloudWatch log retention period
- `lambda_timeout`: Lambda function timeout in seconds
- `lambda_memory`: Lambda function memory allocation in MB

### Terraform Variables

```hcl
# terraform/terraform.tfvars
environment = "production"
project_name = "smart-factory"
retention_days = 30
lambda_timeout = 60
lambda_memory = 256
```

### CloudFormation Parameters

```yaml
Parameters:
  Environment:
    Type: String
    Default: "dev"
    AllowedValues: ["dev", "staging", "prod"]
  
  ProjectName:
    Type: String
    Default: "smart-factory"
  
  RetentionDays:
    Type: Number
    Default: 14
```

### CDK Configuration

```typescript
// cdk-typescript/app.ts
const app = new cdk.App();
new IoTRulesEngineStack(app, 'IoTRulesEngineStack', {
  environment: 'dev',
  projectName: 'smart-factory',
  retentionDays: 14
});
```

## Security Considerations

### IAM Roles and Policies

- **IoT Rules Role**: Minimum permissions for DynamoDB writes, SNS publishing, and Lambda invocation
- **Lambda Execution Role**: Basic execution permissions with CloudWatch logging
- **Service-Specific Policies**: Least-privilege access for each service integration

### Data Protection

- **Encryption at Rest**: DynamoDB encryption enabled by default
- **Encryption in Transit**: TLS 1.2 for all service communications
- **Access Logging**: CloudWatch logs for all rule executions and Lambda invocations

### Network Security

- **VPC Endpoints**: Optional VPC endpoints for private service access
- **Security Groups**: Restrictive security group rules where applicable
- **Resource Policies**: Service-specific resource policies for additional access control

## Cost Optimization

### Resource Sizing

- **DynamoDB**: On-demand billing mode for variable workloads
- **Lambda**: Right-sized memory allocation based on processing requirements
- **CloudWatch**: Appropriate log retention periods to manage storage costs

### Monitoring

- **Cost Alerts**: Set up CloudWatch billing alarms for unexpected costs
- **Usage Metrics**: Monitor IoT message volumes and Lambda invocations
- **Resource Utilization**: Regular review of resource utilization patterns

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name iot-rules-engine-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name iot-rules-engine-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy the stack
cdk destroy

# Confirm deletion
aws cloudformation describe-stacks --stack-name IoTRulesEngineStack || echo "Stack deleted"
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="environment=dev"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
aws iot list-topic-rules
aws dynamodb list-tables
aws lambda list-functions
```

## Advanced Features

### Multi-Environment Deployment

```bash
# Deploy to multiple environments
for env in dev staging prod; do
    terraform workspace new $env
    terraform workspace select $env
    terraform apply -var="environment=$env"
done
```

### Custom Rule Development

1. **Rule SQL Syntax**: Extend rules with advanced SQL filtering
2. **Custom Actions**: Add support for additional AWS services
3. **Error Handling**: Implement dead letter queues for failed messages
4. **Retry Logic**: Configure retry policies for temporary failures

### Integration Patterns

- **API Gateway**: Expose REST endpoints for rule management
- **Step Functions**: Orchestrate complex event processing workflows
- **Kinesis**: Stream processing for high-volume data pipelines
- **SageMaker**: Machine learning integration for anomaly detection

## Support

For issues with this infrastructure code, refer to:

1. **Original Recipe**: [IoT Event Processing with Rules Engine](../iot-rules-engine-event-processing.md)
2. **AWS Documentation**: [IoT Rules Engine Guide](https://docs.aws.amazon.com/iot/latest/developerguide/iot-rules.html)
3. **Provider Documentation**: Consult CloudFormation, CDK, or Terraform documentation for specific implementation details
4. **AWS Support**: Contact AWS Support for service-specific issues

## Contributing

When modifying this infrastructure code:

1. **Test Changes**: Validate all modifications in a development environment
2. **Update Documentation**: Keep README.md synchronized with code changes
3. **Security Review**: Ensure security best practices are maintained
4. **Version Control**: Follow semantic versioning for infrastructure updates

## License

This infrastructure code is provided under the same license as the original recipe documentation.