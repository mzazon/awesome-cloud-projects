# Real-time Data Quality Monitoring with Deequ on EMR - Terraform Infrastructure

This Terraform configuration deploys a comprehensive real-time data quality monitoring solution using Amazon Deequ on EMR. The infrastructure includes an EMR cluster with Deequ pre-installed, S3 data lake, CloudWatch monitoring, SNS alerting, and automation capabilities.

## 🏗️ Architecture Overview

The infrastructure creates:

- **EMR Cluster**: Managed Spark environment with Deequ for data quality analysis
- **S3 Data Lake**: Centralized storage for raw data, quality reports, and scripts
- **CloudWatch Integration**: Metrics collection and dashboard for monitoring
- **SNS Alerting**: Automated notifications for quality issues
- **Lambda Automation**: Optional automated monitoring triggers
- **IAM Roles**: Secure access management with least privilege

## 📋 Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured
   ```bash
   aws configure
   ```

2. **Terraform** v1.0+ installed
   ```bash
   terraform --version
   ```

3. **Appropriate AWS permissions** for:
   - EMR cluster management
   - S3 bucket creation and management
   - IAM role creation
   - CloudWatch and SNS access
   - Lambda function deployment

4. **Cost awareness**: EMR clusters incur hourly charges (~$15-25/hour for default configuration)

## 🚀 Quick Start

### 1. Clone and Navigate
```bash
cd aws/real-time-data-quality-monitoring-deequ-emr/code/terraform
```

### 2. Initialize Terraform
```bash
terraform init
```

### 3. Review and Customize Variables
```bash
# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit variables to match your requirements
vim terraform.tfvars
```

### 4. Plan Deployment
```bash
terraform plan
```

### 5. Deploy Infrastructure
```bash
terraform apply
```

### 6. Confirm Email Subscription
Check your email for SNS subscription confirmation if you provided `notification_email`.

## ⚙️ Configuration Variables

### Essential Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `notification_email` | Email for quality alerts | `""` | No |

### EMR Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `emr_release_label` | EMR version | `emr-6.15.0` |
| `emr_instance_type` | EC2 instance type | `m5.xlarge` |
| `emr_instance_count` | Number of cluster instances | `3` |
| `emr_auto_termination_timeout` | Auto-termination timeout (seconds) | `3600` |

### Advanced Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_spot_instances` | Use Spot instances for cost reduction | `false` |
| `enable_encryption_at_rest` | Enable encryption at rest | `true` |
| `create_dashboard` | Create CloudWatch dashboard | `true` |
| `cloudwatch_log_retention_days` | Log retention period | `7` |

## 📊 Sample terraform.tfvars

```hcl
# Basic Configuration
aws_region         = "us-east-1"
environment        = "dev"
project_name       = "deequ-quality-monitor"
notification_email = "your-email@company.com"

# EMR Configuration
emr_instance_type  = "m5.xlarge"
emr_instance_count = 3

# Cost Optimization
enable_spot_instances     = true
spot_instance_percentage  = 50

# Security
enable_encryption_at_rest     = true
enable_encryption_in_transit  = true

# Monitoring
create_dashboard              = true
cloudwatch_log_retention_days = 14
```

## 🔧 Post-Deployment Steps

### 1. Wait for Cluster Ready State
```bash
# Check cluster status
aws emr describe-cluster --cluster-id $(terraform output -raw emr_cluster_id)

# Wait for WAITING state (cluster ready for jobs)
aws emr wait cluster-running --cluster-id $(terraform output -raw emr_cluster_id)
```

### 2. Generate and Upload Sample Data
```bash
# Use the included data generator
python3 scripts/generate-sample-data.py \
    --records 10000 \
    --s3-bucket $(terraform output -raw s3_bucket_name) \
    --s3-key "raw-data/sample_customer_data.csv"
```

### 3. Submit Your First Quality Monitoring Job
```bash
# Use the output command from Terraform
terraform output -raw sample_spark_submit_command | bash
```

### 4. Monitor Results
- **CloudWatch Dashboard**: Check the dashboard URL from `terraform output cloudwatch_dashboard_url`
- **S3 Reports**: Browse quality reports in the S3 bucket
- **Email Alerts**: Check for SNS notifications

## 📈 Using the Infrastructure

### Running Data Quality Jobs

Submit monitoring jobs using the EMR Steps API:

```bash
# Submit a monitoring job
aws emr add-steps \
    --cluster-id $(terraform output -raw emr_cluster_id) \
    --steps '[{
        "Name": "DataQualityMonitoring",
        "ActionOnFailure": "CONTINUE",
        "HadoopJarStep": {
            "Jar": "command-runner.jar",
            "Args": [
                "spark-submit",
                "--deploy-mode", "cluster",
                "--master", "yarn",
                "s3://BUCKET/scripts/deequ-quality-monitor.py",
                "BUCKET",
                "s3://BUCKET/raw-data/your-data.csv",
                "SNS_TOPIC_ARN"
            ]
        }
    }]'
```

### Monitoring Job Progress

```bash
# List running steps
aws emr list-steps --cluster-id $(terraform output -raw emr_cluster_id)

# Get step details
aws emr describe-step --cluster-id CLUSTER_ID --step-id STEP_ID
```

### Automated Monitoring with Lambda

The deployed Lambda function can be triggered to automatically submit monitoring jobs:

```bash
# Invoke Lambda function
aws lambda invoke \
    --function-name $(terraform output -raw lambda_function_name) \
    --payload '{"data_path": "s3://bucket/raw-data/new-data.csv"}' \
    response.json
```

## 📊 CloudWatch Metrics

The solution publishes metrics to the `DataQuality/Deequ` namespace:

- **Size**: Dataset record count
- **Completeness_***: Data completeness ratios
- **Uniqueness_***: Data uniqueness scores
- **Mean_***: Statistical means
- **StandardDeviation_***: Statistical deviations

## 🔔 Alert Configuration

SNS alerts are triggered for:
- Data quality check failures
- Missing or invalid data patterns
- Processing errors
- Infrastructure issues

Alert severity levels:
- **HIGH**: Critical quality failures, system errors
- **MEDIUM**: Minor quality issues, warnings
- **LOW**: Informational messages

## 💰 Cost Management

### Cost Optimization Strategies

1. **Use Spot Instances**: Set `enable_spot_instances = true`
2. **Auto-termination**: Configure `emr_auto_termination_timeout`
3. **Right-sizing**: Adjust `emr_instance_type` and `emr_instance_count`
4. **S3 Lifecycle**: Configure automatic archival of old reports

### Cost Monitoring

```bash
# Monitor EMR costs
aws ce get-cost-and-usage \
    --time-period Start=2025-01-01,End=2025-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## 🛡️ Security Best Practices

The infrastructure implements:

- **Encryption**: Data encrypted at rest and in transit
- **IAM Roles**: Least privilege access patterns
- **VPC Security**: Network isolation and security groups
- **Audit Logging**: Comprehensive CloudWatch logging
- **Access Control**: S3 bucket public access blocked

## 🔧 Troubleshooting

### Common Issues

1. **Cluster fails to start**
   ```bash
   # Check bootstrap logs
   aws s3 cp s3://$(terraform output -raw s3_bucket_name)/logs/CLUSTER_ID/node/ . --recursive
   ```

2. **Steps fail with errors**
   ```bash
   # Check step logs
   aws emr describe-step --cluster-id CLUSTER_ID --step-id STEP_ID
   ```

3. **No CloudWatch metrics**
   - Verify IAM permissions for CloudWatch
   - Check Spark application logs
   - Ensure metrics publishing code is executing

4. **Missing SNS alerts**
   - Confirm email subscription
   - Check SNS topic permissions
   - Verify Lambda error handling

### Debug Commands

```bash
# Check cluster status
terraform output emr_cluster_id | xargs aws emr describe-cluster --cluster-id

# List S3 bucket contents
terraform output s3_bucket_name | xargs aws s3 ls s3:// --recursive

# Check recent CloudWatch metrics
aws cloudwatch list-metrics --namespace "DataQuality/Deequ"

# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/deequ"
```

## 🧹 Cleanup

To avoid ongoing charges, destroy the infrastructure when done:

```bash
# Destroy all resources
terraform destroy

# Confirm destruction
terraform show
```

**⚠️ Warning**: This will delete all data in S3 buckets if `s3_force_destroy = true`.

## 📚 Additional Resources

- [Amazon Deequ Documentation](https://github.com/awslabs/deequ)
- [EMR Best Practices](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-plan.html)
- [Spark Configuration Guide](https://spark.apache.org/docs/latest/configuration.html)
- [CloudWatch Metrics Reference](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)

## 🤝 Contributing

To contribute improvements to this infrastructure:

1. Test changes in a development environment
2. Validate with `terraform plan`
3. Update documentation for any new variables
4. Test the complete deployment lifecycle

## 📄 License

This infrastructure code is part of the AWS recipes collection and follows the same licensing terms.

---

**🎯 Need Help?** Check the [troubleshooting section](#-troubleshooting) or review the AWS documentation for specific services.