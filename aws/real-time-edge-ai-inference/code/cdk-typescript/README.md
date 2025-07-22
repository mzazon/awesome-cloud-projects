# Edge AI Inference CDK TypeScript Implementation

This directory contains the AWS CDK TypeScript implementation for deploying real-time edge AI inference infrastructure using SageMaker and IoT Greengrass.

## Architecture Overview

This CDK application creates the following AWS resources:

- **S3 Bucket**: Secure storage for ML models with versioning and lifecycle policies
- **IAM Roles**: Token Exchange Role and Device Role for secure edge device operation
- **IoT Core**: Policies, Role Alias, and device authentication
- **EventBridge**: Custom event bus for centralized monitoring
- **CloudWatch Logs**: Log group for capturing inference events
- **Greengrass Components**: ONNX Runtime, Model, and Inference Engine components

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI** installed and configured with appropriate permissions
2. **Node.js 18+** installed
3. **AWS CDK v2** installed globally: `npm install -g aws-cdk`
4. **TypeScript** installed globally: `npm install -g typescript`
5. An edge device (Raspberry Pi, NVIDIA Jetson, or x86_64 Linux) for deployment

## Required AWS Permissions

Your AWS credentials need the following permissions:
- Full access to IoT Core, S3, IAM, EventBridge, CloudWatch Logs
- Ability to create and manage Greengrass components
- CloudFormation stack creation and management

## Installation and Deployment

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment (Optional)

You can customize the deployment by setting environment variables:

```bash
export PROJECT_NAME="my-edge-ai"
export ENVIRONMENT="prod"
export CDK_DEFAULT_ACCOUNT="123456789012"
export CDK_DEFAULT_REGION="us-east-1"
```

### 3. Bootstrap CDK (First-time setup)

If this is your first time using CDK in this account/region:

```bash
cdk bootstrap
```

### 4. Synthesize CloudFormation Template

```bash
npm run synth
```

### 5. Deploy the Stack

```bash
npm run deploy
```

Or using CDK directly:

```bash
cdk deploy
```

## Configuration Options

The stack accepts the following context parameters:

```bash
# Deploy with custom project name
cdk deploy -c projectName=my-custom-project

# Deploy with custom environment
cdk deploy -c environment=staging

# Deploy with both
cdk deploy -c projectName=my-project -c environment=prod
```

## Post-Deployment Setup

After successful deployment, follow these steps:

### 1. Upload Sample Model to S3

```bash
# Get the bucket name from CDK outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name edge-ai-inference-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`ModelBucketName`].OutputValue' \
    --output text)

# Create sample model files (for demo)
echo "model.onnx placeholder" > model.onnx
echo '{"input_shape": [1, 3, 224, 224]}' > config.json

# Upload to S3
aws s3 cp model.onnx s3://${BUCKET_NAME}/models/v1.0.0/
aws s3 cp config.json s3://${BUCKET_NAME}/models/v1.0.0/
```

### 2. Set Up Edge Device

Create an IoT Thing and certificates for your edge device:

```bash
# Create IoT Thing
THING_NAME="my-edge-device-$(date +%s)"
aws iot create-thing --thing-name ${THING_NAME}

# Create and download certificates
CERT_ARN=$(aws iot create-keys-and-certificate \
    --set-as-active \
    --certificate-pem-outfile device.cert.pem \
    --public-key-outfile device.public.key \
    --private-key-outfile device.private.key \
    --query certificateArn --output text)

# Download root CA
curl -o root-ca-cert.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem

# Attach IoT policy to certificate (get policy name from CDK outputs)
POLICY_NAME=$(aws cloudformation describe-stacks \
    --stack-name edge-ai-inference-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`IoTPolicyName`].OutputValue' \
    --output text)

aws iot attach-policy \
    --policy-name ${POLICY_NAME} \
    --target ${CERT_ARN}
```

### 3. Install Greengrass on Edge Device

On your edge device:

```bash
# Download Greengrass installer
curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip > greengrass-nucleus-latest.zip
unzip greengrass-nucleus-latest.zip -d GreengrassInstaller

# Get role alias from CDK outputs
ROLE_ALIAS=$(aws cloudformation describe-stacks \
    --stack-name edge-ai-inference-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`IoTRoleAliasName`].OutputValue' \
    --output text)

# Install Greengrass (run on edge device)
sudo -E java -Droot="/greengrass/v2" -Dlog.store=FILE \
    -jar ./GreengrassInstaller/lib/Greengrass.jar \
    --aws-region us-east-1 \
    --thing-name ${THING_NAME} \
    --iot-role-alias ${ROLE_ALIAS} \
    --cert-path device.cert.pem \
    --key-path device.private.key \
    --root-ca-path root-ca-cert.pem \
    --component-default-user ggc_user:ggc_group \
    --provision true \
    --setup-system-service true
```

### 4. Deploy Components to Edge Device

```bash
# Get component names from CDK outputs
ONNX_COMPONENT=$(aws cloudformation describe-stacks \
    --stack-name edge-ai-inference-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`OnnxRuntimeComponentName`].OutputValue' \
    --output text)

MODEL_COMPONENT=$(aws cloudformation describe-stacks \
    --stack-name edge-ai-inference-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`ModelComponentName`].OutputValue' \
    --output text)

INFERENCE_COMPONENT=$(aws cloudformation describe-stacks \
    --stack-name edge-ai-inference-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`InferenceEngineComponentName`].OutputValue' \
    --output text)

# Create deployment
aws greengrassv2 create-deployment \
    --target-arn "arn:aws:iot:us-east-1:${AWS_ACCOUNT_ID}:thing/${THING_NAME}" \
    --deployment-name "EdgeAIInferenceDeployment" \
    --components "{
        \"${ONNX_COMPONENT}\": {\"componentVersion\": \"1.0.0\"},
        \"${MODEL_COMPONENT}\": {\"componentVersion\": \"1.0.0\"},
        \"${INFERENCE_COMPONENT}\": {\"componentVersion\": \"1.0.0\"},
        \"aws.greengrass.Cli\": {\"componentVersion\": \"2.12.0\"}
    }"
```

## Monitoring and Validation

### View EventBridge Events

```bash
# Get log group name from CDK outputs
LOG_GROUP=$(aws cloudformation describe-stacks \
    --stack-name edge-ai-inference-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`LogGroupName`].OutputValue' \
    --output text)

# Tail logs to see inference events
aws logs tail ${LOG_GROUP} --follow
```

### Check Greengrass Component Status

On the edge device:

```bash
sudo /greengrass/v2/bin/greengrass-cli component list
sudo /greengrass/v2/bin/greengrass-cli logs get --all
```

## Customization

### Modify Components

To update the inference components:

1. Edit the component recipes in `edge-ai-inference-stack.ts`
2. Update component versions
3. Redeploy the stack: `cdk deploy`
4. Create a new deployment to the edge device

### Add New Components

To add additional Greengrass components:

1. Create new `CfnGreengrassComponentVersion` constructs
2. Add dependencies between components
3. Include in deployment configuration

## Troubleshooting

### Common Issues

1. **Deployment Fails**: Check IAM permissions and ensure all prerequisites are met
2. **Components Not Installing**: Verify S3 bucket access and network connectivity on edge device
3. **No Events in CloudWatch**: Check EventBridge permissions and component configuration

### Debugging Commands

```bash
# Check stack deployment status
cdk list
cdk diff

# View CloudFormation events
aws cloudformation describe-stack-events --stack-name edge-ai-inference-dev

# Check Greengrass logs on device
sudo tail -f /greengrass/v2/logs/greengrass.log
```

## Cleanup

To remove all resources:

```bash
npm run destroy
```

Or using CDK directly:

```bash
cdk destroy
```

**Note**: This will delete all resources including the S3 bucket and stored models.

## Cost Optimization

- S3 bucket includes lifecycle policies to reduce storage costs
- EventBridge charges are minimal for typical edge inference volumes
- IoT Core charges apply per message published
- Consider using S3 Intelligent Tiering for large model storage

## Security Best Practices

This implementation follows AWS security best practices:

- ✅ Least privilege IAM roles
- ✅ Encrypted S3 storage
- ✅ Secure device authentication via certificates
- ✅ Network isolation through VPC (optional)
- ✅ CloudTrail logging (account-level)

## Support

For issues with this CDK implementation:

1. Check AWS CDK documentation: https://docs.aws.amazon.com/cdk/
2. Review IoT Greengrass documentation: https://docs.aws.amazon.com/greengrass/
3. Consult the original recipe documentation
4. Submit issues to the AWS Samples repository

## License

This code is licensed under the MIT-0 License. See the LICENSE file for details.