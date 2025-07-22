# Database Monitoring Dashboards with CloudWatch - Terraform

This Terraform configuration creates a comprehensive database monitoring solution using Amazon RDS, CloudWatch, and SNS. It implements the infrastructure described in the "Database Monitoring Dashboards with CloudWatch" recipe.

## 🏗️ Architecture

The solution deploys:

- **RDS MySQL Instance** with enhanced monitoring and Performance Insights
- **CloudWatch Dashboard** with comprehensive database performance metrics
- **CloudWatch Alarms** for critical thresholds (CPU, connections, storage, memory, latency)
- **SNS Topic** for alert notifications
- **IAM Role** for enhanced monitoring permissions

## 📋 Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.5 installed
- AWS account with permissions to create:
  - RDS instances
  - CloudWatch dashboards and alarms
  - SNS topics
  - IAM roles and policies

## 🚀 Quick Start

1. **Clone and Navigate**
   ```bash
   cd terraform/
   ```

2. **Configure Variables**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Initialize and Deploy**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## ⚙️ Configuration

### Required Variables

All variables have sensible defaults, but you should customize these in `terraform.tfvars`:

```hcl
# Basic configuration
environment = "demo"
alert_email = "your-email@example.com"  # For receiving alerts

# Database configuration
db_instance_class = "db.t3.micro"  # Adjust for your workload
db_allocated_storage = 20

# Alarm thresholds (customize for your workload)
alarm_cpu_threshold = 80
alarm_connections_threshold = 50
```

### Key Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Environment name | `"demo"` |
| `alert_email` | Email for alerts | `""` |
| `db_instance_class` | RDS instance type | `"db.t3.micro"` |
| `db_allocated_storage` | Storage in GB | `20` |
| `alarm_cpu_threshold` | CPU alarm threshold (%) | `80` |
| `alarm_connections_threshold` | Connection count threshold | `50` |

See `variables.tf` for the complete list of configurable options.

## 📊 Monitoring Features

### CloudWatch Dashboard

The dashboard includes widgets for:

- **Performance Overview**: CPU, Connections, Memory
- **Storage & Latency**: Free storage, Read/Write latency
- **I/O Performance**: IOPS and throughput metrics
- **Database Load**: DBLoad metrics from Performance Insights
- **System Resources**: Swap usage, binary logs, network throughput

### CloudWatch Alarms

Automated alerting for:

- ✅ **High CPU Utilization** (>80% default)
- ✅ **High Database Connections** (>50 default)
- ✅ **Low Storage Space** (<2GB default)
- ✅ **Low Memory** (<256MB default)
- ✅ **High Database Load** (>2 sessions default)
- ✅ **High Read Latency** (>0.2s default)
- ✅ **High Write Latency** (>0.2s default)

### Enhanced Monitoring

- OS-level metrics collected every 60 seconds
- CPU, memory, file system, and network statistics
- Integrated with CloudWatch for centralized monitoring

### Performance Insights

- Query-level performance monitoring
- Identify top SQL statements and wait events
- 7-day retention (free tier)

## 💰 Cost Estimation

Approximate monthly costs (us-east-1):

| Component | Cost |
|-----------|------|
| RDS db.t3.micro | ~$13-16 |
| Storage (20GB gp2) | ~$2 |
| Enhanced Monitoring | ~$1-3 |
| Performance Insights | Free (7 days) |
| CloudWatch Alarms (7) | ~$0.70 |
| SNS Notifications | ~$0.50 |
| **Total** | **~$17-22/month** |

> **Note**: Costs vary by region and actual usage. Consider using AWS Cost Calculator for precise estimates.

## 🔧 Customization

### Alarm Thresholds

Adjust thresholds in `terraform.tfvars`:

```hcl
# For high-traffic applications
alarm_cpu_threshold = 90
alarm_connections_threshold = 100
alarm_db_load_threshold = 4

# For production workloads
alarm_read_latency_threshold = 0.1
alarm_write_latency_threshold = 0.1
```

### Instance Sizing

For different environments:

```hcl
# Development
db_instance_class = "db.t3.micro"
db_allocated_storage = 20

# Staging
db_instance_class = "db.t3.small"
db_allocated_storage = 50

# Production
db_instance_class = "db.r6g.large"
db_allocated_storage = 100
db_max_allocated_storage = 1000
```

### Multi-AZ and Backup

For production environments:

```hcl
db_multi_az = true
db_backup_retention_period = 30
db_deletion_protection = true
db_skip_final_snapshot = false
```

## 🛡️ Security Features

- ✅ **Encryption at rest** enabled by default
- ✅ **Private subnet deployment** (not publicly accessible)
- ✅ **Secure password generation** using Terraform random provider
- ✅ **IAM role** with minimal required permissions
- ✅ **Security group** restrictions

## 📈 Outputs

After deployment, you'll receive:

- Database connection information
- CloudWatch dashboard URL
- SNS topic ARN
- All alarm ARNs
- Performance Insights URL
- Next steps recommendations

Example output:
```
cloudwatch_dashboard_url = "https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=DatabaseMonitoring-abc123"
db_instance_endpoint = "monitoring-demo-abc123.xyz.us-east-1.rds.amazonaws.com:3306"
sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:database-alerts-abc123"
```

## 🔍 Testing and Validation

### Verify Dashboard

1. Visit the CloudWatch dashboard URL from outputs
2. Confirm all metrics are displaying data
3. Check that widgets load properly

### Test Alarms

1. **Verify email subscription**: Check your email for SNS confirmation
2. **Test alarm functionality**:
   ```bash
   # Lower CPU threshold temporarily to test
   terraform apply -var="alarm_cpu_threshold=1"
   ```

### Connect to Database

```bash
# Use the connection command from outputs
mysql -h <endpoint> -P 3306 -u admin -p <database_name>
```

## 🧹 Cleanup

To remove all resources:

```bash
terraform destroy
```

> **Warning**: This will permanently delete the database and all monitoring configuration. Ensure you have backups if needed.

## 📚 Advanced Usage

### Backend Configuration

For production, configure remote state:

```hcl
# In versions.tf
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "database-monitoring/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

### Multi-Environment Deployment

Use Terraform workspaces:

```bash
# Create environments
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod

# Deploy to specific environment
terraform workspace select dev
terraform apply -var-file="dev.tfvars"
```

### Custom Metrics

Add custom CloudWatch metrics:

```hcl
resource "aws_cloudwatch_metric_alarm" "custom_metric" {
  alarm_name          = "custom-application-metric"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CustomMetric"
  namespace           = "AWS/RDS"
  period             = "300"
  statistic          = "Average"
  threshold          = "100"
  alarm_actions      = [aws_sns_topic.database_alerts.arn]
}
```

## 🐛 Troubleshooting

### Common Issues

1. **Database creation fails**:
   - Check AWS service limits
   - Verify subnet group configuration
   - Ensure proper IAM permissions

2. **Alarms not triggering**:
   - Confirm SNS email subscription
   - Check alarm threshold values
   - Verify metric data is being collected

3. **Dashboard not showing data**:
   - Wait 5-10 minutes for metrics to populate
   - Check database instance is running
   - Verify metric names and dimensions

### Debug Commands

```bash
# Check Terraform state
terraform show

# Validate configuration
terraform validate

# Plan with debug output
TF_LOG=DEBUG terraform plan
```

## 📖 References

- [Amazon RDS User Guide](https://docs.aws.amazon.com/rds/)
- [CloudWatch User Guide](https://docs.aws.amazon.com/cloudwatch/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [RDS Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This code is provided as-is for educational purposes. Please review and adapt for your specific requirements before using in production.