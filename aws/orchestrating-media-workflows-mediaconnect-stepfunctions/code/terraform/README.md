# Terraform Infrastructure for MediaConnect Workflow Orchestration

This Terraform configuration deploys a complete real-time media workflow orchestration solution using AWS Elemental MediaConnect, Step Functions, Lambda, CloudWatch, and SNS.

## Architecture Overview

The infrastructure creates an automated media monitoring and alerting system with the following components:

- **MediaConnect Flow**: Ingests live video streams with dual outputs for redundancy
- **Lambda Functions**: Monitor stream health and handle alert notifications
- **Step Functions**: Orchestrate the monitoring workflow with severity-based routing
- **CloudWatch**: Collect metrics, trigger alarms, and provide dashboards
- **SNS**: Deliver real-time notifications to operations teams
- **EventBridge**: Automatically trigger workflows based on alarm states

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.5 installed
- Appropriate AWS permissions for:
  - MediaConnect (flows, outputs)
  - Lambda (functions, execution roles)
  - Step Functions (state machines)
  - CloudWatch (alarms, dashboards, logs)
  - SNS (topics, subscriptions)
  - EventBridge (rules, targets)
  - IAM (roles, policies)
  - S3 (buckets for Lambda artifacts)

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd aws/orchestrating-real-time-media-workflows-with-aws-elemental-mediaconnect-and-step-functions/code/terraform/
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Configure Variables**:
   Create a `terraform.tfvars` file:
   ```hcl
   # Required: Update with your email for notifications
   notification_email = "your-email@example.com"
   
   # Optional: Customize environment and project name
   environment = "prod"
   project_name = "media-workflow"
   
   # Optional: Configure MediaConnect settings
   source_whitelist_cidr = "203.0.113.0/24"  # Replace with your source IP range
   primary_output_destination = "10.0.1.100"
   backup_output_destination = "10.0.1.101"
   
   # Optional: Adjust monitoring thresholds
   packet_loss_threshold = 0.1
   jitter_threshold_ms = 50
   ```

4. **Plan and Apply**:
   ```bash
   terraform plan
   terraform apply
   ```

5. **Confirm SNS Subscription**:
   Check your email and confirm the SNS subscription to receive alerts.

## Configuration Variables

### Required Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `notification_email` | Email for SNS alerts | `admin@example.com` | `ops@yourcompany.com` |

### Network Configuration

| Variable | Description | Default | Security Note |
|----------|-------------|---------|---------------|
| `source_whitelist_cidr` | Source IP whitelist | `0.0.0.0/0` | ⚠️ Restrict to your encoder IPs |
| `primary_output_destination` | Primary output IP | `10.0.0.100` | Your downstream system IP |
| `backup_output_destination` | Backup output IP | `10.0.0.101` | Your backup system IP |
| `ingest_port` | Stream ingest port | `5000` | 1024-65535 |
| `primary_output_port` | Primary output port | `5001` | 1024-65535 |
| `backup_output_port` | Backup output port | `5002` | 1024-65535 |

### Monitoring Thresholds

| Variable | Description | Default | Recommendation |
|----------|-------------|---------|----------------|
| `packet_loss_threshold` | Packet loss alarm % | `0.1` | 0.05-0.2% for broadcast |
| `jitter_threshold_ms` | Jitter alarm threshold | `50` | 20-100ms depending on content |
| `workflow_trigger_threshold` | Workflow trigger % | `0.05` | Lower than packet loss alarm |

### Operational Settings

| Variable | Description | Default | Range |
|----------|-------------|---------|--------|
| `environment` | Environment name | `dev` | dev, staging, prod |
| `project_name` | Project identifier | `media-workflow` | 3-20 chars |
| `lambda_timeout` | Lambda timeout (sec) | `60` | 1-900 |
| `lambda_memory_size` | Lambda memory (MB) | `256` | 128-10240 |
| `step_functions_type` | SF type | `EXPRESS` | STANDARD, EXPRESS |

## Outputs

After deployment, Terraform provides these key outputs:

### MediaConnect Information
- `mediaconnect_ingest_ip`: IP address to stream to
- `mediaconnect_ingest_port`: Port for streaming
- `mediaconnect_flow_arn`: Flow ARN for monitoring

### Console URLs
- `cloudwatch_dashboard_url`: Direct link to monitoring dashboard
- `step_functions_console_url`: Workflow execution history
- `mediaconnect_console_url`: Flow management interface

### Configuration Summary
- `streaming_configuration`: Complete streaming setup details
- `monitoring_configuration`: Alert thresholds and settings

## Usage Instructions

### Starting Your Stream

1. **Get Connection Details**:
   ```bash
   terraform output streaming_configuration
   ```

2. **Configure Your Encoder**:
   - Protocol: RTP
   - Destination: `<ingest_ip>:<ingest_port>`
   - Ensure your encoder IP is in the whitelist CIDR

3. **Start Streaming**:
   The MediaConnect flow will automatically start receiving your stream

### Monitoring Your Stream

1. **View Real-time Metrics**:
   ```bash
   # Get dashboard URL
   terraform output cloudwatch_dashboard_url
   ```

2. **Check Flow Status**:
   ```bash
   aws mediaconnect describe-flow --flow-arn $(terraform output -raw mediaconnect_flow_arn)
   ```

3. **Monitor Workflow Executions**:
   ```bash
   # Get Step Functions URL
   terraform output step_functions_console_url
   ```

### Testing the Alert System

1. **Manual Workflow Trigger**:
   ```bash
   aws stepfunctions start-execution \
     --state-machine-arn $(terraform output -raw step_functions_state_machine_arn) \
     --input '{"flow_arn":"'$(terraform output -raw mediaconnect_flow_arn)'"}'
   ```

2. **Check Alert Delivery**:
   Monitor your email for test notifications

## Security Considerations

### Network Security
- **Whitelist Configuration**: Always restrict `source_whitelist_cidr` to known encoder IPs
- **Output Destinations**: Ensure output IPs are within your secure network
- **Port Management**: Use non-standard ports and firewall appropriately

### Access Control
- **IAM Roles**: All services use least-privilege IAM roles
- **Resource Tags**: All resources are tagged for governance
- **Encryption**: S3 bucket uses server-side encryption

### Monitoring Security
- **SNS Topics**: Secured with resource-based policies
- **CloudWatch Logs**: Retention set to 14 days to control costs
- **Lambda Functions**: No hardcoded credentials or secrets

## Cost Optimization

### Expected Costs (per month)
- **MediaConnect**: ~$50-100 (varies by bandwidth)
- **Lambda**: ~$1-5 (based on executions)
- **Step Functions**: ~$1-3 (EXPRESS workflows)
- **CloudWatch**: ~$5-15 (metrics, alarms, dashboards)
- **SNS**: <$1 (notification delivery)
- **S3**: <$1 (Lambda artifacts)

### Cost Control Strategies
1. **Monitor Usage**: Use AWS Cost Explorer to track spending
2. **Optimize Thresholds**: Reduce false alarms to minimize executions
3. **Log Retention**: Adjust CloudWatch log retention as needed
4. **Flow Management**: Stop flows when not actively streaming

## Troubleshooting

### Common Issues

**Stream Not Connecting**:
- Verify encoder IP is in whitelist CIDR
- Check encoder configuration matches ingest details
- Ensure network connectivity and firewall rules

**No Alerts Received**:
- Confirm SNS subscription in email
- Check CloudWatch alarms are in ALARM state
- Verify Lambda function logs for errors

**Workflow Failures**:
- Check Step Functions execution history
- Review Lambda function CloudWatch logs
- Verify IAM permissions are correctly configured

### Debug Commands

```bash
# Check flow status
aws mediaconnect describe-flow --flow-arn $(terraform output -raw mediaconnect_flow_arn)

# View recent Lambda logs
aws logs describe-log-streams \
  --log-group-name "/aws/lambda/$(terraform output -raw stream_monitor_lambda_name)" \
  --order-by LastEventTime --descending

# Check alarm states
aws cloudwatch describe-alarms \
  --alarm-names $(terraform output -raw packet_loss_alarm_name)

# List recent Step Functions executions
aws stepfunctions list-executions \
  --state-machine-arn $(terraform output -raw step_functions_state_machine_arn) \
  --max-items 10
```

## Customization

### Adding Custom Metrics
Edit `lambda/stream-monitor.py` to include additional CloudWatch metrics:
```python
# Example: Add custom threshold checking
if custom_metric_value > custom_threshold:
    issues.append({
        'metric': 'CustomMetric',
        'value': custom_metric_value,
        'threshold': custom_threshold,
        'severity': 'HIGH'
    })
```

### Modifying Alert Content
Edit `lambda/alert-handler.py` to customize notification messages:
```python
# Add custom message sections
message_lines.extend([
    "Custom Section:",
    f"Additional context: {custom_data}",
    ""
])
```

### Extending the Workflow
Modify `stepfunctions/state-machine.json` to add new states:
```json
{
  "CustomAction": {
    "Type": "Task",
    "Resource": "arn:aws:lambda:region:account:function:custom-function",
    "Next": "NextState"
  }
}
```

## Cleanup

To remove all infrastructure:

```bash
terraform destroy
```

**Note**: This will permanently delete all created resources including MediaConnect flows, Lambda functions, and CloudWatch data.

## Support and Maintenance

### Regular Maintenance Tasks
1. **Update Lambda Runtime**: Keep Python runtime current
2. **Review Thresholds**: Adjust based on operational experience
3. **Monitor Costs**: Check AWS billing monthly
4. **Test Alerts**: Verify notification delivery quarterly

### Backup and Recovery
- **Terraform State**: Ensure state file is backed up
- **Configuration**: Version control all `.tfvars` files
- **Documentation**: Keep this README updated with any customizations

For additional support, refer to:
- [AWS MediaConnect User Guide](https://docs.aws.amazon.com/mediaconnect/latest/ug/)
- [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/latest/dg/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)