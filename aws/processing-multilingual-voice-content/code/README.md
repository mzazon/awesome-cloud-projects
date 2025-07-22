# Infrastructure as Code for Processing Multilingual Voice Content with Transcribe and Polly

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Processing Multilingual Voice Content with Transcribe and Polly".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a comprehensive multi-language voice processing platform that:

- **Detects Languages**: Automatically identifies spoken languages in audio files
- **Transcribes Audio**: Converts speech to text with high accuracy using Amazon Transcribe
- **Translates Content**: Translates transcribed text to multiple target languages using Amazon Translate
- **Synthesizes Speech**: Generates natural-sounding audio in multiple languages using Amazon Polly
- **Orchestrates Workflows**: Manages the entire pipeline using AWS Step Functions

## Infrastructure Components

### Core Services
- **Amazon Transcribe**: Speech-to-text conversion with language detection
- **Amazon Translate**: Neural machine translation between languages
- **Amazon Polly**: Text-to-speech synthesis with neural voices
- **AWS Step Functions**: Workflow orchestration and state management

### Supporting Infrastructure
- **AWS Lambda**: Serverless compute for processing logic (5 functions)
- **Amazon S3**: Storage for input audio, output audio, and processing artifacts (2 buckets)
- **Amazon DynamoDB**: Metadata storage and job tracking
- **AWS IAM**: Security roles and policies with least privilege access

### Monitoring & Operations
- **Amazon CloudWatch**: Logging and metrics collection
- **AWS SNS**: Notifications for job completion and errors

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for all services used
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Sample audio files for testing (optional)

### Required AWS Permissions

Your AWS credentials must have permissions for:
- Transcribe: Full access for transcription jobs and custom vocabularies
- Translate: Full access for translation jobs and custom terminologies
- Polly: Full access for speech synthesis
- Lambda: Create and manage functions, execution roles
- Step Functions: Create and execute state machines
- S3: Create buckets, upload/download objects
- DynamoDB: Create tables, read/write items
- IAM: Create roles and attach policies
- CloudWatch: Create log groups and metrics

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name voice-processing-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-voice-pipeline

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name voice-processing-pipeline \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name voice-processing-pipeline \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
# Navigate to TypeScript CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Review what will be deployed
cdk diff

# Deploy the stack
cdk deploy

# Get outputs
cdk ls --long
```

### Using CDK Python
```bash
# Navigate to Python CDK directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Review what will be deployed
cdk diff

# Deploy the stack
cdk deploy

# Get outputs
cdk ls --long
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output key information including:
# - S3 bucket names
# - Step Functions state machine ARN
# - DynamoDB table name
# - Lambda function names
```

## Testing the Pipeline

After deployment, test the voice processing pipeline:

```bash
# Set environment variables from deployment outputs
export INPUT_BUCKET="your-input-bucket-name"
export STATE_MACHINE_ARN="your-state-machine-arn"

# Create a test audio file using Polly
aws polly synthesize-speech \
    --text "Hello, this is a test of our multi-language voice processing pipeline." \
    --voice-id Joanna \
    --output-format mp3 \
    test-audio.mp3

# Upload test audio to S3
aws s3 cp test-audio.mp3 s3://${INPUT_BUCKET}/test-audio.mp3

# Start the processing pipeline
aws stepfunctions start-execution \
    --state-machine-arn ${STATE_MACHINE_ARN} \
    --name "test-execution-$(date +%Y%m%d-%H%M%S)" \
    --input '{
        "bucket": "'${INPUT_BUCKET}'",
        "key": "test-audio.mp3",
        "job_id": "'$(uuidgen)'",
        "target_languages": ["es", "fr", "de"]
    }'

# Monitor execution in the AWS Console or via CLI
aws stepfunctions list-executions \
    --state-machine-arn ${STATE_MACHINE_ARN} \
    --max-items 5
```

## Configuration Options

### Language Support

The pipeline supports these languages for transcription and translation:

**Transcription Languages**: English (US/UK/AU), Spanish (US/ES), French (FR/CA), German, Italian, Portuguese (BR/PT), Japanese, Korean, Chinese (CN/TW), Arabic, Hindi, Russian, Dutch, Swedish

**Translation Languages**: English, Spanish, French, German, Italian, Portuguese, Japanese, Korean, Chinese, Arabic, Hindi, Russian, Dutch, Swedish, and 50+ additional languages

**Speech Synthesis Languages**: High-quality neural voices available for major languages, with standard voices for additional languages

### Customization Parameters

Most implementations support these customization options:

- **Project Name**: Unique identifier for your deployment
- **Target Languages**: List of languages for translation and synthesis
- **S3 Bucket Names**: Custom names for input and output buckets
- **DynamoDB Table Configuration**: Provisioned vs. on-demand capacity
- **Lambda Function Configuration**: Memory allocation and timeout settings
- **Custom Vocabularies**: Enable/disable custom vocabulary support
- **Notification Settings**: SNS topic configuration for alerts

### Advanced Features

- **Custom Vocabularies**: Improve transcription accuracy for domain-specific terms
- **Custom Terminologies**: Ensure consistent translation of technical terms
- **Neural Voices**: Use advanced neural text-to-speech engines
- **Speaker Diarization**: Identify different speakers in audio (English only)
- **SSML Support**: Advanced speech synthesis markup for better audio quality

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor processing through CloudWatch log groups:
- `/aws/lambda/[project-name]-language-detector`
- `/aws/lambda/[project-name]-transcription-processor`
- `/aws/lambda/[project-name]-translation-processor`
- `/aws/lambda/[project-name]-speech-synthesizer`
- `/aws/stepfunctions/[project-name]-voice-processing`

### Common Issues

1. **Transcription Failures**: Check audio format (supported: MP3, MP4, WAV, FLAC)
2. **Translation Errors**: Verify source/target language compatibility
3. **Speech Synthesis Issues**: Check text length limits and voice availability
4. **Permission Errors**: Verify IAM roles have required service permissions
5. **Timeout Issues**: Increase Lambda function timeout for large audio files

### Performance Optimization

- **Audio Processing**: Use compressed audio formats (MP3) for faster processing
- **Batch Processing**: Process multiple files concurrently using Step Functions
- **Memory Allocation**: Increase Lambda memory for large audio files
- **Custom Models**: Use custom vocabularies and terminologies for better accuracy

## Cost Considerations

### Service Pricing

- **Transcribe**: $0.024 per minute of audio
- **Translate**: $15 per million characters
- **Polly**: $4.00 per million characters (Neural voices: $16.00)
- **Lambda**: $0.20 per million requests + compute time
- **Step Functions**: $0.025 per 1,000 state transitions
- **S3**: $0.023 per GB per month
- **DynamoDB**: $0.25 per million read/write requests

### Cost Optimization Tips

1. Use standard Polly voices for cost savings when neural quality isn't required
2. Implement audio compression before processing
3. Use S3 Intelligent Tiering for storage optimization
4. Monitor and set billing alerts for usage tracking
5. Clean up processing artifacts regularly

## Cleanup

### Using CloudFormation
```bash
# Delete the stack (this removes all resources)
aws cloudformation delete-stack \
    --stack-name voice-processing-pipeline

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name voice-processing-pipeline \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# From the CDK directory (TypeScript or Python)
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
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup

If automated cleanup fails, manually delete:
1. S3 buckets (empty them first)
2. DynamoDB tables
3. Lambda functions
4. Step Functions state machines
5. IAM roles and policies
6. CloudWatch log groups

## Security Best Practices

- IAM roles use least privilege principles
- S3 buckets have public access blocked by default
- All data is encrypted at rest and in transit
- VPC endpoints can be configured for private connectivity
- CloudTrail logging recommended for audit trails

## Support and Troubleshooting

For issues with this infrastructure code:

1. Check the original recipe documentation for detailed explanations
2. Review AWS service documentation for specific service issues
3. Monitor CloudWatch logs for detailed error messages
4. Verify IAM permissions for all required services
5. Check service quotas and limits for your AWS account

## Advanced Customization

### Adding New Languages

To add support for additional languages:

1. Update the language mapping functions in Lambda code
2. Verify language support in Transcribe, Translate, and Polly
3. Add appropriate voice selections for new languages
4. Update the default target languages parameter

### Custom Vocabularies

To improve transcription accuracy:

1. Create custom vocabularies in Amazon Transcribe
2. Update the transcription processor to use vocabularies
3. Organize vocabularies by language and domain

### Custom Terminologies

To ensure consistent translations:

1. Create custom terminologies in Amazon Translate
2. Update the translation processor to use terminologies
3. Organize terminologies by language pairs

### Integration with Other Services

The pipeline can be extended to integrate with:
- Amazon Comprehend for sentiment analysis
- Amazon Rekognition for video processing
- Amazon Bedrock for AI-powered content enhancement
- Amazon Connect for call center integration

## Version History

- **v1.0**: Initial implementation with basic voice processing pipeline
- **v1.1**: Added support for custom vocabularies and terminologies
- **v1.2**: Enhanced error handling and monitoring capabilities
- **v1.3**: Added support for additional languages and neural voices