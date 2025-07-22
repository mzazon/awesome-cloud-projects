# Infrastructure as Code for IoT Device Shadows for State Management

This directory contains Infrastructure as Code (IaC) implementations for the recipe "IoT Device Shadows for State Management".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for IoT Core, Lambda, DynamoDB, and IAM
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+
- Basic understanding of IoT device communication and MQTT protocol

### Required AWS Permissions

Your AWS credentials need permissions for:
- IoT Core (Things, Certificates, Policies, Rules)
- Lambda (Function creation and execution)
- DynamoDB (Table creation and data operations)
- IAM (Role and policy management)
- CloudWatch Logs (Log group creation)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name iot-device-shadows-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ThingName,ParameterValue=my-smart-device

# Monitor deployment
aws cloudformation wait stack-create-complete \
    --stack-name iot-device-shadows-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name iot-device-shadows-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not done before)
cdk bootstrap

# Deploy the stack
cdk deploy

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

# Bootstrap CDK (if not done before)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
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

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# Follow the interactive prompts to configure your deployment
```

## Architecture Overview

The infrastructure creates:

1. **IoT Thing**: Represents your physical device in AWS IoT Core
2. **Device Certificate**: X.509 certificate for device authentication
3. **IoT Policy**: Defines permissions for device shadow operations
4. **Device Shadow**: Persistent JSON document for device state
5. **IoT Rule**: Processes shadow update events automatically
6. **Lambda Function**: Handles shadow updates and business logic
7. **DynamoDB Table**: Stores historical device state data
8. **IAM Roles**: Secure execution permissions for Lambda

## Configuration Options

### CloudFormation Parameters

- `ThingName`: Name for the IoT Thing (default: smart-thermostat-demo)
- `Environment`: Deployment environment (default: dev)
- `TableName`: DynamoDB table name (auto-generated if not specified)

### CDK Configuration

Edit the configuration in the CDK app file:

```typescript
// cdk-typescript/app.ts
const config = {
  thingName: 'my-smart-device',
  environment: 'production',
  enableRetentionPeriod: true
};
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
thing_name = "my-smart-device"
environment = "production"
lambda_timeout = 30
lambda_memory_size = 128
table_billing_mode = "PAY_PER_REQUEST"
```

### Bash Script Configuration

The deploy script will prompt for:
- Thing name
- AWS region
- Environment tag
- Whether to create sample data

## Testing the Deployment

After deployment, test the Device Shadow functionality:

```bash
# Set your thing name
THING_NAME="your-thing-name"

# Get current shadow state
aws iot-data get-thing-shadow \
    --thing-name ${THING_NAME} \
    current-shadow.json

# Update desired state
echo '{
  "state": {
    "desired": {
      "temperature": 25.0,
      "hvac_mode": "cool"
    }
  }
}' > update-shadow.json

aws iot-data update-thing-shadow \
    --thing-name ${THING_NAME} \
    --payload file://update-shadow.json \
    response.json

# Check Lambda logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/ProcessShadowUpdate-* \
    --start-time $(date -d '5 minutes ago' +%s)000
```

## Monitoring and Observability

The infrastructure includes:

- **CloudWatch Logs**: Lambda function execution logs
- **CloudWatch Metrics**: Lambda performance metrics
- **DynamoDB Metrics**: Table performance and capacity metrics
- **IoT Core Metrics**: Device connectivity and message metrics

Access logs through:

```bash
# View Lambda logs
aws logs describe-log-streams \
    --log-group-name /aws/lambda/ProcessShadowUpdate-*

# Monitor DynamoDB
aws cloudwatch get-metric-statistics \
    --namespace AWS/DynamoDB \
    --metric-name ConsumedReadCapacityUnits \
    --dimensions Name=TableName,Value=DeviceStateHistory-*
```

## Security Considerations

The implementation follows AWS security best practices:

- **Least Privilege IAM**: Roles have minimal required permissions
- **Device-Specific Access**: IoT policies restrict devices to their own shadows
- **Certificate-Based Authentication**: X.509 certificates for device identity
- **Encrypted Communication**: TLS encryption for all MQTT communication
- **Resource Tagging**: All resources tagged for management and billing

## Troubleshooting

### Common Issues

1. **Certificate attachment fails**:
   ```bash
   # Check if certificate is active
   aws iot describe-certificate --certificate-id YOUR_CERT_ID
   ```

2. **Lambda function not triggered**:
   ```bash
   # Verify IoT rule is enabled
   aws iot get-topic-rule --rule-name YOUR_RULE_NAME
   ```

3. **DynamoDB permission errors**:
   ```bash
   # Check Lambda execution role permissions
   aws iam get-role-policy --role-name YOUR_ROLE_NAME --policy-name YOUR_POLICY_NAME
   ```

### Debugging Steps

1. Check CloudWatch Logs for Lambda errors
2. Verify IoT Rule SQL syntax and actions
3. Confirm device certificates are attached to policies
4. Test shadow operations manually using AWS CLI
5. Validate DynamoDB table permissions

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name iot-device-shadows-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name iot-device-shadows-stack
```

### Using CDK

```bash
# From the CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Review what will be destroyed
terraform plan -destroy

# Destroy the infrastructure
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Cost Optimization

To minimize costs during testing:

1. **Use PAY_PER_REQUEST billing** for DynamoDB
2. **Set short Lambda timeout** (30 seconds is sufficient)
3. **Configure minimal Lambda memory** (128 MB)
4. **Delete test devices** when not in use
5. **Monitor CloudWatch Logs** retention period

Estimated monthly costs for moderate usage:
- IoT Core: $0.08 per 100,000 messages
- Lambda: $0.20 per 1 million requests
- DynamoDB: $1.25 per million write requests
- CloudWatch Logs: $0.50 per GB stored

## Customization

### Extending the Lambda Function

Modify the Lambda code to add:
- Data validation and sanitization
- Integration with other AWS services
- Custom business logic for device state
- Alert notifications for critical states

### Adding Named Shadows

For multiple shadow support:

```json
{
  "shadowName": "configuration",
  "state": {
    "desired": {
      "update_interval": 300,
      "logging_level": "INFO"
    }
  }
}
```

### Scaling for Multiple Devices

Consider these patterns for fleet management:
- Device groups with shared policies
- Bulk certificate generation
- Fleet indexing for search operations
- Device defender for security monitoring

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS IoT Core documentation
3. Verify AWS CLI and SDK versions
4. Consult AWS CloudFormation/CDK/Terraform documentation
5. Check AWS service quotas and limits

## Additional Resources

- [AWS IoT Device Shadow Service](https://docs.aws.amazon.com/iot/latest/developerguide/iot-device-shadows.html)
- [AWS IoT Core MQTT Topics](https://docs.aws.amazon.com/iot/latest/developerguide/topics.html)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)