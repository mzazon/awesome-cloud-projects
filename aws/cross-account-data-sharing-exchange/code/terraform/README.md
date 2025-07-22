# AWS Data Exchange Cross-Account Data Sharing - Terraform Infrastructure

This Terraform configuration creates a complete AWS Data Exchange solution for secure cross-account data sharing with automated updates and comprehensive monitoring capabilities.

## 🏗️ Architecture Overview

The infrastructure includes:

- **AWS Data Exchange**: Dataset and revision management for secure data sharing
- **S3 Buckets**: Provider and subscriber buckets for data storage
- **IAM Roles**: Service roles for Data Exchange and Lambda operations
- **Lambda Functions**: Automated notification handling and data updates
- **EventBridge Rules**: Event-driven automation and scheduling
- **CloudWatch**: Comprehensive monitoring, logging, and alerting
- **SNS Topic**: Optional email notifications for Data Exchange events

## 📋 Prerequisites

1. **AWS Account**: Two AWS accounts (provider and subscriber) with appropriate permissions
2. **AWS CLI**: Version 2.0 or later, configured with credentials
3. **Terraform**: Version 1.5 or later
4. **Permissions**: The following AWS permissions are required:
   - Data Exchange: Full access for provider operations
   - S3: Bucket creation, object management
   - IAM: Role and policy management
   - Lambda: Function creation and management
   - EventBridge: Rule and target management
   - CloudWatch: Log group and alarm management
   - SNS: Topic and subscription management (if email notifications enabled)

## 🚀 Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd aws/cross-account-data-sharing-aws-data-exchange/code/terraform/

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your configuration
nano terraform.tfvars
```

### 2. Required Variables

Set the following required variables in `terraform.tfvars`:

```hcl
# Required: AWS region for deployment
aws_region = "us-east-1"

# Required: Subscriber AWS account ID (12-digit account ID)
subscriber_account_id = "123456789012"

# Optional: Email for notifications
notification_email = "admin@example.com"

# Optional: Custom dataset name
dataset_name = "my-enterprise-analytics-data"
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment

```bash
# Check the created resources
terraform output

# View the Data Exchange dataset
aws dataexchange list-data-sets --origin OWNED

# Check S3 buckets
aws s3 ls | grep data-exchange
```

## 📊 Configuration Options

### Core Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for deployment | `us-east-1` | Yes |
| `subscriber_account_id` | Subscriber AWS account ID | - | Yes |
| `dataset_name` | Name for the Data Exchange dataset | Auto-generated | No |
| `provider_bucket_name` | S3 bucket for data provider | Auto-generated | No |
| `subscriber_bucket_name` | S3 bucket for data subscriber | Auto-generated | No |

### Optional Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `data_grant_expires_at` | Data grant expiration (ISO 8601) | `2024-12-31T23:59:59Z` |
| `lambda_timeout` | Lambda function timeout (seconds) | `60` |
| `lambda_memory_size` | Lambda memory allocation (MB) | `256` |
| `log_retention_days` | CloudWatch log retention period | `30` |
| `schedule_expression` | Update schedule expression | `rate(24 hours)` |
| `sample_data_enabled` | Create sample data files | `true` |
| `enable_versioning` | Enable S3 bucket versioning | `true` |
| `enable_monitoring` | Enable CloudWatch monitoring | `true` |
| `notification_email` | Email for SNS notifications | `""` |

### Advanced Configuration

```hcl
# Custom tags for all resources
default_tags = {
  Environment = "production"
  Project     = "data-exchange"
  Owner       = "data-team"
}

# Additional resource-specific tags
additional_tags = {
  CostCenter = "analytics"
  Compliance = "required"
}

# Custom schedule for data updates
schedule_expression = "cron(0 6 * * ? *)"  # Daily at 6 AM UTC
```

## 🔧 Lambda Functions

### Notification Handler

Processes Data Exchange events and sends notifications:

- **Trigger**: EventBridge rules for Data Exchange events
- **Function**: Formats and sends notifications via SNS
- **Monitoring**: Custom CloudWatch metrics for event tracking

### Auto Update Function

Automatically creates new data revisions:

- **Trigger**: EventBridge scheduled rules
- **Function**: Generates sample data and creates new revisions
- **Features**: Realistic data generation, error handling, metrics logging

## 📈 Monitoring and Alerting

### CloudWatch Resources

- **Log Groups**: Separate log groups for each Lambda function and Data Exchange operations
- **Metrics**: Custom metrics for event tracking and automation success/failure
- **Alarms**: Automated alerting for failed operations

### Available Metrics

- `DataExchange/Events/EventCount`: Count of Data Exchange events
- `DataExchange/Events/FailedEvents`: Count of failed operations
- `DataExchange/AutoUpdate/SuccessfulUpdates`: Successful automated updates
- `DataExchange/AutoUpdate/FailedUpdates`: Failed automated updates

## 🔐 Security Best Practices

### IAM Security

- **Least Privilege**: All roles follow least privilege principle
- **Service-Specific**: Separate roles for Data Exchange and Lambda operations
- **Resource-Specific**: Policies limited to specific buckets and datasets

### Data Security

- **Encryption**: All S3 buckets use server-side encryption
- **Access Control**: Public access blocked on all buckets
- **Versioning**: Optional versioning for data integrity

### Network Security

- **Private**: All resources operate within AWS network boundaries
- **Cross-Account**: Secure cross-account sharing through Data Exchange grants

## 🛠️ Management and Operations

### Creating Data Grants

After deployment, create data grants for cross-account sharing:

```bash
# Get the dataset ID from Terraform outputs
DATASET_ID=$(terraform output -raw dataset_id)

# Create a data grant (replace with actual subscriber account)
aws dataexchange create-data-grant \
    --name "Analytics Data Grant" \
    --description "Cross-account data sharing grant" \
    --dataset-id "$DATASET_ID" \
    --recipient-account-id "123456789012" \
    --ends-at "2024-12-31T23:59:59Z"
```

### Subscriber Access

Use the generated subscriber access script:

```bash
# Make the script executable
chmod +x generated/subscriber-access-script.sh

# Run the script with a data grant ID
./generated/subscriber-access-script.sh <data-grant-id>

# Use dry-run mode to test
./generated/subscriber-access-script.sh <data-grant-id> --dry-run
```

### Manual Data Updates

Trigger manual data updates:

```bash
# Get function name from outputs
FUNCTION_NAME=$(terraform output -raw auto_update_lambda_name)
DATASET_ID=$(terraform output -raw dataset_id)
BUCKET_NAME=$(terraform output -raw provider_bucket_name)

# Invoke the Lambda function
aws lambda invoke \
    --function-name "$FUNCTION_NAME" \
    --payload "{\"dataset_id\":\"$DATASET_ID\",\"bucket_name\":\"$BUCKET_NAME\"}" \
    response.json

# Check the response
cat response.json
```

## 🧹 Cleanup

### Destroy Infrastructure

```bash
# Remove all resources
terraform destroy

# Confirm when prompted
# Type: yes
```

### Manual Cleanup (if needed)

If Terraform destroy fails, manually clean up:

```bash
# List and delete Data Exchange resources
aws dataexchange list-data-sets --origin OWNED
aws dataexchange delete-data-set --data-set-id <dataset-id>

# Empty S3 buckets before deletion
aws s3 rm s3://<bucket-name> --recursive
aws s3 rb s3://<bucket-name>
```

## 🔍 Troubleshooting

### Common Issues

1. **Data Exchange Not Available**: Ensure your region supports Data Exchange
2. **Permission Denied**: Verify IAM permissions for all required services
3. **Bucket Name Conflicts**: S3 bucket names must be globally unique
4. **Lambda Timeout**: Increase timeout for large data processing operations

### Debug Commands

```bash
# Check Data Exchange service availability
aws dataexchange describe-data-sets --max-items 1

# Verify Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# Check EventBridge rules
aws events list-rules --name-prefix "DataExchange"

# Monitor CloudWatch metrics
aws cloudwatch list-metrics --namespace "DataExchange/Events"
```

### Log Analysis

```bash
# View Lambda function logs
aws logs tail "/aws/lambda/DataExchangeNotificationHandler-<suffix>" --follow

# Check for errors in auto-update function
aws logs filter-log-events \
    --log-group-name "/aws/lambda/DataExchangeAutoUpdate-<suffix>" \
    --filter-pattern "ERROR"
```

## 📚 Additional Resources

- [AWS Data Exchange User Guide](https://docs.aws.amazon.com/data-exchange/latest/userguide/)
- [AWS Data Exchange API Reference](https://docs.aws.amazon.com/data-exchange/latest/apireference/)
- [EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)

## 📞 Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS service documentation
3. Verify your AWS account permissions and limits
4. Check CloudWatch logs for detailed error information

## 📄 License

This infrastructure code is provided as part of the AWS Data Exchange cross-account data sharing recipe. Refer to the main recipe documentation for complete usage instructions and best practices.