# Video Content Analysis with AWS Elemental MediaAnalyzer - Terraform Infrastructure

This Terraform configuration deploys a complete video content analysis solution using Amazon Rekognition, AWS Step Functions, and other AWS services. The infrastructure automatically processes video files uploaded to S3, performs content moderation and segment detection, and stores results for downstream consumption.

## Architecture Overview

The solution implements the following components:

- **S3 Buckets**: Source videos, analysis results, and temporary files
- **DynamoDB**: Job tracking and metadata storage
- **Lambda Functions**: Video processing orchestration
- **Step Functions**: Workflow coordination
- **SNS/SQS**: Event notifications and queuing
- **CloudWatch**: Monitoring and alerting
- **IAM Roles**: Secure service-to-service communication

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** >= 1.0 installed
3. **AWS IAM permissions** for creating the required resources:
   - S3 buckets and policies
   - DynamoDB tables
   - Lambda functions
   - Step Functions state machines
   - IAM roles and policies
   - SNS topics and SQS queues
   - CloudWatch dashboards and alarms

## Quick Start

### 1. Initialize Terraform

```bash
terraform init
```

### 2. Review and Customize Variables

Copy the example variables file and customize as needed:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to match your requirements:

```hcl
aws_region     = "us-east-1"
environment    = "dev"
project_name   = "video-analysis"

# Lambda configuration
lambda_timeout    = 60
lambda_memory_size = 256

# DynamoDB configuration
dynamodb_read_capacity  = 10
dynamodb_write_capacity = 10

# S3 configuration
enable_s3_versioning = true
enable_s3_encryption = true
s3_lifecycle_transition_days = 30

# Rekognition configuration
rekognition_min_confidence = 50.0

# CloudWatch configuration
enable_cloudwatch_logs = true
cloudwatch_log_retention_days = 14
```

### 3. Plan the Deployment

```bash
terraform plan
```

### 4. Deploy the Infrastructure

```bash
terraform apply
```

When prompted, type `yes` to confirm the deployment.

### 5. Verify the Deployment

After deployment, Terraform will output important information including:

- S3 bucket names
- DynamoDB table name
- Lambda function ARNs
- Step Functions state machine ARN
- CloudWatch dashboard URL
- Usage instructions

## Usage

### Upload Videos for Analysis

Upload video files to the source S3 bucket:

```bash
aws s3 cp your-video.mp4 s3://$(terraform output -raw source_bucket_name)/
```

### Monitor Processing

1. **CloudWatch Dashboard**: View real-time metrics and execution status
2. **Step Functions Console**: Monitor workflow executions
3. **DynamoDB Table**: Query job status and metadata
4. **S3 Results Bucket**: Access detailed analysis results

### Retrieve Results

Analysis results are stored in the results S3 bucket:

```bash
aws s3 ls s3://$(terraform output -raw results_bucket_name)/analysis-results/
```

Download specific results:

```bash
aws s3 cp s3://$(terraform output -raw results_bucket_name)/analysis-results/JOB_ID/results.json ./
```

## Configuration Options

### Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `project_name` | Project name for resource naming | `video-analysis` | No |
| `lambda_timeout` | Lambda function timeout (seconds) | `60` | No |
| `lambda_memory_size` | Lambda memory allocation (MB) | `256` | No |
| `aggregation_lambda_timeout` | Aggregation Lambda timeout (seconds) | `300` | No |
| `aggregation_lambda_memory_size` | Aggregation Lambda memory (MB) | `512` | No |
| `dynamodb_read_capacity` | DynamoDB read capacity units | `10` | No |
| `dynamodb_write_capacity` | DynamoDB write capacity units | `10` | No |
| `rekognition_min_confidence` | Minimum confidence for detections | `50.0` | No |
| `enable_s3_versioning` | Enable S3 bucket versioning | `true` | No |
| `enable_s3_encryption` | Enable S3 bucket encryption | `true` | No |
| `s3_lifecycle_transition_days` | Days before IA transition | `30` | No |
| `s3_lifecycle_expiration_days` | Days before expiration (0=disabled) | `0` | No |
| `enable_cloudwatch_logs` | Enable CloudWatch logging | `true` | No |
| `cloudwatch_log_retention_days` | Log retention period | `14` | No |

### Supported Video Formats

The system automatically processes these video formats:
- MP4 (.mp4)
- AVI (.avi)
- MOV (.mov)
- MKV (.mkv)
- WMV (.wmv)

## Security Considerations

The infrastructure implements several security best practices:

1. **S3 Security**:
   - Public access blocked on all buckets
   - Encryption at rest enabled
   - Secure transport required (HTTPS only)

2. **IAM Security**:
   - Least privilege principle applied
   - Service-specific roles and policies
   - No hardcoded credentials

3. **Network Security**:
   - All communication over HTTPS
   - VPC endpoints can be added for additional security

4. **Data Security**:
   - Encryption at rest for DynamoDB
   - Temporary files automatically cleaned up

## Monitoring and Troubleshooting

### CloudWatch Metrics

The solution provides comprehensive monitoring through:

- **Lambda Metrics**: Duration, errors, invocations
- **Step Functions Metrics**: Execution success/failure rates
- **DynamoDB Metrics**: Capacity consumption
- **S3 Metrics**: Object counts and storage usage

### Alarms

Pre-configured alarms monitor:

- Step Functions execution failures
- Lambda function errors
- DynamoDB throttling events

### Troubleshooting Common Issues

1. **Lambda Timeouts**:
   - Increase `lambda_timeout` or `aggregation_lambda_timeout`
   - Monitor CloudWatch logs for performance bottlenecks

2. **DynamoDB Throttling**:
   - Increase `dynamodb_read_capacity` or `dynamodb_write_capacity`
   - Consider enabling auto-scaling

3. **Rekognition Errors**:
   - Verify video format compatibility
   - Check IAM permissions for Rekognition services
   - Monitor service limits and quotas

## Cost Optimization

### Strategies

1. **S3 Lifecycle Management**:
   - Configure appropriate transition days
   - Set expiration policies for temporary files
   - Use S3 Intelligent-Tiering for variable access patterns

2. **Lambda Optimization**:
   - Right-size memory allocation
   - Optimize function code for performance
   - Use provisioned concurrency for predictable workloads

3. **DynamoDB Optimization**:
   - Monitor capacity utilization
   - Consider on-demand billing for variable workloads
   - Use DynamoDB auto-scaling

### Cost Estimation

Approximate monthly costs for processing 100 hours of video:

- **S3 Storage**: $5-10 (depends on retention)
- **Lambda Compute**: $10-15
- **DynamoDB**: $5-10
- **Rekognition**: $300-500 (primary cost driver)
- **Other Services**: $5-10

**Total**: ~$325-545/month for 100 hours of video analysis

## Cleanup

To remove all resources and avoid ongoing charges:

```bash
# Empty S3 buckets first (required for deletion)
aws s3 rm s3://$(terraform output -raw source_bucket_name) --recursive
aws s3 rm s3://$(terraform output -raw results_bucket_name) --recursive  
aws s3 rm s3://$(terraform output -raw temp_bucket_name) --recursive

# Destroy the infrastructure
terraform destroy
```

## Advanced Configuration

### Custom Rekognition Models

To use custom Rekognition models:

1. Deploy your custom model
2. Update the Lambda function code to reference the custom model
3. Ensure IAM permissions include access to the custom model

### Integration with Other Services

The solution can be extended to integrate with:

- **Amazon Transcribe**: For audio transcription
- **Amazon Comprehend**: For sentiment analysis
- **Amazon Translate**: For multi-language support
- **Amazon ElasticSearch**: For searchable metadata

### High Availability

For production deployments:

1. Deploy across multiple AZs
2. Use DynamoDB Global Tables for multi-region
3. Implement S3 Cross-Region Replication
4. Add CloudFront for global content delivery

## Support

For issues with this infrastructure:

1. Check CloudWatch logs for error details
2. Review AWS service limits and quotas
3. Consult the AWS documentation for service-specific guidance
4. Consider AWS Support for production issues

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Please review and adapt for your specific security and compliance requirements before using in production environments.