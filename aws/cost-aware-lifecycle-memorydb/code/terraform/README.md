# Terraform Infrastructure for Cost-Aware MemoryDB Lifecycle Management

This Terraform configuration creates a comprehensive cost optimization system for Amazon MemoryDB workloads using EventBridge Scheduler, Lambda automation, and intelligent cost monitoring.

## Architecture Overview

The infrastructure deploys:

- **MemoryDB Cluster**: Redis-compatible in-memory database with automated scaling capabilities
- **Lambda Function**: Python-based cost optimization engine with Cost Explorer integration
- **EventBridge Scheduler**: Reliable scheduling for business hours automation
- **CloudWatch Monitoring**: Comprehensive dashboards, alarms, and custom metrics
- **Cost Management**: AWS Budgets integration with proactive alerting
- **Security**: IAM roles and policies following least privilege principles

## Prerequisites

- AWS CLI installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for:
  - MemoryDB management
  - Lambda function deployment
  - EventBridge Scheduler management
  - IAM role and policy management
  - CloudWatch and Cost Explorer access
  - AWS Budgets management

## Quick Start

### 1. Initialize Terraform

```bash
terraform init
```

### 2. Review and Customize Variables

Copy the example variables file and customize for your environment:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific configuration:

```hcl
# Basic Configuration
aws_region         = "us-east-1"
environment        = "dev"
cost_center        = "engineering"
cost_alert_email   = "your-email@company.com"

# MemoryDB Configuration
memorydb_node_type = "db.t4g.small"
memorydb_num_shards = 1
memorydb_num_replicas_per_shard = 0

# Cost Thresholds
monthly_budget_limit = 200
weekly_cost_alarm_threshold = 150
scale_up_cost_threshold = 100
scale_down_cost_threshold = 50

# Business Hours (UTC)
business_hours_start_cron = "0 8 ? * MON-FRI *"  # 8 AM weekdays
business_hours_end_cron   = "0 18 ? * MON-FRI *" # 6 PM weekdays

# Feature Flags
enable_scheduler_automation = true
enable_detailed_monitoring  = true
enable_cost_budget         = true
```

### 3. Plan and Apply

```bash
# Review planned changes
terraform plan

# Apply the configuration
terraform apply
```

## Configuration Options

### MemoryDB Settings

| Variable | Description | Default | Valid Values |
|----------|-------------|---------|--------------|
| `memorydb_node_type` | Initial node type for cost optimization | `db.t4g.small` | Valid MemoryDB instance types |
| `memorydb_num_shards` | Number of shards | `1` | 1-500 |
| `memorydb_num_replicas_per_shard` | Replicas per shard | `0` | 0-5 |
| `memorydb_maintenance_window` | Maintenance window (UTC) | `sun:03:00-sun:04:00` | Valid time window |

### Cost Management Settings

| Variable | Description | Default | Range |
|----------|-------------|---------|--------|
| `monthly_budget_limit` | Budget limit in USD | `200` | > 0 |
| `budget_alert_threshold_actual` | Actual cost alert % | `80` | 1-100 |
| `budget_alert_threshold_forecasted` | Forecasted cost alert % | `90` | 1-100 |
| `weekly_cost_alarm_threshold` | Weekly cost alarm threshold | `150` | > 0 |

### Scheduling Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `business_hours_start_cron` | Scale-up schedule | `0 8 ? * MON-FRI *` |
| `business_hours_end_cron` | Scale-down schedule | `0 18 ? * MON-FRI *` |
| `weekly_analysis_cron` | Weekly analysis schedule | `0 9 ? * MON *` |

### Feature Toggles

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_scheduler_automation` | Enable EventBridge Scheduler | `true` |
| `enable_detailed_monitoring` | Enable CloudWatch monitoring | `true` |
| `enable_cost_budget` | Enable AWS Budgets | `true` |
| `enable_deletion_protection` | Enable resource protection | `false` |

## Security Configuration

### IAM Roles and Policies

The configuration creates two specialized IAM roles:

1. **Lambda Execution Role**: Permissions for cost analysis and cluster management
2. **EventBridge Scheduler Role**: Permissions for Lambda function invocation

### Network Security

- **Security Group**: Controls access to MemoryDB cluster
- **VPC Configuration**: Supports both default and custom VPC deployment
- **Subnet Groups**: Multi-AZ deployment for high availability

### Default Security Settings

```hcl
allowed_cidr_blocks = [
  "10.0.0.0/8",
  "172.16.0.0/12", 
  "192.168.0.0/16"
]
```

## Monitoring and Alerting

### CloudWatch Dashboard

The deployment creates a comprehensive dashboard with:

- **Cost Optimization Metrics**: Weekly costs, optimization actions, cost trends
- **MemoryDB Performance**: CPU utilization, network I/O, cluster health
- **Lambda Function Health**: Duration, errors, invocations

### CloudWatch Alarms

1. **Weekly Cost Alarm**: Triggers when costs exceed threshold
2. **Lambda Error Alarm**: Monitors automation function health

### Custom Metrics

Published to `MemoryDB/CostOptimization` namespace:
- `WeeklyCost`: 7-day rolling cost
- `DailyCostAverage`: Average daily cost
- `OptimizationAction`: Count of optimization actions
- `CostTrend`: Cost trend analysis

## Testing and Validation

### Manual Testing

```bash
# Test Lambda function
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{"cluster_name":"CLUSTER_NAME","action":"analyze","cost_threshold":100}' \
  /tmp/response.json

# Check cluster status
aws memorydb describe-clusters \
  --cluster-name $(terraform output -raw memorydb_cluster_name)

# View cost metrics
aws cloudwatch get-metric-statistics \
  --namespace MemoryDB/CostOptimization \
  --metric-name WeeklyCost \
  --dimensions Name=ClusterName,Value=$(terraform output -raw memorydb_cluster_name) \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Average
```

### Verification Commands

```bash
# View all outputs
terraform output

# Check scheduler status
aws scheduler list-schedules \
  --group-name $(terraform output -raw scheduler_group_name)

# Monitor Lambda logs
aws logs tail $(terraform output -raw lambda_log_group_name) --follow
```

## Cost Optimization Features

### Automated Scaling

- **Business Hours Scale-Up**: 8 AM weekdays (configurable)
- **Off-Hours Scale-Down**: 6 PM weekdays (configurable)
- **Weekly Analysis**: Cost trend monitoring and recommendations

### Scaling Logic

| Current Node Type | Scale Down Target | Scale Up Target | Savings |
|-------------------|-------------------|-----------------|---------|
| db.t4g.large | db.t4g.small | - | 30-40% |
| db.t4g.medium | db.t4g.small | - | 20-30% |
| db.t4g.small | - | db.t4g.medium | Performance boost |

### Cost Intelligence

- **7-Day Cost Analysis**: Trend-based optimization decisions
- **Cost Explorer Integration**: Real-time AWS spending data
- **Threshold-Based Scaling**: Configurable cost triggers
- **Budget Integration**: Proactive cost alerting

## Troubleshooting

### Common Issues

1. **Lambda Permission Errors**
   ```bash
   # Check IAM role permissions
   aws iam get-role-policy --role-name ROLE_NAME --policy-name POLICY_NAME
   ```

2. **MemoryDB Cluster Not Available**
   ```bash
   # Check cluster status
   aws memorydb describe-clusters --cluster-name CLUSTER_NAME
   ```

3. **Cost Data Unavailable**
   - Cost Explorer API may need 24-48 hours for data availability
   - Check AWS Cost Explorer console for data presence

### Debugging Lambda Function

```bash
# View recent logs
aws logs describe-log-streams \
  --log-group-name $(terraform output -raw lambda_log_group_name) \
  --order-by LastEventTime \
  --descending

# Get specific log events
aws logs get-log-events \
  --log-group-name $(terraform output -raw lambda_log_group_name) \
  --log-stream-name LOG_STREAM_NAME
```

## Cleanup

### Destroy Infrastructure

```bash
# Plan destruction
terraform plan -destroy

# Destroy all resources
terraform destroy
```

### Manual Cleanup (if needed)

```bash
# Delete any remaining MemoryDB snapshots
aws memorydb describe-snapshots --cluster-name CLUSTER_NAME
aws memorydb delete-snapshot --snapshot-name SNAPSHOT_NAME

# Remove Lambda deployment packages
rm -f lambda_function.zip lambda_function.py
```

## Best Practices

### Production Deployment

1. **Enable Deletion Protection**:
   ```hcl
   enable_deletion_protection = true
   ```

2. **Use Dedicated VPC**:
   ```hcl
   use_default_vpc = false
   vpc_id = "vpc-xxxxxxxxx"
   subnet_ids = ["subnet-xxxxxxxxx", "subnet-yyyyyyyyy"]
   ```

3. **Configure Proper Maintenance Windows**:
   ```hcl
   memorydb_maintenance_window = "sun:03:00-sun:04:00"
   ```

4. **Set Appropriate Cost Thresholds**:
   ```hcl
   monthly_budget_limit = 1000
   weekly_cost_alarm_threshold = 200
   ```

### Security Hardening

- Restrict CIDR blocks to specific application subnets
- Enable VPC Flow Logs for network monitoring  
- Use AWS KMS for encryption at rest
- Implement resource-based policies for fine-grained access control

### Monitoring Enhancement

- Set up SNS topics for alarm notifications
- Integrate with AWS Chatbot for Slack/Teams alerts
- Enable AWS X-Ray tracing for Lambda function
- Configure custom CloudWatch Insights queries

## Support

For issues with this Terraform configuration:

1. Check the [AWS MemoryDB documentation](https://docs.aws.amazon.com/memorydb/)
2. Review [EventBridge Scheduler documentation](https://docs.aws.amazon.com/scheduler/)
3. Consult [AWS Cost Explorer API documentation](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-api.html)
4. Refer to the original recipe documentation for architecture details

## Version Information

- **Terraform Version**: >= 1.0
- **AWS Provider Version**: ~> 5.0
- **Lambda Runtime**: Python 3.9
- **Recipe Version**: 1.0