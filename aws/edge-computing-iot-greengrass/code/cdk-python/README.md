# AWS CDK Python - IoT Greengrass Edge Computing

This AWS CDK Python application deploys the complete infrastructure for edge computing with AWS IoT Greengrass, implementing the solution described in the "Edge Computing with IoT Greengrass" recipe.

## Architecture Overview

This CDK application creates:

- **IoT Core Infrastructure**: Things, Thing Groups, and device certificates for secure device management
- **IoT Policies**: Comprehensive permissions for Greengrass Core device operations
- **IAM Roles**: Service roles for Greengrass Core AWS service access
- **Lambda Functions**: Edge processing functions that run locally on Greengrass devices
- **CloudWatch Logging**: Centralized logging for monitoring and debugging
- **Secrets Management**: Secure storage of device certificates and keys

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI** installed and configured with appropriate permissions
2. **Python 3.8+** installed on your development machine
3. **AWS CDK v2** installed globally (`npm install -g aws-cdk`)
4. **Docker** installed (required for Lambda function bundling)
5. **AWS Account** with permissions for IoT, Lambda, IAM, and CloudWatch

### Required AWS Permissions

Your AWS credentials must have permissions for:
- IoT Core (Things, Certificates, Policies, Thing Groups)
- Lambda (Function creation and management)
- IAM (Role and policy creation)
- CloudWatch Logs (Log group creation)
- Secrets Manager (Secret creation and management)

## Quick Start

### 1. Environment Setup

```bash
# Clone or navigate to the CDK application directory
cd aws/edge-computing-aws-iot-greengrass/code/cdk-python/

# Create and activate Python virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. CDK Bootstrap (First-time setup)

```bash
# Bootstrap CDK in your AWS account and region
cdk bootstrap
```

### 3. Deploy the Infrastructure

```bash
# Synthesize CloudFormation template (optional - for review)
cdk synth

# Deploy the stack
cdk deploy --require-approval never

# Or deploy with specific parameters
cdk deploy IoTGreengrassStack \
    --parameters environment=production \
    --parameters costCenter=iot-department
```

### 4. Post-Deployment Setup

After successful deployment, you'll need to complete the Greengrass Core device setup:

```bash
# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name IoTGreengrassStack \
    --query 'Stacks[0].Outputs'

# Create and download IoT certificates (manual step required)
# See "Certificate Management" section below
```

## Configuration Options

### Environment Variables

Set these environment variables before deployment:

```bash
export CDK_DEFAULT_ACCOUNT="123456789012"
export CDK_DEFAULT_REGION="us-east-1"
export ENVIRONMENT="development"  # or production
export COST_CENTER="iot-development"
```

### CDK Context Values

You can customize the deployment using CDK context:

```bash
# Deploy to specific account/region
cdk deploy -c account=123456789012 -c region=us-west-2

# Set environment type
cdk deploy -c environment=production

# Set cost center for billing
cdk deploy -c cost_center=iot-production
```

### Stack Parameters

The CDK application supports these customizable parameters:

- **Environment**: Deployment environment (development/staging/production)
- **Cost Center**: For billing and cost allocation
- **Thing Name Prefix**: Custom prefix for IoT Thing names
- **Log Retention**: CloudWatch log retention period

## Certificate Management

Due to AWS CDK limitations, IoT device certificates must be created post-deployment:

### 1. Create Device Certificates

```bash
# Get the Thing name from stack outputs
THING_NAME=$(aws cloudformation describe-stacks \
    --stack-name IoTGreengrassStack \
    --query 'Stacks[0].Outputs[?OutputKey==`ThingName`].OutputValue' \
    --output text)

# Create certificates
CERT_ARN=$(aws iot create-keys-and-certificate \
    --set-as-active \
    --query 'certificateArn' --output text)

# Get certificate ID
CERT_ID=$(echo ${CERT_ARN} | cut -d'/' -f2)

# Download certificate files
aws iot describe-certificate \
    --certificate-id ${CERT_ID} \
    --query 'certificateDescription.certificatePem' \
    --output text > device.pem.crt

# Download private key (available only once during creation)
# Store securely and copy to your Greengrass device
```

### 2. Attach Certificate to Policy

```bash
# Get policy name from stack outputs
POLICY_NAME=$(aws cloudformation describe-stacks \
    --stack-name IoTGreengrassStack \
    --query 'Stacks[0].Outputs[?OutputKey==`IoTPolicyName`].OutputValue' \
    --output text)

# Attach policy to certificate
aws iot attach-policy \
    --policy-name ${POLICY_NAME} \
    --target ${CERT_ARN}
```

### 3. Update Secrets Manager

```bash
# Get secret name from stack outputs
SECRET_NAME=$(aws cloudformation describe-stacks \
    --stack-name IoTGreengrassStack \
    --query 'Stacks[0].Outputs[?OutputKey==`CertificateSecretName`].OutputValue' \
    --output text)

# Update secret with actual certificate ARN
aws secretsmanager update-secret \
    --secret-id ${SECRET_NAME} \
    --secret-string "{\"certificateArn\":\"${CERT_ARN}\",\"certificateId\":\"${CERT_ID}\"}"
```

## Greengrass Device Setup

After deploying the infrastructure, install Greengrass Core on your edge device:

### 1. Install Greengrass Core Software

```bash
# Download Greengrass Core installer
curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip \
    -o greengrass-nucleus-latest.zip

# Extract installer
unzip greengrass-nucleus-latest.zip -d GreengrassCore

# Install with automatic configuration
sudo -E java -Droot="/greengrass/v2" \
    -Dlog.store=FILE \
    -jar ./GreengrassCore/lib/Greengrass.jar \
    --aws-region us-east-1 \
    --thing-name ${THING_NAME} \
    --thing-group-name ${THING_GROUP_NAME} \
    --component-default-user ggc_user:ggc_group \
    --provision true \
    --setup-system-service true
```

### 2. Verify Installation

```bash
# Check Greengrass service status
sudo systemctl status greengrass

# View Greengrass logs
sudo tail -f /greengrass/v2/logs/greengrass.log
```

## Testing and Validation

### 1. Test Lambda Function

```bash
# Get Lambda function name from outputs
LAMBDA_NAME=$(aws cloudformation describe-stacks \
    --stack-name IoTGreengrassStack \
    --query 'Stacks[0].Outputs[?OutputKey==`EdgeLambdaArn`].OutputValue' \
    --output text | cut -d':' -f7)

# Test the function
aws lambda invoke \
    --function-name ${LAMBDA_NAME} \
    --payload '{"device_id": "sensor-001", "temperature": 25.5, "humidity": 60}' \
    response.json

# View response
cat response.json
```

### 2. Monitor CloudWatch Logs

```bash
# View Greengrass system logs
aws logs describe-log-groups --log-group-name-prefix "/aws/greengrass"

# Stream Lambda function logs
aws logs tail /aws/lambda/edge-processor-* --follow
```

### 3. Check IoT Core Connectivity

```bash
# Monitor IoT Core device activity
aws iot describe-thing --thing-name ${THING_NAME}

# Check device shadow
aws iot-data get-thing-shadow \
    --thing-name ${THING_NAME} \
    shadow.json && cat shadow.json
```

## Monitoring and Troubleshooting

### CloudWatch Dashboards

The deployment creates CloudWatch log groups for monitoring:

- `/aws/greengrass/system-*`: Greengrass system logs
- `/aws/greengrass/user-*`: User component logs  
- `/aws/lambda/edge-processor-*`: Lambda function logs

### Common Issues

1. **Certificate Errors**: Ensure certificates are properly created and attached to policies
2. **Permission Errors**: Verify IAM roles have required permissions
3. **Connectivity Issues**: Check network connectivity and IoT endpoints
4. **Resource Limits**: Monitor device CPU and memory usage

### Debug Commands

```bash
# Check Greengrass configuration
sudo /greengrass/v2/bin/greengrass-cli component list

# View component logs
sudo /greengrass/v2/bin/greengrass-cli logs get --log-level INFO

# Restart Greengrass service
sudo systemctl restart greengrass
```

## Cleanup

To remove all resources created by this CDK application:

```bash
# Destroy the CDK stack
cdk destroy IoTGreengrassStack

# Manually delete certificates (if needed)
aws iot update-certificate --certificate-id ${CERT_ID} --new-status INACTIVE
aws iot delete-certificate --certificate-id ${CERT_ID}
```

## Security Considerations

This CDK application implements security best practices:

- **Least Privilege IAM**: Roles have minimal required permissions
- **Certificate-based Authentication**: X.509 certificates for device identity
- **Encrypted Communication**: All device-to-cloud communication is encrypted
- **Secure Secret Storage**: Certificates stored in AWS Secrets Manager
- **Network Security**: Devices communicate only with authorized endpoints

## Cost Optimization

To minimize costs:

- Use appropriate Lambda memory allocation (128MB is sufficient for most edge processing)
- Configure CloudWatch log retention periods based on requirements
- Monitor IoT message usage and optimize publishing frequency
- Use Thing Groups for efficient device management at scale

## Extending the Solution

This CDK application provides a foundation for edge computing. Consider these extensions:

1. **Machine Learning Integration**: Add SageMaker Neo or Greengrass ML inference
2. **Data Streaming**: Integrate with Kinesis Data Streams for real-time analytics
3. **Fleet Management**: Add IoT Device Management for remote device updates
4. **Edge Analytics**: Implement local data aggregation and filtering
5. **Security Enhancement**: Add AWS IoT Device Defender for security monitoring

## Support and Documentation

- [AWS IoT Greengrass Documentation](https://docs.aws.amazon.com/greengrass/)
- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [AWS IoT Core Documentation](https://docs.aws.amazon.com/iot/)
- [Recipe Documentation](../../../edge-computing-aws-iot-greengrass.md)

For issues with this CDK application, refer to the troubleshooting section or AWS documentation.