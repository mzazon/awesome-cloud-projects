# Network Security Monitoring with VPC Flow Logs - Terraform Infrastructure

This Terraform configuration deploys a comprehensive network security monitoring solution on Google Cloud Platform using VPC Flow Logs, Cloud Logging, Cloud Monitoring, and Security Command Center integration.

## Architecture Overview

This infrastructure creates:

- **VPC Network**: Custom VPC with comprehensive flow logging enabled
- **Subnet**: Monitored subnet with VPC Flow Logs configured
- **Test VM Instance**: Ubuntu instance for traffic generation and testing
- **Firewall Rules**: Security rules for SSH, HTTP, and internal communication
- **BigQuery Dataset**: Storage for VPC Flow Logs analysis
- **Logging Sink**: Routes VPC Flow Logs to BigQuery
- **Cloud Monitoring**: Alert policies and dashboard for security monitoring
- **Pub/Sub Topic**: For Security Command Center notifications

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud CLI** installed and configured
2. **Terraform** version 1.5.0 or higher
3. **Google Cloud Project** with billing enabled
4. **Required APIs** enabled (handled automatically by Terraform)
5. **Appropriate IAM permissions** for resource creation

### Required IAM Roles

Your user or service account needs these roles:

```bash
# Project-level roles
roles/compute.admin
roles/logging.admin
roles/monitoring.admin
roles/bigquery.admin
roles/pubsub.admin
roles/iam.serviceAccountAdmin
roles/serviceusage.serviceUsageAdmin
```

## Quick Start

### 1. Clone and Navigate

```bash
cd gcp/network-security-monitoring-vpc-flow-logs-security-command-center/code/terraform/
```

### 2. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your project details
nano terraform.tfvars
```

**Important**: Update at least these variables:
- `project_id`: Your GCP project ID
- `notification_emails`: Your email for alerts
- `allowed_ssh_sources`: Restrict SSH access appropriately

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Access Your Resources

After deployment, Terraform will output useful information including:
- VM instance details and SSH commands
- BigQuery dataset information
- Monitoring dashboard URLs
- Sample queries for log analysis

## Configuration Options

### Core Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP project ID | `null` | Yes |
| `region` | GCP region | `us-central1` | No |
| `zone` | GCP zone | `us-central1-a` | No |
| `environment` | Environment name | `dev` | No |

### Network Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `vpc_name` | VPC network name | `security-monitoring-vpc` | No |
| `subnet_name` | Subnet name | `monitored-subnet` | No |
| `subnet_cidr` | Subnet CIDR block | `10.0.1.0/24` | No |
| `allowed_ssh_sources` | SSH source ranges | `["0.0.0.0/0"]` | No |

### Monitoring Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_monitoring_alerts` | Enable alert policies | `true` | No |
| `notification_emails` | Alert notification emails | `[]` | No |
| `high_traffic_threshold_bytes` | High traffic alert threshold | `1000000000` | No |
| `suspicious_connections_threshold` | Suspicious connections threshold | `100` | No |

### Flow Logs Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_flow_logs` | Enable VPC Flow Logs | `true` | No |
| `flow_log_sampling_rate` | Sampling rate (0.0-1.0) | `1.0` | No |
| `flow_log_aggregation_interval` | Aggregation interval | `INTERVAL_5_SEC` | No |

## Post-Deployment

### Verify Deployment

1. **Check VPC Flow Logs**:
   ```bash
   gcloud logging read 'resource.type="gce_subnetwork"' --limit=5
   ```

2. **Test BigQuery Access**:
   ```bash
   bq query --use_legacy_sql=false "SELECT COUNT(*) FROM \`PROJECT_ID.security_monitoring_SUFFIX.compute_googleapis_com_vpc_flows_*\`"
   ```

3. **Generate Test Traffic**:
   ```bash
   # SSH to the test VM
   gcloud compute ssh test-vm-SUFFIX --zone=us-central1-a
   
   # Run traffic generation script
   /usr/local/bin/generate-test-traffic.sh
   ```

### Access Monitoring Resources

- **BigQuery Console**: Use the `bigquery_console_url` output
- **Monitoring Dashboard**: Use the `monitoring_console_url` output
- **VM Web Server**: Use the `web_server_url` output

### Sample BigQuery Queries

#### Basic Flow Log Analysis
```sql
SELECT 
  timestamp,
  jsonPayload.connection.src_ip,
  jsonPayload.connection.dest_ip,
  jsonPayload.connection.protocol,
  jsonPayload.bytes_sent
FROM `PROJECT_ID.security_monitoring_SUFFIX.compute_googleapis_com_vpc_flows_*`
WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
ORDER BY timestamp DESC
LIMIT 100
```

#### Top Talkers Analysis
```sql
SELECT 
  jsonPayload.connection.src_ip,
  COUNT(*) as connection_count,
  SUM(CAST(jsonPayload.bytes_sent AS INT64)) as total_bytes
FROM `PROJECT_ID.security_monitoring_SUFFIX.compute_googleapis_com_vpc_flows_*`
WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
GROUP BY jsonPayload.connection.src_ip
ORDER BY connection_count DESC
LIMIT 20
```

## Security Considerations

### Production Hardening

1. **Restrict SSH Access**:
   ```hcl
   allowed_ssh_sources = ["YOUR_OFFICE_IP/32"]
   ```

2. **Enable OS Login**:
   ```hcl
   enable_oslogin = true
   ```

3. **Use Private Instances**:
   ```hcl
   enable_cloud_nat = true
   # Remove external IP from instances
   ```

4. **Enable Confidential Computing**:
   ```hcl
   enable_confidential_computing = true
   ```

### Cost Optimization

1. **Use Preemptible Instances**:
   ```hcl
   enable_preemptible_instances = true
   ```

2. **Adjust Flow Log Sampling**:
   ```hcl
   flow_log_sampling_rate = 0.1  # 10% sampling
   ```

3. **Set Log Retention**:
   ```hcl
   log_retention_days = 7  # Shorter retention
   ```

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   - Verify IAM roles are correctly assigned
   - Check that APIs are enabled

2. **Flow Logs Not Appearing**:
   - Ensure VM is generating traffic
   - Check flow log configuration on subnet
   - Verify logging sink configuration

3. **BigQuery Access Issues**:
   - Verify dataset permissions
   - Check logging sink service account permissions

4. **Monitoring Alerts Not Firing**:
   - Verify notification channels are configured
   - Check alert policy thresholds
   - Generate sufficient test traffic

### Debug Commands

```bash
# Check flow logs
gcloud logging read 'resource.type="gce_subnetwork"' --limit=5

# Check VM logs
gcloud logging read 'resource.type="gce_instance"' --limit=10

# Check BigQuery datasets
bq ls -d

# Check alert policies
gcloud alpha monitoring policies list

# Test VM connectivity
gcloud compute ssh test-vm-SUFFIX --zone=us-central1-a --command="curl -s http://www.google.com"
```

## Cleanup

To destroy all created resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all resources and data. Make sure to backup any important data from BigQuery before destroying.

## Cost Estimation

Estimated monthly costs for this setup:

- **Compute Instance (e2-micro)**: ~$5-10
- **VPC Flow Logs**: ~$0.50 per GB generated
- **BigQuery Storage**: ~$0.02 per GB (first 10GB free)
- **Cloud Monitoring**: ~$0.258 per metric (first 150 free)
- **Total**: ~$10-20/month for light usage

**Note**: Costs vary significantly based on traffic volume and log generation rates.

## Support and Contributing

For issues or questions:

1. Check the [troubleshooting section](#troubleshooting)
2. Review Google Cloud documentation
3. Check Terraform provider documentation

## License

This infrastructure code is provided as-is for educational and demonstration purposes.