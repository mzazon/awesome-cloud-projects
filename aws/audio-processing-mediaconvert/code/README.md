# Infrastructure as Code for Audio Processing Pipelines with MediaConvert

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Audio Processing Pipelines with MediaConvert".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates an automated audio processing pipeline that:
- Triggers on S3 audio file uploads
- Processes audio through MediaConvert with multiple output formats
- Monitors processing through CloudWatch
- Sends notifications via SNS

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - S3 bucket creation and management
  - Lambda function creation and management
  - MediaConvert service access
  - IAM role and policy management
  - CloudWatch dashboard creation
  - SNS topic management
- Basic understanding of audio formats (MP3, AAC, FLAC, WAV)
- Estimated cost: $5-15 for testing (MediaConvert processing + S3 storage)

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name audio-processing-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
cdk bootstrap  # If first time using CDK in this account/region
cdk deploy
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
cdk bootstrap  # If first time using CDK in this account/region
cdk deploy
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Testing the Pipeline

After deployment, test the pipeline by uploading an audio file:

```bash
# Upload a test audio file to trigger processing
aws s3 cp your-audio-file.mp3 s3://your-input-bucket/

# Monitor processing logs
aws logs tail /aws/lambda/audio-processing-trigger --follow

# Check output bucket for processed files
aws s3 ls s3://your-output-bucket/ --recursive
```

## Supported Audio Formats

### Input Formats
- MP3
- WAV
- FLAC
- M4A
- AAC

### Output Formats
- **MP3**: 128kbps CBR, 44.1kHz (optimized for web streaming)
- **AAC**: 128kbps, 44.1kHz in MP4 container (mobile applications)
- **FLAC**: Lossless compression, 44.1kHz (archival storage)

## Resource Components

### Core Resources
- **S3 Buckets**: Input and output storage
- **Lambda Function**: Processing trigger and MediaConvert job orchestration
- **MediaConvert Job Template**: Standardized processing configuration
- **MediaConvert Preset**: Enhanced audio processing settings
- **IAM Roles**: Service permissions for MediaConvert and Lambda
- **CloudWatch Dashboard**: Pipeline monitoring and metrics
- **SNS Topic**: Job completion notifications

### Monitoring and Logging
- CloudWatch Logs for Lambda execution
- CloudWatch Metrics for MediaConvert jobs
- Dashboard for real-time monitoring
- SNS notifications for job status updates

## Customization Options

### Audio Quality Settings
Modify the MediaConvert job template to adjust:
- Bitrates (128kbps, 192kbps, 256kbps)
- Sample rates (44.1kHz, 48kHz, 96kHz)
- Audio normalization settings
- Codec-specific parameters

### Processing Triggers
Configure S3 event notifications for:
- Different file extensions
- Specific S3 prefixes
- Multiple input buckets

### Output Formats
Add additional output formats by modifying the job template:
- OGG Vorbis for open-source applications
- Opus for low-latency streaming
- PCM for uncompressed audio

## Security Considerations

### IAM Permissions
- Lambda functions use least-privilege IAM roles
- MediaConvert service role has minimal S3 and SNS permissions
- S3 buckets configured with appropriate access policies

### Data Protection
- S3 server-side encryption enabled by default
- VPC endpoints can be configured for private network access
- CloudTrail logging for audit compliance

## Cost Optimization

### MediaConvert Pricing
- Charges based on audio duration processed
- Multiple output formats multiply processing costs
- Consider reserved pricing for predictable workloads

### Storage Optimization
- Implement S3 lifecycle policies for output files
- Use S3 Intelligent-Tiering for cost-effective storage
- Configure S3 deletion policies for temporary processing files

## Monitoring and Troubleshooting

### CloudWatch Metrics
- **MediaConvert Jobs**: Submitted, Completed, Errored
- **Lambda Metrics**: Invocations, Duration, Errors
- **S3 Metrics**: Object counts, storage usage

### Common Issues
- **Permission Errors**: Check IAM roles and policies
- **Processing Failures**: Verify audio file format compatibility
- **Timeout Issues**: Adjust Lambda timeout for large files
- **Cost Overruns**: Monitor processing duration and output formats

### Log Analysis
```bash
# Check Lambda logs for errors
aws logs describe-log-streams \
    --log-group-name /aws/lambda/audio-processing-trigger

# Monitor MediaConvert job status
aws mediaconvert list-jobs \
    --endpoint-url https://mediaconvert.region.amazonaws.com
```

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name audio-processing-pipeline
```

### Using CDK
```bash
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Advanced Features

### Batch Processing
- Process multiple files concurrently
- Implement SQS for job queuing
- Use Step Functions for complex workflows

### Quality Analysis
- Integrate Amazon Transcribe for content analysis
- Implement automatic quality scoring
- Add metadata extraction capabilities

### Distribution Integration
- Connect to CloudFront for content delivery
- Integrate with streaming platforms
- Add webhook notifications for external systems

## Performance Optimization

### Parallel Processing
- Multiple Lambda functions for high-volume processing
- SQS FIFO queues for ordered processing
- Dead letter queues for failed jobs

### Caching Strategy
- ElastiCache for job metadata
- S3 Transfer Acceleration for large files
- CloudFront for processed audio delivery

## Compliance and Governance

### Data Residency
- Regional MediaConvert endpoints
- S3 bucket region configuration
- VPC endpoints for private processing

### Audit and Compliance
- CloudTrail integration for API logging
- Config rules for resource compliance
- Cost allocation tags for billing

## Support and Documentation

### AWS Documentation
- [MediaConvert User Guide](https://docs.aws.amazon.com/mediaconvert/)
- [Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [S3 User Guide](https://docs.aws.amazon.com/s3/)

### Troubleshooting Resources
- AWS Support cases for service issues
- MediaConvert job error codes reference
- Lambda function timeout and memory optimization

For issues with this infrastructure code, refer to the original recipe documentation or the AWS service documentation.