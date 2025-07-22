# Audio Processing Pipeline with AWS Elemental MediaConvert - Terraform

This Terraform configuration deploys a complete audio processing pipeline using AWS Elemental MediaConvert, S3, Lambda, and CloudWatch. The pipeline automatically processes audio files uploaded to an S3 bucket and converts them to multiple formats (MP3, AAC, FLAC) with professional audio enhancement.

## Architecture Overview

The solution creates an event-driven architecture that:

1. **S3 Input Bucket**: Receives audio files and triggers processing
2. **Lambda Function**: Orchestrates MediaConvert jobs when files are uploaded
3. **MediaConvert**: Processes audio files with multiple output formats
4. **S3 Output Bucket**: Stores processed audio files organized by format
5. **CloudWatch**: Provides monitoring and logging capabilities
6. **SNS**: Sends notifications about processing status

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for:
  - S3 (bucket management, object operations)
  - Lambda (function management, execution)
  - MediaConvert (job template and preset management)
  - IAM (role and policy management)
  - CloudWatch (dashboard and log management)
  - SNS (topic management)
  - KMS (key management for encryption)

## Quick Start

### 1. Initialize Terraform

```bash
terraform init
```

### 2. Review and Customize Variables

Copy the example variables file and customize as needed:

```bash
# Review available variables
terraform plan

# Or create a terraform.tfvars file
cat > terraform.tfvars << EOF
aws_region = "us-east-1"
environment = "dev"
project_name = "my-audio-pipeline"
notification_email = "admin@example.com"
EOF
```

### 3. Deploy the Infrastructure

```bash
# Preview changes
terraform plan

# Apply changes
terraform apply
```

### 4. Test the Pipeline

Upload an audio file to the input bucket:

```bash
# Get bucket name from output
INPUT_BUCKET=$(terraform output -raw input_bucket_name)

# Upload test file
aws s3 cp your-audio-file.mp3 s3://${INPUT_BUCKET}/

# Monitor processing
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow
```

## Configuration Options

### Audio Processing Settings

| Variable | Description | Default | Valid Range |
|----------|-------------|---------|-------------|
| `audio_bitrate_mp3` | MP3 output bitrate (bps) | 128000 | 32000-320000 |
| `audio_bitrate_aac` | AAC output bitrate (bps) | 128000 | 32000-256000 |
| `audio_sample_rate` | Sample rate (Hz) | 44100 | 22050, 44100, 48000, 96000 |
| `audio_channels` | Number of audio channels | 2 | 1-8 |
| `loudness_target_lkfs` | Target loudness (LKFS) | -23.0 | -50.0 to 0.0 |

### Infrastructure Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `s3_versioning_enabled` | Enable S3 bucket versioning | true |
| `s3_encryption_enabled` | Enable S3 server-side encryption | true |
| `lambda_timeout` | Lambda timeout (seconds) | 300 |
| `lambda_memory_size` | Lambda memory (MB) | 128 |
| `cloudwatch_log_retention_days` | Log retention period | 14 |

### Security Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_s3_access_logging` | Enable S3 access logging | true |
| `enable_s3_public_access_block` | Block public S3 access | true |
| `kms_key_deletion_window` | KMS key deletion window (days) | 7 |

## Supported Audio Formats

The pipeline supports the following input formats:
- MP3 (.mp3)
- WAV (.wav)
- FLAC (.flac)
- M4A (.m4a)
- AAC (.aac)

Output formats generated:
- **MP3**: Web-optimized, standard quality
- **AAC**: Mobile-optimized, high efficiency
- **FLAC**: Lossless, archival quality

## Monitoring and Troubleshooting

### CloudWatch Dashboard

Access the monitoring dashboard:

```bash
# Get dashboard URL
terraform output cloudwatch_dashboard_url
```

### Lambda Logs

Monitor function execution:

```bash
# Get recent logs
aws logs describe-log-streams \
    --log-group-name "$(terraform output -raw lambda_log_group_name)" \
    --order-by LastEventTime --descending

# Tail logs in real-time
aws logs tail "$(terraform output -raw lambda_log_group_name)" --follow
```

### MediaConvert Jobs

Check job status:

```bash
# List recent jobs
aws mediaconvert list-jobs \
    --endpoint-url "$(terraform output -raw mediaconvert_endpoint)" \
    --max-results 10

# Get specific job details
aws mediaconvert get-job \
    --endpoint-url "$(terraform output -raw mediaconvert_endpoint)" \
    --id JOB_ID
```

### Common Issues

1. **Files not processing**: Check Lambda logs for errors
2. **MediaConvert job failures**: Verify audio file format and codec
3. **Permission errors**: Ensure IAM roles have required permissions
4. **S3 event issues**: Verify bucket notification configuration

## Cost Optimization

### Estimated Costs

- **S3 Storage**: ~$0.023 per GB per month
- **Lambda Invocations**: ~$0.0000002 per invocation
- **MediaConvert Processing**: ~$0.0075 per minute of audio
- **CloudWatch Logs**: ~$0.50 per GB ingested
- **SNS Notifications**: ~$0.50 per million notifications

### Optimization Tips

1. **S3 Lifecycle Policies**: Transition old files to cheaper storage classes
2. **Log Retention**: Set appropriate CloudWatch log retention periods
3. **Audio Settings**: Optimize bitrates and sample rates for your use case
4. **Batch Processing**: Group multiple files for processing efficiency

## Security Best Practices

This configuration implements several security measures:

- **Encryption**: S3 buckets encrypted with customer-managed KMS keys
- **Access Control**: IAM roles with least-privilege permissions
- **Network Security**: Public access blocked on S3 buckets
- **Logging**: Comprehensive audit logging enabled
- **Monitoring**: CloudWatch dashboards for operational visibility

## Customization Examples

### Custom Audio Preset

Add additional audio processing options:

```hcl
# In variables.tf
variable "enable_noise_reduction" {
  description = "Enable noise reduction processing"
  type        = bool
  default     = false
}

# In main.tf - modify preset settings
resource "aws_media_convert_preset" "enhanced_audio" {
  # ... existing configuration
  
  settings_json = jsonencode({
    # ... existing settings
    AudioDescriptions = [
      {
        # ... existing audio description
        AudioNormalizationSettings = {
          # ... existing normalization
          NoiseReducerSettings = var.enable_noise_reduction ? {
            Filter = "AUTO"
            FilterSettings = {
              Strength = "MEDIUM"
            }
          } : null
        }
      }
    ]
  })
}
```

### Multi-Region Deployment

Deploy to multiple regions for global processing:

```hcl
# providers.tf
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}

# main.tf
module "audio_pipeline_us" {
  source = "./modules/audio-pipeline"
  providers = {
    aws = aws.us_east_1
  }
  # ... configuration
}

module "audio_pipeline_eu" {
  source = "./modules/audio-pipeline"
  providers = {
    aws = aws.eu_west_1
  }
  # ... configuration
}
```

## Cleanup

To remove all resources:

```bash
# Destroy infrastructure
terraform destroy

# Verify cleanup
aws s3 ls | grep audio-processing
aws lambda list-functions | grep audio-processing
```

## Advanced Features

### Batch Processing

For high-volume processing, consider:

- **SQS Integration**: Queue files for batch processing
- **Step Functions**: Complex workflow orchestration
- **EventBridge**: Advanced event routing and filtering

### Content Analysis

Extend with AI/ML services:

- **Amazon Transcribe**: Speech-to-text conversion
- **Amazon Comprehend**: Content analysis and sentiment
- **Amazon Rekognition**: Audio content classification

### Integration Patterns

Connect with other systems:

- **API Gateway**: REST API for file uploads
- **AppSync**: GraphQL API for real-time updates
- **DynamoDB**: Metadata storage and indexing

## Support and Troubleshooting

### Useful Commands

```bash
# Check resource status
terraform state list
terraform state show aws_lambda_function.audio_processor

# Validate configuration
terraform validate
terraform fmt -check

# Import existing resources
terraform import aws_s3_bucket.input existing-bucket-name
```

### Common Terraform Issues

1. **State Lock**: If deployment fails, check for state locks
2. **Resource Dependencies**: Ensure proper resource ordering
3. **Provider Versions**: Keep providers updated for latest features
4. **Permissions**: Verify Terraform has necessary AWS permissions

For additional support, refer to:
- [AWS MediaConvert Documentation](https://docs.aws.amazon.com/mediaconvert/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)

## Contributing

To contribute improvements to this Terraform configuration:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit a pull request with detailed description

## License

This Terraform configuration is provided as-is under the MIT License. See the original recipe documentation for more details.