# Infrastructure as Code for Generating Speech with Amazon Polly

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Generating Speech with Amazon Polly".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for Amazon Polly and S3 services
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Bash shell environment for script execution

### Required AWS Permissions

Your AWS credentials must have the following permissions:
- `polly:DescribeVoices`
- `polly:SynthesizeSpeech`
- `polly:StartSpeechSynthesisTask`
- `polly:GetSpeechSynthesisTask`
- `polly:PutLexicon`
- `polly:GetLexicon`
- `polly:ListLexicons`
- `polly:DeleteLexicon`
- `s3:CreateBucket`
- `s3:GetObject`
- `s3:PutObject`
- `s3:DeleteObject`
- `s3:DeleteBucket`
- `s3:ListBucket`

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name polly-text-to-speech-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Environment,ParameterValue=demo \
    --capabilities CAPABILITY_IAM

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name polly-text-to-speech-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name polly-text-to-speech-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters environment=demo

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python (AWS)

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
cdk deploy --parameters environment=demo

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="environment=demo"

# Apply the configuration
terraform apply -var="environment=demo"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for configuration values
# Follow the prompts to set up your environment
```

## Configuration Options

### Environment Variables

All implementations support these environment variables:

```bash
export AWS_REGION=us-east-1                    # AWS region for deployment
export ENVIRONMENT=demo                        # Environment name (dev/staging/prod)
export BUCKET_PREFIX=polly-audio-output        # S3 bucket name prefix
export ENABLE_VERSIONING=true                  # Enable S3 bucket versioning
export ENABLE_ENCRYPTION=true                  # Enable S3 bucket encryption
export ENABLE_LOGGING=true                     # Enable CloudTrail logging
```

### Customization Parameters

#### CloudFormation Parameters
- `Environment`: Environment name (default: demo)
- `BucketPrefix`: S3 bucket name prefix
- `EnableVersioning`: Enable S3 versioning (true/false)
- `EnableEncryption`: Enable S3 encryption (true/false)

#### CDK Parameters
- `environment`: Environment name
- `bucketPrefix`: S3 bucket name prefix
- `enableVersioning`: Enable S3 versioning
- `enableEncryption`: Enable S3 encryption

#### Terraform Variables
- `environment`: Environment name
- `bucket_prefix`: S3 bucket name prefix
- `enable_versioning`: Enable S3 versioning
- `enable_encryption`: Enable S3 encryption
- `aws_region`: AWS region for deployment

## Architecture Overview

The infrastructure creates the following AWS resources:

### Core Resources
- **S3 Bucket**: Storage for batch synthesis audio output
- **IAM Roles**: Service roles for Polly batch synthesis
- **CloudWatch Logs**: Log groups for monitoring and troubleshooting

### Security Features
- **S3 Bucket Encryption**: AES-256 encryption at rest
- **Bucket Versioning**: Version control for audio files
- **Access Logging**: CloudTrail logging for API calls
- **IAM Least Privilege**: Minimal required permissions

### Monitoring & Logging
- **CloudWatch Metrics**: Polly service metrics
- **CloudWatch Alarms**: Alerts for synthesis failures
- **CloudTrail**: API call logging and auditing

## Usage Examples

After deployment, you can use the infrastructure for various text-to-speech scenarios:

### Basic Speech Synthesis
```bash
# Get bucket name from outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name polly-text-to-speech-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`AudioOutputBucket`].OutputValue' \
    --output text)

# Synthesize speech
aws polly synthesize-speech \
    --text "Hello from Amazon Polly!" \
    --output-format mp3 \
    --voice-id Joanna \
    --engine neural \
    hello-world.mp3
```

### Batch Synthesis
```bash
# Start batch synthesis task
aws polly start-speech-synthesis-task \
    --text "This is a longer text for batch processing..." \
    --output-format mp3 \
    --output-s3-bucket-name $BUCKET_NAME \
    --voice-id Matthew \
    --engine neural
```

### SSML Enhanced Speech
```bash
# Create SSML file
cat > ssml-sample.xml << 'EOF'
<speak>
    <prosody rate="slow">
        Welcome to <emphasis level="strong">Amazon Polly</emphasis>
    </prosody>
    <break time="1s"/>
    <prosody rate="fast">This is exciting!</prosody>
</speak>
EOF

# Synthesize with SSML
aws polly synthesize-speech \
    --text-type ssml \
    --text file://ssml-sample.xml \
    --output-format mp3 \
    --voice-id Joanna \
    --engine neural \
    ssml-output.mp3
```

## Monitoring and Troubleshooting

### CloudWatch Metrics
Monitor these key metrics in CloudWatch:
- `AWS/Polly/RequestCharacters`: Characters processed
- `AWS/Polly/ResponseTime`: API response times
- `AWS/S3/BucketRequests`: S3 bucket activity

### CloudWatch Logs
Check these log groups for troubleshooting:
- `/aws/polly/synthesis-tasks`: Batch synthesis logs
- `/aws/cloudtrail/polly-api-calls`: API call logs

### Common Issues
1. **Synthesis Task Failures**: Check IAM permissions for S3 access
2. **Audio Quality Issues**: Verify voice engine selection (neural vs standard)
3. **Cost Optimization**: Monitor character usage and consider voice engine choices

## Cost Optimization

### Pricing Considerations
- **Standard Voices**: $4.00 per 1 million characters
- **Neural Voices**: $16.00 per 1 million characters
- **S3 Storage**: $0.023 per GB per month (Standard tier)
- **Free Tier**: 5 million characters per month for 12 months

### Cost Optimization Tips
1. Use standard voices for internal applications
2. Enable S3 lifecycle policies to archive old audio files
3. Monitor usage with CloudWatch billing alarms
4. Use batch synthesis for large content volumes

## Cleanup

### Using CloudFormation (AWS)
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name polly-text-to-speech-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name polly-text-to-speech-stack
```

### Using CDK (AWS)
```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="environment=demo"

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Security Best Practices

### Data Protection
- S3 buckets use AES-256 encryption
- Audio files are encrypted at rest
- Access logging enabled for audit trails

### Access Control
- IAM roles follow least privilege principle
- S3 bucket policies restrict unauthorized access
- CloudTrail logging for API monitoring

### Network Security
- S3 bucket public access blocked by default
- VPC endpoints can be added for private access
- SSL/TLS encryption for all API calls

## Support and Troubleshooting

### Common Issues and Solutions

1. **Permission Denied Errors**
   - Verify IAM permissions for Polly and S3 services
   - Check S3 bucket policies and ACLs
   - Ensure proper AWS CLI configuration

2. **Synthesis Task Failures**
   - Verify S3 bucket exists and is accessible
   - Check text content for unsupported characters
   - Validate voice ID and engine compatibility

3. **Audio Quality Issues**
   - Compare neural vs standard voice engines
   - Verify SSML syntax for enhanced speech
   - Check audio format compatibility

### Getting Help
- AWS Support: For account and service-specific issues
- AWS Documentation: [Amazon Polly Developer Guide](https://docs.aws.amazon.com/polly/)
- Community Forums: AWS Developer Forums and Stack Overflow

### Useful Resources
- [Amazon Polly Pricing](https://aws.amazon.com/polly/pricing/)
- [SSML Reference](https://docs.aws.amazon.com/polly/latest/dg/ssml.html)
- [Voice Samples](https://docs.aws.amazon.com/polly/latest/dg/voicelist.html)

For issues with this infrastructure code, refer to the original recipe documentation or the AWS service documentation.