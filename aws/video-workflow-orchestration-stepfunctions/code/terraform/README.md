# Video Workflow Orchestration Terraform Infrastructure

This Terraform configuration deploys a comprehensive video processing workflow orchestration system on AWS using Step Functions, MediaConvert, Lambda, and supporting services.

## Architecture Overview

The infrastructure creates a serverless video processing pipeline that:

- **Automatically triggers** when videos are uploaded to S3
- **Orchestrates processing** using Step Functions state machines
- **Transcodes videos** using AWS MediaConvert
- **Validates quality** through automated quality control checks
- **Publishes content** with notifications and monitoring
- **Provides APIs** for programmatic workflow triggering

## Infrastructure Components

### Core Services
- **AWS Step Functions**: Workflow orchestration and state management
- **AWS MediaConvert**: Video transcoding and format conversion
- **AWS Lambda**: Serverless compute for workflow tasks
- **Amazon S3**: Storage for source, output, and archived videos
- **Amazon DynamoDB**: Job tracking and metadata storage
- **Amazon SNS**: Notifications for workflow completion

### Supporting Services
- **API Gateway**: HTTP API for workflow triggering
- **CloudWatch**: Monitoring, logging, and dashboards
- **IAM**: Security roles and policies
- **AWS Budgets**: Cost monitoring and alerts (optional)

## Prerequisites

Before deploying this infrastructure, ensure you have:

### Required Tools
- **Terraform >= 1.0**: Infrastructure as Code tool
- **AWS CLI v2**: Command-line interface for AWS
- **Python 3.9+**: For Lambda function development (if customizing)

### AWS Requirements
- **AWS Account**: With appropriate permissions
- **AWS CLI Configuration**: Run `aws configure` to set up credentials
- **IAM Permissions**: The deploying user/role needs permissions for:
  - Step Functions, Lambda, MediaConvert, S3, DynamoDB
  - SNS, API Gateway, CloudWatch, IAM
  - Budgets (if cost monitoring is enabled)

### Cost Considerations
- **Estimated Monthly Cost**: $50-150 for moderate usage
- **Variable Costs**: MediaConvert pricing based on video duration and complexity
- **Storage Costs**: S3 storage for source, output, and archived videos
- **Compute Costs**: Lambda execution time and Step Functions state transitions

## Deployment Guide

### 1. Clone and Navigate to Terraform Directory

```bash
# Navigate to the Terraform configuration directory
cd aws/automated-video-workflow-orchestration-step-functions/code/terraform/
```

### 2. Configure Variables

Create a `terraform.tfvars` file to customize your deployment:

```hcl
# Basic Configuration
aws_region                = "us-east-1"
environment              = "prod"
project_name             = "video-workflow"
notification_email       = "your-email@example.com"

# Feature Toggles
enable_api_gateway       = true
enable_s3_triggers       = true
enable_cloudwatch_dashboard = true
enable_cost_alerts       = true

# Lambda Configuration
lambda_timeout           = 300
lambda_memory_size       = 512

# DynamoDB Configuration
dynamodb_billing_mode    = "PAY_PER_REQUEST"

# S3 Configuration
s3_force_destroy         = false
enable_s3_versioning     = true

# Step Functions Configuration
step_functions_type      = "EXPRESS"

# MediaConvert Configuration
mediaconvert_queue_priority = 0

# Video Processing Configuration
video_file_extensions    = ["mp4", "mov", "avi", "mkv"]
quality_threshold        = 0.8

# Cost Monitoring
monthly_cost_threshold   = 100.0
```

### 3. Initialize Terraform

```bash
# Initialize Terraform and download providers
terraform init
```

### 4. Plan Deployment

```bash
# Review the planned changes
terraform plan
```

### 5. Deploy Infrastructure

```bash
# Deploy the infrastructure
terraform apply

# Confirm deployment when prompted
# Type 'yes' to proceed
```

### 6. Verify Deployment

After successful deployment, verify the infrastructure:

```bash
# Check Step Functions state machine
aws stepfunctions describe-state-machine --state-machine-arn $(terraform output -raw step_functions_state_machine_arn)

# List Lambda functions
aws lambda list-functions --query "Functions[?contains(FunctionName, 'video-workflow')].FunctionName"

# Check S3 buckets
aws s3 ls | grep video-workflow

# Verify DynamoDB table
aws dynamodb describe-table --table-name $(terraform output -raw jobs_table_name)
```

## Usage Examples

### 1. Automatic Processing (S3 Upload)

Upload a video file to trigger automatic processing:

```bash
# Get source bucket name
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)

# Upload a video file
aws s3 cp your-video.mp4 s3://${SOURCE_BUCKET}/

# Monitor workflow execution
aws stepfunctions list-executions --state-machine-arn $(terraform output -raw step_functions_state_machine_arn)
```

### 2. API-Triggered Processing

Use the API Gateway endpoint to trigger processing:

```bash
# Get API endpoint
API_ENDPOINT=$(terraform output -raw workflow_trigger_endpoint)

# Trigger workflow via API
curl -X POST $API_ENDPOINT \
  -H "Content-Type: application/json" \
  -d '{
    "bucket": "'$(terraform output -raw source_bucket_name)'",
    "key": "your-video.mp4"
  }'
```

### 3. Monitor Workflow Progress

```bash
# Check recent executions
aws stepfunctions list-executions \
  --state-machine-arn $(terraform output -raw step_functions_state_machine_arn) \
  --max-results 10

# Check job status in DynamoDB
aws dynamodb scan \
  --table-name $(terraform output -raw jobs_table_name) \
  --limit 10 \
  --query 'Items[].{JobId:JobId.S,Status:JobStatus.S,CreatedAt:CreatedAt.S}'

# View CloudWatch logs
aws logs describe-log-streams \
  --log-group-name $(terraform output -raw step_functions_logs_group)
```

### 4. Check Processing Outputs

```bash
# List processed outputs
OUTPUT_BUCKET=$(terraform output -raw output_bucket_name)

# Check MP4 outputs
aws s3 ls s3://${OUTPUT_BUCKET}/mp4/ --recursive

# Check HLS outputs
aws s3 ls s3://${OUTPUT_BUCKET}/hls/ --recursive

# Check thumbnails
aws s3 ls s3://${OUTPUT_BUCKET}/thumbnails/ --recursive
```

## Configuration Options

### Variable Reference

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `aws_region` | string | "us-east-1" | AWS region for deployment |
| `environment` | string | "dev" | Environment name (dev, staging, prod) |
| `project_name` | string | "video-workflow" | Project name for resource naming |
| `notification_email` | string | "" | Email for workflow notifications |
| `enable_api_gateway` | bool | true | Enable API Gateway for triggering |
| `enable_s3_triggers` | bool | true | Enable automatic S3 event triggers |
| `lambda_timeout` | number | 300 | Lambda function timeout (seconds) |
| `lambda_memory_size` | number | 512 | Lambda function memory (MB) |
| `quality_threshold` | number | 0.8 | Minimum quality score for publishing |
| `step_functions_type` | string | "EXPRESS" | Step Functions type (STANDARD/EXPRESS) |

### Environment-Specific Configurations

**Development Environment:**
```hcl
environment = "dev"
dynamodb_billing_mode = "PAY_PER_REQUEST"
step_functions_type = "EXPRESS"
enable_cost_alerts = false
s3_force_destroy = true
```

**Production Environment:**
```hcl
environment = "prod"
dynamodb_billing_mode = "PROVISIONED"
step_functions_type = "STANDARD"
enable_cost_alerts = true
s3_force_destroy = false
enable_s3_versioning = true
```

## Monitoring and Troubleshooting

### CloudWatch Dashboard

If enabled, access the monitoring dashboard:
```bash
# Get dashboard URL
terraform output cloudwatch_dashboard_url
```

The dashboard includes:
- Step Functions execution metrics
- MediaConvert job statistics
- Lambda function performance
- Recent workflow execution logs

### Common Issues and Solutions

**1. MediaConvert Job Failures**
```bash
# Check MediaConvert jobs
aws mediaconvert list-jobs --max-results 10

# Check specific job details
aws mediaconvert get-job --id JOB_ID
```

**2. Lambda Function Errors**
```bash
# Check Lambda function logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/FUNCTION_NAME \
  --start-time $(date -d '1 hour ago' +%s)000
```

**3. Step Functions Execution Failures**
```bash
# Get execution details
aws stepfunctions describe-execution --execution-arn EXECUTION_ARN

# Get execution history
aws stepfunctions get-execution-history --execution-arn EXECUTION_ARN
```

**4. DynamoDB Job Tracking Issues**
```bash
# Query jobs by status
aws dynamodb query \
  --table-name $(terraform output -raw jobs_table_name) \
  --index-name CreatedAtIndex \
  --key-condition-expression "CreatedAt = :date" \
  --expression-attribute-values '{":date":{"S":"2024-01-01"}}'
```

### Performance Optimization

**1. Lambda Function Optimization**
- Adjust memory allocation based on processing requirements
- Monitor duration and cold start metrics
- Consider provisioned concurrency for high-frequency triggers

**2. Step Functions Cost Optimization**
- Use Express Workflows for high-volume, short-duration executions
- Minimize state transitions by combining related operations
- Implement efficient retry and error handling

**3. MediaConvert Optimization**
- Choose appropriate instance types based on workload
- Optimize encoding settings for quality vs. speed trade-offs
- Use queue priorities for urgent vs. batch processing

## Security Considerations

### IAM Policies
- All IAM roles follow the principle of least privilege
- Service-specific roles with minimal required permissions
- No cross-account access unless explicitly configured

### Data Encryption
- S3 buckets use server-side encryption (AES-256)
- DynamoDB tables have encryption at rest enabled
- SNS topics use AWS managed KMS encryption

### Network Security
- All resources deployed in default VPC with security groups
- API Gateway includes CORS configuration
- S3 buckets block public access by default

### Access Control
- S3 bucket policies restrict access to workflow resources
- Lambda functions can only access required services
- Step Functions execution role limited to necessary actions

## Cost Management

### Cost Optimization Strategies

**1. Storage Optimization**
- S3 lifecycle policies for archive bucket
- Intelligent tiering for infrequently accessed content
- Regular cleanup of temporary processing files

**2. Compute Optimization**
- Right-size Lambda function memory allocation
- Use Express Workflows for cost-effective orchestration
- Monitor and optimize MediaConvert instance usage

**3. Monitoring and Alerts**
- Enable AWS Budgets for cost tracking
- Set up billing alerts for unexpected usage
- Regular cost analysis and optimization reviews

### Sample Cost Breakdown

For moderate usage (100 videos/month, 2GB average):

| Service | Monthly Cost | Notes |
|---------|--------------|-------|
| MediaConvert | $30-50 | Based on video duration/complexity |
| Step Functions | $5-10 | Express Workflows, state transitions |
| Lambda | $5-15 | Execution time and memory usage |
| S3 Storage | $10-20 | Source, output, and archive storage |
| DynamoDB | $2-5 | Pay-per-request or provisioned |
| Other Services | $3-8 | SNS, API Gateway, CloudWatch |
| **Total** | **$55-108** | Varies with usage patterns |

## Backup and Disaster Recovery

### Data Protection
- S3 versioning enabled for source bucket
- DynamoDB point-in-time recovery enabled
- Regular testing of restore procedures

### Multi-Region Considerations
- Consider cross-region replication for critical content
- Implement region-specific MediaConvert endpoints
- Plan for service availability during regional outages

## Cleanup and Destruction

### Temporary Cleanup
```bash
# Remove test files from buckets
aws s3 rm s3://$(terraform output -raw source_bucket_name)/ --recursive
aws s3 rm s3://$(terraform output -raw output_bucket_name)/ --recursive
aws s3 rm s3://$(terraform output -raw archive_bucket_name)/ --recursive
```

### Complete Infrastructure Removal
```bash
# Destroy all infrastructure (irreversible)
terraform destroy

# Confirm destruction when prompted
# Type 'yes' to proceed
```

**Warning**: This will permanently delete all resources and data. Ensure you have backups of any important content before running `terraform destroy`.

## Support and Maintenance

### Regular Maintenance Tasks
- Monitor CloudWatch metrics and logs
- Review and update Lambda function code as needed
- Update Terraform provider versions regularly
- Review and optimize costs monthly

### Getting Help
- Check AWS documentation for service-specific issues
- Review Terraform AWS provider documentation
- Monitor AWS service health dashboard
- Consider AWS Support plans for production workloads

## Contributing

To contribute improvements to this infrastructure:

1. Fork the repository
2. Create a feature branch
3. Make your changes and test thoroughly
4. Submit a pull request with detailed description
5. Ensure all Terraform formatting is correct (`terraform fmt`)

## License

This infrastructure code is provided as-is under the MIT License. See the LICENSE file for details.