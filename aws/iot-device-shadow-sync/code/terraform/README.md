# Advanced IoT Device Shadow Synchronization - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code for IoT Device Shadow Synchronization with conflict resolution, offline support, and comprehensive monitoring.

## Overview

This infrastructure deploys a complete IoT shadow synchronization system that includes:

- **Conflict Resolution**: Lambda-based conflict detection and resolution with multiple strategies
- **Offline Support**: Comprehensive handling of devices reconnecting after extended offline periods  
- **Shadow Management**: Multiple named shadows for different data types (configuration, telemetry, maintenance)
- **Audit Trail**: Complete shadow update history and compliance logging
- **Monitoring**: Real-time dashboards, metrics, and health reporting
- **Event-Driven Architecture**: Automated processing using IoT Rules and EventBridge

## Architecture Components

### Core Services
- **AWS IoT Core**: Device shadow management and MQTT communication
- **AWS Lambda**: Conflict resolution and synchronization management functions
- **Amazon DynamoDB**: Shadow history, device configuration, and metrics storage
- **Amazon EventBridge**: Event-driven monitoring and alerting
- **Amazon CloudWatch**: Logging, metrics, and operational dashboards

### Lambda Functions
- **Conflict Resolver**: Handles shadow delta events and resolves conflicts using configurable strategies
- **Sync Manager**: Manages offline synchronization, health monitoring, and conflict reporting

### DynamoDB Tables
- **Shadow History**: Audit trail of all shadow changes with versioning
- **Device Configuration**: Device-specific conflict resolution settings and preferences
- **Sync Metrics**: Performance monitoring and conflict analytics data

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for:
  - IoT Core (Things, Certificates, Policies, Rules)
  - Lambda (Functions, Execution Roles)
  - DynamoDB (Tables, Streams)
  - EventBridge (Custom buses, Rules)
  - CloudWatch (Logs, Metrics, Dashboards)
  - IAM (Roles, Policies)

## Quick Start

### 1. Initialize Terraform

```bash
# Initialize Terraform workspace
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply
```

### 2. Deploy with Custom Variables

```bash
# Create terraform.tfvars file
cat > terraform.tfvars << EOF
aws_region = "us-west-2"
thing_name_prefix = "my-iot-device"
default_conflict_strategy = "field_level_merge"
health_check_schedule = "rate(10 minutes)"
log_retention_days = 30
EOF

# Apply with custom variables
terraform apply
```

### 3. Advanced Configuration

```bash
# Use custom configuration file
terraform apply -var-file="production.tfvars"

# Override specific variables
terraform apply \
  -var="aws_region=eu-west-1" \
  -var="conflict_resolver_memory=1024" \
  -var="auto_resolve_threshold=10"
```

## Configuration Options

### Core Configuration

| Variable | Description | Default | Valid Values |
|----------|-------------|---------|--------------|
| `aws_region` | AWS region for deployment | `us-east-1` | Any valid AWS region |
| `thing_name_prefix` | Prefix for IoT Thing name | `sync-demo-device` | Alphanumeric, hyphens, underscores |
| `random_suffix` | Custom suffix for resources | `""` (auto-generated) | Any string |

### Lambda Configuration

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `conflict_resolver_timeout` | Conflict resolver timeout (seconds) | `300` | 1-900 |
| `conflict_resolver_memory` | Conflict resolver memory (MB) | `512` | 128-10240 |
| `sync_manager_timeout` | Sync manager timeout (seconds) | `300` | 1-900 |
| `sync_manager_memory` | Sync manager memory (MB) | `256` | 128-10240 |

### Conflict Resolution

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `default_conflict_strategy` | Default resolution strategy | `field_level_merge` | `last_writer_wins`, `field_level_merge`, `priority_based`, `manual_review` |
| `auto_resolve_threshold` | Conflicts before manual review | `5` | 1-100 |

### Monitoring Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `health_check_schedule` | Health check frequency | `rate(15 minutes)` | EventBridge rate/cron syntax |
| `log_retention_days` | CloudWatch log retention | `14` | Valid CloudWatch retention periods |

### DynamoDB Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `dynamodb_billing_mode` | DynamoDB billing mode | `PAY_PER_REQUEST` | `PAY_PER_REQUEST`, `PROVISIONED` |
| `dynamodb_read_capacity` | Read capacity (if PROVISIONED) | `5` | 1+ |
| `dynamodb_write_capacity` | Write capacity (if PROVISIONED) | `5` | 1+ |

## Post-Deployment Setup

### 1. Initialize Device Shadows

After deployment, initialize the named shadows for your device:

```bash
# Get device name from Terraform outputs
THING_NAME=$(terraform output -raw thing_name)

# Initialize configuration shadow
aws iot-data update-thing-shadow \
    --thing-name $THING_NAME \
    --shadow-name "configuration" \
    --payload '{"state":{"desired":{"samplingRate":30,"alertThreshold":80},"reported":{"samplingRate":30,"alertThreshold":80,"firmwareVersion":"v1.0.0"}}}' \
    config-shadow.json

# Initialize telemetry shadow
aws iot-data update-thing-shadow \
    --thing-name $THING_NAME \
    --shadow-name "telemetry" \
    --payload '{"state":{"reported":{"temperature":23.5,"humidity":65.2,"pressure":1013.25}}}' \
    telemetry-shadow.json

# Initialize maintenance shadow
aws iot-data update-thing-shadow \
    --thing-name $THING_NAME \
    --shadow-name "maintenance" \
    --payload '{"state":{"desired":{"maintenanceWindow":"02:00-04:00"},"reported":{"lastMaintenance":"'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'"}}}' \
    maintenance-shadow.json
```

### 2. Test Conflict Resolution

```bash
# Simulate a conflict by updating the same shadow field from different sources
SYNC_MANAGER=$(terraform output -raw sync_manager_function_name)

# Test sync check
aws lambda invoke \
    --function-name $SYNC_MANAGER \
    --payload '{"operation":"sync_check","thingName":"'$THING_NAME'","shadowNames":["configuration","telemetry","maintenance"]}' \
    sync-check-result.json

# View results
cat sync-check-result.json | jq '.body' | jq '.'
```

### 3. Monitor System Health

```bash
# Generate health report
aws lambda invoke \
    --function-name $SYNC_MANAGER \
    --payload '{"operation":"health_report","thingNames":["'$THING_NAME'"]}' \
    health-report.json

# View dashboard
DASHBOARD_URL=$(terraform output -raw dashboard_url)
echo "Access dashboard at: $DASHBOARD_URL"

# Check conflict metrics
aws cloudwatch get-metric-statistics \
    --namespace "IoT/ShadowSync" \
    --metric-name "ConflictDetected" \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Device Integration

### Certificate and Connection

```bash
# Save device credentials from Terraform outputs
terraform output -raw certificate_pem > device-cert.pem
terraform output -raw private_key > device-private.key
terraform output -raw public_key > device-public.key

# Download Amazon Root CA
curl -o AmazonRootCA1.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem

# Get IoT endpoint
IOT_ENDPOINT=$(terraform output -raw iot_endpoint)
echo "Connect to: $IOT_ENDPOINT:8883"
```

### MQTT Topics for Shadow Operations

```bash
# Shadow update topics (publish)
$aws/things/{thing-name}/shadow/{shadow-name}/update

# Shadow delta topics (subscribe)
$aws/things/{thing-name}/shadow/{shadow-name}/update/delta

# Shadow get topics
$aws/things/{thing-name}/shadow/{shadow-name}/get
```

## Troubleshooting

### Common Issues

1. **Lambda timeout errors**: Increase memory allocation or timeout values
2. **DynamoDB throttling**: Switch to on-demand billing or increase capacity
3. **IoT connection failures**: Verify certificate, policy, and endpoint configuration
4. **Conflict resolution not triggering**: Check IoT Rules and Lambda permissions

### Debugging Commands

```bash
# Check Lambda function logs
CONFLICT_RESOLVER=$(terraform output -raw conflict_resolver_function_name)
aws logs filter-log-events \
    --log-group-name "/aws/lambda/$CONFLICT_RESOLVER" \
    --start-time $(date -d '1 hour ago' +%s)000

# Check IoT Rules
aws iot list-topic-rules
aws iot get-topic-rule --rule-name ShadowDeltaProcessingRule

# Check shadow state
aws iot-data get-thing-shadow \
    --thing-name $THING_NAME \
    --shadow-name configuration \
    current-shadow.json
```

### Performance Tuning

1. **High-frequency updates**: Consider using DynamoDB on-demand billing
2. **Large device fleets**: Implement device grouping and batch processing
3. **Complex conflicts**: Optimize conflict resolution algorithms
4. **Storage costs**: Implement data retention policies and archiving

## Monitoring and Alerting

### CloudWatch Metrics

The system publishes custom metrics to the `IoT/ShadowSync` namespace:

- `ConflictDetected`: Number of conflicts detected
- `SyncCompleted`: Successful synchronizations
- `OfflineSync`: Offline synchronization events

### Log Groups

- `/aws/iot/shadow-audit`: All shadow update events
- `/aws/lambda/{conflict-resolver}`: Conflict resolution logs  
- `/aws/lambda/{sync-manager}`: Sync management logs

### Dashboard Components

- Shadow synchronization metrics over time
- Audit trail of shadow updates
- Conflict resolution events and trends
- System health indicators

## Security Considerations

### IAM Permissions

The infrastructure follows least privilege principles:

- Lambda functions have minimal required permissions
- IoT policies restrict access to device-specific resources
- DynamoDB access is limited to necessary tables and operations

### Data Protection

- All data in transit uses TLS encryption
- DynamoDB tables have point-in-time recovery enabled
- CloudWatch logs are encrypted at rest
- Shadow data can include sensitive information - implement field-level encryption if needed

### Certificate Management

- X.509 certificates are auto-generated for demo purposes
- In production, implement proper certificate lifecycle management
- Consider using AWS IoT Device Management for fleet-wide certificate operations

## Cost Optimization

### Pay-Per-Request Resources

- DynamoDB tables use on-demand billing by default
- Lambda functions only incur costs when invoked
- CloudWatch logs and metrics have retention policies

### Cost Monitoring

```bash
# Estimate monthly costs
aws ce get-cost-and-usage \
    --time-period Start=$(date -d '1 month ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Cleanup

### Complete Infrastructure Removal

```bash
# Destroy all resources
terraform destroy

# Clean up local files
rm -f *.json *.pem *.key
```

### Selective Resource Removal

```bash
# Remove specific resources (be careful!)
terraform destroy -target=aws_iot_thing.demo_device
terraform destroy -target=aws_dynamodb_table.shadow_history
```

## Advanced Configuration

### Production Deployment

```bash
# Production terraform.tfvars example
cat > production.tfvars << EOF
aws_region = "us-east-1"
thing_name_prefix = "prod-iot-device"
conflict_resolver_memory = 1024
sync_manager_memory = 512
default_conflict_strategy = "priority_based"
auto_resolve_threshold = 3
health_check_schedule = "rate(5 minutes)"
log_retention_days = 90
dynamodb_billing_mode = "PROVISIONED"
dynamodb_read_capacity = 10
dynamodb_write_capacity = 10

additional_tags = {
  Environment = "production"
  Owner       = "iot-team"
  CostCenter  = "engineering"
}
EOF
```

### Multi-Region Deployment

For multi-region deployments, deploy the infrastructure in each region with appropriate configuration:

```bash
# Deploy to multiple regions
for region in us-east-1 us-west-2 eu-west-1; do
  terraform workspace new $region || terraform workspace select $region
  terraform apply -var="aws_region=$region" -var="random_suffix=$region"
done
```

## Support and Documentation

- [AWS IoT Device Shadow Service](https://docs.aws.amazon.com/iot/latest/developerguide/iot-device-shadows.html)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the project repository.