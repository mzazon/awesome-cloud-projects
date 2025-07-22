# Infrastructure as Code for IoT Device Registry with IoT Core

This directory contains Infrastructure as Code (IaC) implementations for the recipe "IoT Device Registry with IoT Core".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- One of the following tools depending on your chosen implementation:
  - AWS CLI v2 (for CloudFormation and scripts)
  - Node.js 18+ and npm (for CDK TypeScript)
  - Python 3.8+ and pip (for CDK Python)
  - Terraform 1.0+ (for Terraform implementation)
- IAM permissions for the following AWS services:
  - AWS IoT Core (full access)
  - AWS Lambda (create/update/delete functions)
  - AWS IAM (create/attach/detach roles and policies)
  - AWS CloudWatch Logs (create log groups and streams)
- Estimated cost: $5-15/month for testing (varies by message volume and Lambda invocations)

## Quick Start

### Using CloudFormation (AWS)

Deploy the complete IoT device management infrastructure:

```bash
aws cloudformation create-stack \
    --stack-name iot-device-management-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=DeviceName,ParameterValue=temperature-sensor-001 \
                 ParameterKey=Environment,ParameterValue=dev
```

Monitor stack creation:

```bash
aws cloudformation describe-stacks \
    --stack-name iot-device-management-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript (AWS)

Install dependencies and deploy:

```bash
cd cdk-typescript/
npm install
npm run build
cdk bootstrap  # Only needed once per account/region
cdk deploy
```

View stack outputs:

```bash
cdk ls
aws cloudformation describe-stacks \
    --stack-name CdkIotDeviceManagementStack \
    --query 'Stacks[0].Outputs'
```

### Using CDK Python (AWS)

Set up Python environment and deploy:

```bash
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt
cdk bootstrap  # Only needed once per account/region
cdk deploy
```

View deployment status:

```bash
cdk ls
cdk diff  # Preview changes before deployment
```

### Using Terraform

Initialize and deploy infrastructure:

```bash
cd terraform/
terraform init
terraform plan -var="device_name=temperature-sensor-001" \
               -var="environment=dev"
terraform apply -var="device_name=temperature-sensor-001" \
                -var="environment=dev"
```

View created resources:

```bash
terraform show
terraform output
```

### Using Bash Scripts

Execute the deployment script:

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

The script will:
- Set up environment variables
- Create IoT Thing, certificate, and policy
- Deploy Lambda function for data processing
- Configure IoT rules for message routing
- Initialize device shadow state

## Architecture Components

This infrastructure deployment creates:

### IoT Core Components
- **IoT Thing**: Device registry entry with metadata and attributes
- **Device Certificate**: X.509 certificate for device authentication
- **IoT Policy**: JSON policy defining device permissions and access controls
- **IoT Rules**: SQL-based message routing to Lambda functions
- **Device Shadow**: Persistent device state management

### Processing Components
- **Lambda Function**: Serverless data processing for IoT telemetry
- **IAM Role**: Execution role with least privilege permissions
- **CloudWatch Logs**: Log groups for Lambda function output

### Security Features
- Certificate-based device authentication
- Least privilege IoT policies with resource constraints
- Encrypted data transmission (TLS 1.2)
- IAM roles with minimal required permissions

## Configuration Options

### Environment Variables

The implementations support the following customization options:

- `DEVICE_NAME`: Name of the IoT device/thing (default: temperature-sensor-001)
- `ENVIRONMENT`: Deployment environment tag (default: dev)
- `AWS_REGION`: Target AWS region for deployment
- `TEMPERATURE_THRESHOLD`: Alert threshold for temperature processing (default: 80)

### CloudFormation Parameters

```yaml
Parameters:
  DeviceName: 
    Type: String
    Default: temperature-sensor-001
  Environment:
    Type: String
    Default: dev
    AllowedValues: [dev, staging, prod]
```

### CDK Context Variables

```json
{
  "device_name": "temperature-sensor-001",
  "environment": "dev",
  "temperature_threshold": 80
}
```

### Terraform Variables

```hcl
variable "device_name" {
  description = "Name of the IoT device"
  type        = string
  default     = "temperature-sensor-001"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}
```

## Testing the Deployment

After successful deployment, test the IoT infrastructure:

### 1. Verify IoT Thing Creation

```bash
aws iot describe-thing --thing-name temperature-sensor-001
```

### 2. Test Message Publishing

```bash
# Publish test telemetry data
aws iot-data publish \
    --topic sensor/temperature/temperature-sensor-001 \
    --payload '{"temperature": 85.5, "humidity": 65, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'"}'
```

### 3. Check Lambda Function Logs

```bash
aws logs describe-log-groups \
    --log-group-name-prefix /aws/lambda/iot-data-processor

# View recent log events
aws logs describe-log-streams \
    --log-group-name /aws/lambda/iot-data-processor-* \
    --order-by LastEventTime --descending --max-items 1
```

### 4. Verify Device Shadow State

```bash
aws iot-data get-thing-shadow \
    --thing-name temperature-sensor-001 \
    outfile && cat outfile
```

## Device Integration

### Certificate Files

After deployment, device certificates are available for download:

```bash
# CloudFormation - certificates stored in stack outputs
aws cloudformation describe-stacks \
    --stack-name iot-device-management-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`DeviceCertificateArn`].OutputValue'

# CDK/Terraform - certificates referenced in outputs
terraform output device_certificate_arn
```

### MQTT Connection Example

Connect your IoT device using the generated certificates:

```python
import ssl
import paho.mqtt.client as mqtt

# Configure MQTT client with certificates
client = mqtt.Client()
client.tls_set(ca_certs="AmazonRootCA1.pem",
               certfile="device-cert.pem", 
               keyfile="device-private-key.pem",
               cert_reqs=ssl.CERT_REQUIRED,
               tls_version=ssl.PROTOCOL_TLSv1_2)

# Connect to AWS IoT Core
client.connect("your-iot-endpoint.iot.us-east-1.amazonaws.com", 8883, 60)

# Publish telemetry data
client.publish("sensor/temperature/temperature-sensor-001", 
               '{"temperature": 22.5, "timestamp": "2024-01-15T10:30:00Z"}')
```

## Monitoring and Alerts

### CloudWatch Metrics

Monitor IoT Core metrics:

```bash
# View IoT Core message metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/IoT \
    --metric-name PublishIn.Success \
    --start-time 2024-01-15T00:00:00Z \
    --end-time 2024-01-15T23:59:59Z \
    --period 3600 \
    --statistics Sum
```

### Lambda Function Monitoring

```bash
# Check Lambda invocation metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=iot-data-processor-* \
    --start-time 2024-01-15T00:00:00Z \
    --end-time 2024-01-15T23:59:59Z \
    --period 3600 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation (AWS)

```bash
aws cloudformation delete-stack --stack-name iot-device-management-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name iot-device-management-stack
```

### Using CDK (AWS)

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="device_name=temperature-sensor-001" \
                  -var="environment=dev"

# Type 'yes' when prompted to confirm
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh

# Follow prompts for confirmation
```

## Security Considerations

### Certificate Management
- Rotate device certificates regularly (recommended: annually)
- Store private keys securely on devices (hardware security modules preferred)
- Implement certificate revocation procedures for compromised devices

### Policy Best Practices
- Use least privilege principle for IoT policies
- Implement policy variables for device-specific access
- Regular audit of policy permissions and device access patterns

### Network Security
- Use VPC endpoints for private connectivity to IoT Core
- Implement network segmentation for IoT devices
- Monitor unusual traffic patterns and connection attempts

## Troubleshooting

### Common Issues

#### Certificate Connection Errors
```bash
# Verify certificate is active
aws iot describe-certificate --certificate-id YOUR_CERT_ID

# Check policy attachment
aws iot list-attached-policies --target YOUR_CERT_ARN
```

#### Lambda Function Errors
```bash
# Check function configuration
aws lambda get-function --function-name iot-data-processor-*

# Review error logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/iot-data-processor-* \
    --filter-pattern "ERROR"
```

#### IoT Rule Issues
```bash
# Verify rule configuration
aws iot get-topic-rule --rule-name sensor_data_rule_*

# Check rule metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/IoT \
    --metric-name RuleMessageThrottled \
    --dimensions Name=RuleName,Value=sensor_data_rule_*
```

## Cost Optimization

### Cost Monitoring
- Enable AWS Cost Explorer for IoT Core usage analysis
- Set up billing alerts for unexpected usage spikes
- Review message volume and Lambda invocation patterns

### Optimization Strategies
- Use IoT message batching for high-volume devices
- Implement efficient device shadow update patterns
- Consider AWS IoT Device Management for fleet operations

## Customization

Refer to the variable definitions in each implementation to customize the deployment for your environment:

- Modify device attributes and metadata
- Adjust Lambda function memory and timeout settings
- Configure additional IoT rules for different message patterns
- Add CloudWatch alarms for operational monitoring

## Support

For issues with this infrastructure code, refer to:

- [AWS IoT Core Documentation](https://docs.aws.amazon.com/iot/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- Original recipe documentation in the parent directory

## Additional Resources

- [AWS IoT Core Pricing](https://aws.amazon.com/iot-core/pricing/)
- [AWS IoT Device SDK](https://docs.aws.amazon.com/iot/latest/developerguide/iot-sdks.html)
- [AWS IoT Security Best Practices](https://docs.aws.amazon.com/iot/latest/developerguide/security-best-practices.html)
- [MQTT Protocol Specification](https://mqtt.org/mqtt-specification/)