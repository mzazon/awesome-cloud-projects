# Terraform Infrastructure for IoT Firmware Updates

This Terraform configuration deploys the complete infrastructure for AWS IoT firmware updates using Device Management Jobs, as described in the recipe "IoT Firmware Updates with Device Management Jobs".

## Architecture Overview

This infrastructure creates:

- **S3 Bucket**: Secure storage for firmware files with versioning and encryption
- **IoT Resources**: Thing Groups and Things for device organization and targeting
- **IAM Roles**: Least-privilege roles for IoT Jobs and Lambda execution
- **Lambda Function**: Serverless orchestration for firmware update workflows
- **AWS Signer**: Code signing profile for firmware integrity verification
- **CloudWatch**: Monitoring dashboard and log management
- **Sample Resources**: Test device and firmware for validation

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for:
  - S3 (bucket creation and management)
  - IoT Core (things, thing groups, jobs)
  - IAM (role and policy management)
  - Lambda (function creation and execution)
  - AWS Signer (signing profile management)
  - CloudWatch (dashboard and log group creation)

## Quick Start

1. **Clone and Navigate**:
   ```bash
   git clone <repository>
   cd aws/iot-firmware-updates-device-management-jobs/code/terraform
   ```

2. **Configure Variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific configuration
   ```

3. **Initialize and Deploy**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Test the Deployment**:
   ```bash
   # Use the output CLI commands to test the infrastructure
   terraform output cli_commands
   ```

## Configuration

### Required Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region for deployment | `us-east-1` |
| `environment` | Environment name | `dev` |
| `project_name` | Project name for resource naming | `iot-firmware-updates` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `signing_platform_id` | AWS Signer platform ID | `AmazonFreeRTOS-TI-CC3220SF` |
| `lambda_timeout` | Lambda timeout in seconds | `300` |
| `enable_s3_versioning` | Enable S3 bucket versioning | `true` |
| `create_sample_device` | Create test IoT device | `true` |
| `create_cloudwatch_dashboard` | Create monitoring dashboard | `true` |

See `terraform.tfvars.example` for all available configuration options.

## Testing the Infrastructure

After deployment, test the firmware update workflow:

### 1. Create a Firmware Update Job

```bash
# Get the test payload from Terraform outputs
terraform output lambda_test_payload_create_job

# Invoke the Lambda function
aws lambda invoke \
    --function-name $(terraform output -raw lambda_function_name) \
    --payload "$(terraform output -raw lambda_test_payload_create_job | base64)" \
    response.json

# Check the response
cat response.json
```

### 2. Monitor Job Progress

```bash
# Extract job ID from the response
JOB_ID=$(cat response.json | jq -r '.body' | jq -r '.job_id')

# Check job status
aws lambda invoke \
    --function-name $(terraform output -raw lambda_function_name) \
    --payload "{\"action\":\"check_job_status\",\"job_id\":\"$JOB_ID\"}" \
    status.json

cat status.json
```

### 3. View CloudWatch Dashboard

```bash
# Get the dashboard URL
terraform output cloudwatch_dashboard_url

# Or view via CLI
aws cloudwatch get-dashboard \
    --dashboard-name $(terraform output -raw cloudwatch_dashboard_name)
```

### 4. Download and Verify Firmware

```bash
# Download the sample firmware
aws s3 cp \
    "s3://$(terraform output -raw firmware_bucket_name)/$(terraform output -raw sample_firmware_s3_key)" \
    ./test_firmware.bin

# Verify the download
ls -la test_firmware.bin
```

## Security Features

### S3 Security
- Server-side encryption (AES-256 or KMS)
- Public access blocked
- Bucket versioning for rollback capability
- IAM-based access control

### IAM Security
- Least-privilege principle
- Service-specific trust policies
- Resource-specific permissions
- No wildcard permissions

### IoT Security
- Device certificates for authentication
- Thing Groups for targeted updates
- Secure MQTT communication
- Job execution controls

### Code Signing
- AWS Signer integration
- Firmware integrity verification
- Configurable signature validity
- Support for multiple platforms

## Monitoring and Logging

### CloudWatch Dashboard
The dashboard provides real-time visibility into:
- IoT Jobs status metrics
- Lambda function performance
- Recent execution logs
- Error rates and trends

### Log Management
- Lambda execution logs in CloudWatch
- Configurable log retention periods
- Structured logging for troubleshooting
- Integration with AWS X-Ray (optional)

## Customization

### Device Types
To support different device types, modify the `signing_platform_id` variable:

```hcl
# For different FreeRTOS devices
signing_platform_id = "AmazonFreeRTOS-Default"

# For AWS Lambda-based devices
signing_platform_id = "AWSLambda-SHA384-ECDSA"
```

### Rollout Configuration
Customize job execution parameters:

```hcl
# Conservative rollout
job_rollout_max_per_minute = 5
job_rollout_base_rate_per_minute = 2
job_abort_failure_threshold = 10.0

# Aggressive rollout
job_rollout_max_per_minute = 100
job_rollout_base_rate_per_minute = 20
job_abort_failure_threshold = 30.0
```

### Environment-Specific Configuration
Use different configurations per environment:

```bash
# Development
terraform apply -var-file="dev.tfvars"

# Staging
terraform apply -var-file="staging.tfvars"

# Production
terraform apply -var-file="prod.tfvars"
```

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   ```bash
   # Verify AWS credentials
   aws sts get-caller-identity
   
   # Check IAM permissions
   aws iam get-user
   ```

2. **Lambda Function Errors**:
   ```bash
   # Check function logs
   aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"
   
   # View recent logs
   aws logs filter-log-events \
       --log-group-name "/aws/lambda/$(terraform output -raw lambda_function_name)" \
       --start-time $(date -d '1 hour ago' +%s)000
   ```

3. **S3 Access Issues**:
   ```bash
   # Verify bucket exists and is accessible
   aws s3 ls "s3://$(terraform output -raw firmware_bucket_name)"
   
   # Check bucket policy
   aws s3api get-bucket-policy --bucket "$(terraform output -raw firmware_bucket_name)"
   ```

4. **IoT Job Issues**:
   ```bash
   # List all jobs
   aws iot list-jobs
   
   # Check job details
   aws iot describe-job --job-id JOB_ID
   
   # List job executions
   aws iot list-job-executions-for-job --job-id JOB_ID
   ```

### Debug Mode
Enable detailed logging by setting environment variables:

```bash
export TF_LOG=DEBUG
export AWS_SDK_LOAD_CONFIG=1
terraform apply
```

## Cleanup

To destroy the infrastructure:

```bash
# Remove all resources
terraform destroy

# Confirm deletion
aws s3 ls | grep $(terraform output -raw firmware_bucket_name) || echo "Bucket deleted"
```

**Note**: The S3 bucket must be empty before Terraform can delete it. The configuration automatically removes the sample firmware, but if you've uploaded additional files, remove them manually:

```bash
# Empty the bucket before destroy
aws s3 rm "s3://$(terraform output -raw firmware_bucket_name)" --recursive
```

## Cost Optimization

### Resource Costs
- **S3**: Storage costs for firmware files (~$0.023/GB/month)
- **Lambda**: Execution costs (~$0.20/1M requests + $0.0000166667/GB-second)
- **IoT Jobs**: Message costs (~$1.00/1M messages)
- **CloudWatch**: Log storage (~$0.50/GB/month)
- **AWS Signer**: Signing requests (~$0.80/signing request)

### Cost Reduction Tips
1. Use S3 Intelligent Tiering for firmware storage
2. Set appropriate CloudWatch log retention periods
3. Implement Lambda reserved concurrency for predictable costs
4. Use S3 lifecycle policies for old firmware versions

## Support

For issues related to this Terraform configuration:

1. Check the [AWS IoT Device Management documentation](https://docs.aws.amazon.com/iot/latest/developerguide/iot-device-management.html)
2. Review the [AWS Signer documentation](https://docs.aws.amazon.com/signer/latest/developerguide/Welcome.html)
3. Consult the [Terraform AWS Provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
4. Review the original recipe documentation for implementation details

## Contributing

When modifying this infrastructure:

1. Update variable descriptions and validation rules
2. Add appropriate tags to new resources
3. Update outputs for new resources
4. Test changes in a development environment
5. Update this README with new features or changes