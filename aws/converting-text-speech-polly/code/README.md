# Infrastructure as Code for Converting Text to Speech with Polly

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Converting Text to Speech with Polly".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for Polly, S3, Lambda, and IAM services
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python and Lambda functions)
- Terraform 1.0+ (for Terraform implementation)
- Estimated cost: $0.10-2.00 per hour for testing

## Architecture Overview

This implementation deploys:
- Amazon Polly for text-to-speech synthesis
- S3 bucket for audio file storage
- Lambda function for batch processing
- IAM roles and policies for secure access
- Custom pronunciation lexicons
- CloudFront distribution for content delivery (optional)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name polly-text-to-speech-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketName,ParameterValue=my-polly-audio-bucket

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name polly-text-to-speech-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name polly-text-to-speech-stack \
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
cdk deploy

# View outputs
cdk outputs
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
cdk deploy

# View outputs
cdk outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
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
# and deploy all necessary resources
```

## Configuration Options

### CloudFormation Parameters

- `BucketName`: Name for the S3 bucket (must be globally unique)
- `LambdaFunctionName`: Name for the Lambda function
- `Environment`: Environment tag (dev, staging, prod)

### CDK Configuration

Both CDK implementations support environment variables:

```bash
export POLLY_BUCKET_NAME=my-polly-audio-bucket
export ENVIRONMENT=dev
export AWS_REGION=us-east-1
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
bucket_name = "my-polly-audio-bucket"
lambda_function_name = "polly-batch-processor"
environment = "dev"
aws_region = "us-east-1"
```

## Testing the Deployment

### Basic Voice Synthesis Test

```bash
# Set environment variables from outputs
export BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name polly-text-to-speech-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`AudioBucketName`].OutputValue' \
    --output text)

# Test basic synthesis
aws polly synthesize-speech \
    --text "Hello from Amazon Polly! This is a test of the text-to-speech deployment." \
    --output-format mp3 \
    --voice-id Joanna \
    --engine neural \
    test-audio.mp3

# Upload to S3
aws s3 cp test-audio.mp3 s3://${BUCKET_NAME}/test/
```

### Lambda Function Test

```bash
# Get Lambda function name from outputs
export LAMBDA_FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name polly-text-to-speech-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Test Lambda function
aws lambda invoke \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --payload '{"text": "Testing the Lambda-based text-to-speech processing", "voice_id": "Matthew"}' \
    lambda-response.json

# View response
cat lambda-response.json
```

### SSML Processing Test

```bash
# Test SSML processing
aws polly synthesize-speech \
    --text-type ssml \
    --text '<speak>Welcome to <emphasis level="strong">Amazon Polly</emphasis>. <break time="500ms"/> This is a test of SSML processing.</speak>' \
    --output-format mp3 \
    --voice-id Joanna \
    --engine neural \
    ssml-test.mp3
```

## Voice Options and Features

### Available Neural Voices

The deployment supports all Amazon Polly neural voices:

- **English (US)**: Ivy, Joanna, Kendra, Kimberly, Salli, Joey, Justin, Kevin, Matthew
- **English (British)**: Amy, Emma, Brian
- **Other Languages**: Multiple voices for Spanish, French, German, Italian, Portuguese, and more

### Voice Features

1. **Standard Voices**: Traditional text-to-speech voices
2. **Neural Voices**: High-quality, natural-sounding voices
3. **Long-form Voices**: Optimized for longer content
4. **Generative Voices**: Most human-like and expressive

### SSML Support

The deployment supports full SSML (Speech Synthesis Markup Language):

- `<emphasis>`: Add emphasis to words
- `<break>`: Insert pauses
- `<prosody>`: Control rate, pitch, and volume
- `<say-as>`: Control pronunciation of numbers, dates, etc.
- `<phoneme>`: Specify exact pronunciation

## Custom Lexicons

The infrastructure includes support for custom pronunciation lexicons:

```bash
# Upload a custom lexicon
aws polly put-lexicon \
    --name MyCustomLexicon \
    --content file://my-lexicon.xml

# Use lexicon in synthesis
aws polly synthesize-speech \
    --text "AWS Polly API provides excellent capabilities" \
    --lexicon-names MyCustomLexicon \
    --voice-id Joanna \
    --engine neural \
    --output-format mp3 \
    lexicon-test.mp3
```

## Monitoring and Logging

### CloudWatch Integration

All deployments include CloudWatch logging and monitoring:

- Lambda function logs in CloudWatch Logs
- S3 access logging (optional)
- Polly API usage metrics
- Cost and billing alerts

### Viewing Logs

```bash
# View Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/"

# Get recent log events
aws logs filter-log-events \
    --log-group-name "/aws/lambda/${LAMBDA_FUNCTION_NAME}" \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Security Considerations

### IAM Permissions

The deployment follows least-privilege principles:

- Lambda execution role with minimal required permissions
- S3 bucket policies restricting access to specific resources
- Polly permissions limited to synthesis operations

### Data Protection

- Audio files stored in S3 with server-side encryption
- VPC endpoint support for private network access
- CloudFront integration for secure content delivery

## Cost Optimization

### Pricing Considerations

- Standard voices: $4.00 per 1 million characters
- Neural voices: $16.00 per 1 million characters
- Long-form voices: $100.00 per 1 million characters
- S3 storage and data transfer charges apply

### Cost-Saving Tips

1. Use caching to avoid re-synthesizing identical content
2. Choose appropriate voice types for your use case
3. Implement S3 lifecycle policies for audio files
4. Use CloudFront for global content delivery

## Troubleshooting

### Common Issues

1. **Synthesis Failures**:
   - Check text length limits (200,000 characters for neural voices)
   - Validate SSML syntax
   - Verify voice availability in your region

2. **Lambda Timeouts**:
   - Increase Lambda timeout for longer content
   - Consider using asynchronous processing for large files

3. **S3 Access Issues**:
   - Verify IAM permissions
   - Check bucket policies
   - Ensure bucket exists in the correct region

### Debug Commands

```bash
# Check Polly service availability
aws polly describe-voices --region us-east-1

# Test S3 access
aws s3 ls s3://${BUCKET_NAME}

# Check Lambda function configuration
aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME}
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name polly-text-to-speech-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name polly-text-to-speech-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# From the appropriate CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup (if needed)

```bash
# Empty S3 bucket before deletion
aws s3 rm s3://${BUCKET_NAME} --recursive

# Delete custom lexicons
aws polly delete-lexicon --name MyCustomLexicon

# Clean up CloudWatch log groups
aws logs delete-log-group \
    --log-group-name "/aws/lambda/${LAMBDA_FUNCTION_NAME}"
```

## Advanced Usage

### Batch Processing

For processing large amounts of content:

```bash
# Start asynchronous synthesis task
aws polly start-speech-synthesis-task \
    --text file://large-content.txt \
    --output-format mp3 \
    --voice-id Joanna \
    --engine long-form \
    --output-s3-bucket-name ${BUCKET_NAME} \
    --output-s3-key-prefix "batch-processing/"
```

### Speech Marks

For applications requiring synchronization:

```bash
# Generate speech marks
aws polly synthesize-speech \
    --text "Text for synchronization" \
    --output-format json \
    --voice-id Joanna \
    --engine neural \
    --speech-mark-types '["sentence", "word", "viseme"]' \
    speech-marks.json
```

## Integration Examples

### Web Application Integration

```javascript
// Example: Browser-based synthesis request
const synthesizeText = async (text, voiceId = 'Joanna') => {
    const response = await fetch('/api/synthesize', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text, voiceId })
    });
    return response.json();
};
```

### Mobile Application Integration

```python
# Example: Python/Flask API endpoint
from flask import Flask, request, jsonify
import boto3

app = Flask(__name__)
polly = boto3.client('polly')

@app.route('/synthesize', methods=['POST'])
def synthesize_speech():
    data = request.json
    response = polly.synthesize_speech(
        Text=data['text'],
        VoiceId=data.get('voiceId', 'Joanna'),
        OutputFormat='mp3',
        Engine='neural'
    )
    # Process and return audio stream
    return jsonify({'status': 'success'})
```

## Support

For issues with this infrastructure code:

1. Check the [Amazon Polly documentation](https://docs.aws.amazon.com/polly/)
2. Review the original recipe documentation
3. Consult AWS CloudFormation/CDK/Terraform documentation
4. Check AWS service status and regional availability

## Additional Resources

- [Amazon Polly Developer Guide](https://docs.aws.amazon.com/polly/latest/dg/)
- [SSML Reference](https://docs.aws.amazon.com/polly/latest/dg/ssml.html)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)