# Infrastructure as Code for IoT Device Provisioning and Certificate Management

This directory contains Infrastructure as Code (IaC) implementations for the recipe "IoT Device Provisioning and Certificate Management".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements automated, secure IoT device provisioning using:

- **AWS IoT Core Fleet Provisioning**: Automated device onboarding with validation
- **Lambda Pre-Provisioning Hook**: Device validation and authorization logic
- **DynamoDB Device Registry**: Centralized device lifecycle management
- **Thing Groups**: Hierarchical device organization
- **IoT Policies**: Fine-grained device permissions
- **Device Shadows**: Virtual device state management
- **CloudWatch Monitoring**: Comprehensive logging and alerting

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - IoT Core (provisioning templates, certificates, policies)
  - Lambda (function creation and execution)
  - DynamoDB (table creation and access)
  - IAM (role and policy management)
  - CloudWatch (logging and monitoring)
- Understanding of X.509 certificates and PKI concepts
- Knowledge of IoT device authentication and MQTT protocol
- Python 3.8+ for Lambda function development

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name iot-device-provisioning-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=IoTProvisioning

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name iot-device-provisioning-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name iot-device-provisioning-stack \
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
cdk deploy --outputs-file outputs.json
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
cdk deploy --outputs-file outputs.json
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

# The script will:
# 1. Create DynamoDB device registry table
# 2. Deploy Lambda pre-provisioning hook
# 3. Set up IoT Core provisioning template
# 4. Create device policies and thing groups
# 5. Generate claim certificates
# 6. Configure monitoring and alerts
```

## Configuration Options

### Key Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `ProjectName` | Name prefix for all resources | `IoTProvisioning` | No |
| `Environment` | Environment name (dev/staging/prod) | `dev` | No |
| `DeviceRegistryTableName` | DynamoDB table for device registry | `device-registry-{random}` | No |
| `AllowedDeviceTypes` | Comma-separated list of allowed device types | `temperature-sensor,humidity-sensor,pressure-sensor,gateway` | No |
| `MonitoringEnabled` | Enable CloudWatch monitoring and alerts | `true` | No |
| `LogRetentionDays` | CloudWatch log retention period | `30` | No |

### Device Types Supported

- **temperature-sensor**: Temperature monitoring devices
- **humidity-sensor**: Humidity monitoring devices  
- **pressure-sensor**: Pressure monitoring devices
- **gateway**: IoT gateway devices with extended permissions

### Security Configuration

- **Least Privilege**: Each device type receives minimum required permissions
- **Certificate Validation**: Pre-provisioning hook validates device metadata
- **Audit Logging**: All provisioning events logged to CloudWatch
- **Device Registry**: Centralized tracking of device lifecycle status

## Post-Deployment Steps

### 1. Verify Deployment

```bash
# Check provisioning template status
aws iot describe-provisioning-template \
    --template-name $(terraform output -raw provisioning_template_name)

# Verify device registry table
aws dynamodb describe-table \
    --table-name $(terraform output -raw device_registry_table_name)

# Test Lambda function
aws lambda invoke \
    --function-name $(terraform output -raw provisioning_hook_function_name) \
    --payload '{"parameters":{"SerialNumber":"TEST123","DeviceType":"temperature-sensor","Manufacturer":"TestCorp"}}' \
    response.json
```

### 2. Configure Device Manufacturing

```bash
# Retrieve claim certificate for device manufacturing
aws iot describe-certificate \
    --certificate-id $(terraform output -raw claim_certificate_id)

# Download claim certificate files
aws iot describe-certificate \
    --certificate-id $(terraform output -raw claim_certificate_id) \
    --query 'certificateDescription.certificatePem' \
    --output text > claim-certificate.pem
```

### 3. Test Device Provisioning

```bash
# Simulate device provisioning request
python3 test_provisioning.py \
    --serial-number "TEST123456" \
    --device-type "temperature-sensor" \
    --manufacturer "AcmeIoT" \
    --firmware-version "v1.0.0"
```

## Monitoring and Alerts

### CloudWatch Dashboards

The deployment creates CloudWatch dashboards for:

- **Provisioning Metrics**: Success/failure rates, processing times
- **Device Registry**: Device counts by type and status
- **Lambda Performance**: Function execution metrics and errors
- **Security Events**: Failed provisioning attempts and anomalies

### Alerts Configuration

Default alerts include:

- **High Provisioning Failures**: >5 failures in 5 minutes
- **Lambda Errors**: Function execution failures
- **DynamoDB Throttling**: Read/write capacity exceeded
- **Certificate Expiration**: Claim certificate approaching expiration

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   ```bash
   # Check IAM role permissions
   aws iam get-role-policy \
       --role-name $(terraform output -raw provisioning_role_name) \
       --policy-name provisioning-policy
   ```

2. **Lambda Function Failures**
   ```bash
   # Check Lambda logs
   aws logs filter-log-events \
       --log-group-name /aws/lambda/$(terraform output -raw provisioning_hook_function_name) \
       --start-time $(date -d '1 hour ago' +%s)000
   ```

3. **Device Provisioning Failures**
   ```bash
   # Check device registry for failed devices
   aws dynamodb scan \
       --table-name $(terraform output -raw device_registry_table_name) \
       --filter-expression "attribute_exists(#status) AND #status = :status" \
       --expression-attribute-names '{"#status": "status"}' \
       --expression-attribute-values '{":status": {"S": "failed"}}'
   ```

### Debug Mode

Enable debug logging by setting environment variables:

```bash
export IOT_PROVISIONING_DEBUG=true
export AWS_SDK_LOAD_CONFIG=1
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name iot-device-provisioning-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name iot-device-provisioning-stack
```

### Using CDK
```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete provisioning template and claim certificates
# 2. Remove Lambda functions and IAM roles
# 3. Delete IoT policies and thing groups
# 4. Clean up DynamoDB table
# 5. Remove CloudWatch resources
```

## Cost Considerations

### Estimated Monthly Costs

- **DynamoDB**: $1-5 (depends on device count and read/write activity)
- **Lambda**: $2-10 (depends on provisioning frequency)
- **IoT Core**: $5-20 (depends on device connections and messages)
- **CloudWatch**: $2-8 (depends on logging and metrics volume)

### Cost Optimization Tips

1. **Use DynamoDB On-Demand**: For unpredictable provisioning patterns
2. **Optimize Lambda Memory**: Right-size based on actual usage
3. **Configure Log Retention**: Set appropriate retention periods for CloudWatch logs
4. **Monitor Device Connections**: Disconnect unused devices to reduce costs

## Security Best Practices

### Certificate Management

- **Rotate Claim Certificates**: Regularly update manufacturing certificates
- **Monitor Certificate Usage**: Track certificate issuance and usage patterns
- **Implement Certificate Revocation**: Have procedures for compromised certificates

### Access Control

- **Least Privilege Policies**: Grant minimal required permissions
- **Regular Access Reviews**: Audit device permissions periodically
- **Segregate Device Types**: Use separate policies for different device types

### Network Security

- **VPC Endpoints**: Use VPC endpoints for private connectivity
- **Security Groups**: Configure restrictive security groups
- **Network Monitoring**: Monitor network traffic patterns

## Customization Examples

### Adding New Device Types

1. **Update Lambda Function**: Add validation logic for new device type
2. **Create IoT Policy**: Define permissions for new device type
3. **Update Thing Groups**: Add new thing group for organization
4. **Configure Monitoring**: Add device-type-specific metrics

### Integrating with External Systems

1. **API Gateway**: Create REST API for provisioning integration
2. **SQS Integration**: Queue provisioning requests for batch processing
3. **SNS Notifications**: Send alerts for provisioning events
4. **Database Integration**: Store extended device metadata

## Support and Documentation

- **AWS IoT Core Documentation**: https://docs.aws.amazon.com/iot/
- **Device Provisioning Guide**: https://docs.aws.amazon.com/iot/latest/developerguide/provision-wo-cert.html
- **IoT Security Best Practices**: https://docs.aws.amazon.com/iot/latest/developerguide/security-best-practices.html
- **Lambda Best Practices**: https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html

For issues with this infrastructure code, refer to the original recipe documentation or consult the AWS documentation for specific services.