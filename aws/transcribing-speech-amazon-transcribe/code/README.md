# Infrastructure as Code for Transcribing Speech with Amazon Transcribe

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Transcribing Speech with Amazon Transcribe".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Transcribe (all actions)
  - S3 (bucket creation, object operations)
  - IAM (role and policy creation)
  - Lambda (function creation and execution)
- Sample audio files in supported formats (MP3, WAV, FLAC, or MP4)
- Estimated cost: $0.10-$2.00 per hour of audio transcribed (varies by features)

## Architecture Overview

This solution deploys a comprehensive speech recognition platform using Amazon Transcribe with the following components:

- **S3 Bucket**: Stores audio files, transcription outputs, and custom vocabularies
- **Custom Vocabularies**: Improves accuracy for domain-specific terminology
- **Vocabulary Filters**: Provides content filtering and PII redaction
- **IAM Roles**: Secure service-to-service authentication
- **Lambda Functions**: Real-time processing of transcription results
- **Batch Processing**: Handles pre-recorded audio files
- **Streaming Support**: Real-time transcription capabilities

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name transcribe-speech-recognition \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=BucketName,ParameterValue=transcribe-demo-$(date +%s) \
        ParameterKey=VocabularyName,ParameterValue=custom-vocab-$(date +%s)

# Wait for deployment completion
aws cloudformation wait stack-create-complete \
    --stack-name transcribe-speech-recognition

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name transcribe-speech-recognition \
    --query 'Stacks[0].Outputs' --output table
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# Get stack outputs
cdk list --long
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# Get stack outputs
cdk list --long
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
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts and monitor deployment progress
```

## Usage Examples

### 1. Upload Audio Files

```bash
# Get bucket name from stack outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name transcribe-speech-recognition \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text)

# Upload your audio file
aws s3 cp your-audio-file.mp3 s3://${BUCKET_NAME}/audio-input/
```

### 2. Start Batch Transcription Job

```bash
# Create transcription job
aws transcribe start-transcription-job \
    --transcription-job-name "my-transcription-$(date +%s)" \
    --language-code en-US \
    --media-format mp3 \
    --media MediaFileUri=s3://${BUCKET_NAME}/audio-input/your-audio-file.mp3 \
    --output-bucket-name ${BUCKET_NAME} \
    --output-key transcription-output/results.json
```

### 3. Monitor Job Status

```bash
# Check job status
aws transcribe get-transcription-job \
    --transcription-job-name "my-transcription-$(date +%s)" \
    --query 'TranscriptionJob.{Status:TranscriptionJobStatus,OutputUri:Transcript.TranscriptFileUri}'
```

### 4. Advanced Features

#### Custom Vocabulary

```bash
# Get vocabulary name from outputs
VOCABULARY_NAME=$(aws cloudformation describe-stacks \
    --stack-name transcribe-speech-recognition \
    --query 'Stacks[0].Outputs[?OutputKey==`VocabularyName`].OutputValue' \
    --output text)

# Start job with custom vocabulary
aws transcribe start-transcription-job \
    --transcription-job-name "custom-vocab-job-$(date +%s)" \
    --language-code en-US \
    --media-format mp3 \
    --media MediaFileUri=s3://${BUCKET_NAME}/audio-input/your-audio-file.mp3 \
    --output-bucket-name ${BUCKET_NAME} \
    --settings VocabularyName=${VOCABULARY_NAME}
```

#### Speaker Identification

```bash
# Start job with speaker diarization
aws transcribe start-transcription-job \
    --transcription-job-name "speaker-id-job-$(date +%s)" \
    --language-code en-US \
    --media-format mp3 \
    --media MediaFileUri=s3://${BUCKET_NAME}/audio-input/your-audio-file.mp3 \
    --output-bucket-name ${BUCKET_NAME} \
    --settings ShowSpeakerLabels=true,MaxSpeakerLabels=4
```

#### PII Redaction

```bash
# Start job with PII redaction
aws transcribe start-transcription-job \
    --transcription-job-name "pii-redaction-job-$(date +%s)" \
    --language-code en-US \
    --media-format mp3 \
    --media MediaFileUri=s3://${BUCKET_NAME}/audio-input/your-audio-file.mp3 \
    --output-bucket-name ${BUCKET_NAME} \
    --content-redaction RedactionType=PII,RedactionOutput=redacted_and_unredacted
```

## Configuration

### Customizable Parameters

The following parameters can be customized during deployment:

- **BucketName**: Name for the S3 bucket (must be globally unique)
- **VocabularyName**: Name for the custom vocabulary
- **VocabularyFilterName**: Name for the vocabulary filter
- **LanguageCode**: Primary language for transcription (default: en-US)
- **Region**: AWS region for deployment
- **EnableLogging**: Enable CloudWatch logging (default: true)

### Environment Variables

For bash script deployment, set these environment variables:

```bash
export AWS_REGION=us-east-1
export BUCKET_NAME=transcribe-demo-$(date +%s)
export VOCABULARY_NAME=custom-vocab-$(date +%s)
export ENABLE_ADVANCED_FEATURES=true
```

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor transcription job execution through CloudWatch:

```bash
# View Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix /aws/lambda/transcribe-processor

# Stream logs in real-time
aws logs tail /aws/lambda/transcribe-processor-function --follow
```

### Common Issues

1. **Audio Format Not Supported**: Ensure your audio files are in supported formats (MP3, WAV, FLAC, MP4)
2. **Insufficient Permissions**: Verify IAM roles have required permissions for Transcribe, S3, and Lambda
3. **Custom Vocabulary Not Ready**: Wait for vocabulary to reach "READY" state before using in jobs
4. **Job Failure**: Check CloudWatch logs for detailed error messages

### Performance Optimization

- Use appropriate audio quality (16 kHz sample rate recommended)
- Implement audio preprocessing to reduce background noise
- Use streaming transcription for real-time applications
- Enable partial results for better user experience

## Cost Optimization

### Pricing Considerations

- **Standard Transcription**: ~$0.024 per minute
- **Custom Vocabularies**: No additional charge
- **Speaker Identification**: ~$0.024 per minute (additional)
- **PII Redaction**: ~$0.024 per minute (additional)
- **Custom Language Models**: ~$0.048 per minute

### Cost Reduction Strategies

1. **Batch Processing**: Group multiple files for efficient processing
2. **Audio Preprocessing**: Clean audio reduces processing time
3. **Selective Features**: Only enable advanced features when needed
4. **Regional Optimization**: Deploy in regions closest to audio sources

## Security

### Data Protection

- All audio files encrypted at rest in S3
- Transcription results encrypted during processing
- IAM roles follow principle of least privilege
- PII redaction available for sensitive content

### Access Control

- S3 bucket policies restrict access to authorized services
- Lambda execution roles limited to required resources
- CloudWatch logs encrypted for audit trails

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name transcribe-speech-recognition

# Wait for deletion completion
aws cloudformation wait stack-delete-complete \
    --stack-name transcribe-speech-recognition
```

### Using CDK (AWS)

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy --force
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Advanced Configuration

### Real-time Streaming

For real-time transcription applications:

```bash
# Enable streaming configuration
aws transcribe start-stream-transcription \
    --language-code en-US \
    --media-sample-rate-hertz 44100 \
    --media-encoding pcm
```

### Custom Language Models

For specialized domains requiring custom language models:

```bash
# Create custom language model
aws transcribe create-language-model \
    --language-code en-US \
    --base-model-name WideBand \
    --model-name my-custom-model \
    --input-data-config S3Uri=s3://${BUCKET_NAME}/training-data/
```

## Integration Examples

### Lambda Integration

Process transcription results automatically:

```python
import json
import boto3

def lambda_handler(event, context):
    transcribe = boto3.client('transcribe')
    
    # Process completed transcription
    job_name = event['jobName']
    response = transcribe.get_transcription_job(
        TranscriptionJobName=job_name
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps('Transcription processed')
    }
```

### API Gateway Integration

Expose transcription functionality via REST API:

```yaml
Resources:
  TranscriptionApi:
    Type: AWS::ApiGateway::RestApi
    Properties:
      Name: TranscriptionAPI
      Description: API for transcription services
```

## Support

For issues with this infrastructure code, refer to:

1. **Original Recipe Documentation**: Detailed implementation guide
2. **AWS Transcribe Documentation**: [https://docs.aws.amazon.com/transcribe/](https://docs.aws.amazon.com/transcribe/)
3. **AWS Support**: For service-specific issues
4. **Community Resources**: AWS forums and Stack Overflow

## Contributing

To contribute improvements to this infrastructure code:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit a pull request with detailed description

## License

This infrastructure code is provided under the same license as the original recipe.