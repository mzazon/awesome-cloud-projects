# Infrastructure as Code for Network Security Monitoring with VPC Flow Logs and Cloud Security Command Center

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Network Security Monitoring with VPC Flow Logs and Cloud Security Command Center". This solution provides comprehensive network visibility and threat detection capabilities using Google Cloud's native security services.

## Solution Overview

This infrastructure implements an automated network security monitoring solution that:

- **Captures Network Traffic**: VPC Flow Logs with 100% sampling and 5-second aggregation intervals
- **Stores and Analyzes Data**: BigQuery dataset for long-term storage and SQL-based analysis
- **Detects Threats**: Cloud Monitoring alert policies for anomalous traffic patterns
- **Centralizes Security**: Security Command Center integration for unified threat visibility
- **Generates Test Traffic**: Automated test instances for validation and demonstration

## Available Implementations

- **🏗️ Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **🚀 Terraform**: Multi-cloud infrastructure as code with comprehensive resource management
- **⚡ Bash Scripts**: Automated deployment and cleanup scripts with interactive setup

## Prerequisites

### Common Requirements

- Google Cloud account with appropriate permissions
- Google Cloud CLI (`gcloud`) installed and configured
- Billing enabled on your Google Cloud project
- The following APIs enabled:
  - Compute Engine API
  - Cloud Logging API
  - Cloud Monitoring API
  - Security Command Center API
  - BigQuery API

### Required IAM Permissions

Your account or service account needs these roles:
- `roles/compute.admin` - For VPC and VM management
- `roles/logging.admin` - For log sink configuration
- `roles/monitoring.admin` - For alert policy management
- `roles/bigquery.admin` - For dataset creation
- `roles/securitycenter.admin` - For Security Command Center integration
- `roles/pubsub.admin` - For notification topics

### Cost Estimates

**Monthly costs** (approximate, based on US regions):
- VPC Flow Logs: $10-30 (varies by traffic volume)
- BigQuery storage: $5-15 (varies by retention period)
- Cloud Monitoring: $5-10 (based on metrics and alerts)
- Compute Engine (test instances): $10-20
- **Total estimated cost**: $30-75/month

> **💡 Tip**: Use the [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator) for precise cost estimates based on your expected traffic volumes.

## Quick Start

### Option 1: Using Infrastructure Manager (Recommended for Google Cloud)

Infrastructure Manager is Google Cloud's native IaC service that provides GitOps workflows and preview capabilities.

```bash
# Navigate to the Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments create network-security-monitoring \
    --location=${REGION} \
    --source-blueprint=main.yaml \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment progress
gcloud infra-manager deployments describe network-security-monitoring \
    --location=${REGION}
```

### Option 2: Using Terraform

Terraform provides cross-platform compatibility and extensive provider ecosystem.

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

For detailed Terraform configuration options, see the [Terraform README](terraform/README.md).

### Option 3: Using Bash Scripts

Automated scripts provide interactive deployment with built-in validation.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run the deployment script
./scripts/deploy.sh

# Follow the interactive prompts for configuration
```

The deployment script will:
1. Validate prerequisites and permissions
2. Set up environment variables
3. Create all infrastructure resources
4. Configure monitoring and alerting
5. Generate test traffic for validation
6. Provide verification commands

## Post-Deployment Validation

### 1. Verify VPC Flow Logs Collection

```bash
# Check that flow logs are being generated
gcloud logging read 'resource.type="gce_subnetwork" AND 
                    jsonPayload.connection.src_ip!=""' \
    --limit=5 \
    --format="table(timestamp,jsonPayload.connection.src_ip,jsonPayload.connection.dest_ip)"
```

### 2. Query VPC Flow Logs in BigQuery

```bash
# Set your project ID
export PROJECT_ID=$(gcloud config get-value project)

# Query recent flow logs
bq query --use_legacy_sql=false \
    "SELECT 
        timestamp,
        jsonPayload.connection.src_ip as source_ip,
        jsonPayload.connection.dest_ip as destination_ip,
        jsonPayload.connection.protocol,
        jsonPayload.bytes_sent
     FROM \`${PROJECT_ID}.security_monitoring.compute_googleapis_com_vpc_flows_*\`
     WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
     ORDER BY timestamp DESC
     LIMIT 10"
```

### 3. Test Security Monitoring Alerts

```bash
# Get test instance external IP
INSTANCE_IP=$(gcloud compute instances describe security-test-vm \
    --zone=us-central1-a \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

# Generate test traffic to trigger alerts
for i in {1..50}; do
    curl -s http://${INSTANCE_IP}/ > /dev/null
    sleep 1
done
```

### 4. View Security Command Center Findings

```bash
# List recent security findings
gcloud scc findings list \
    --source=projects/YOUR_PROJECT_ID/sources/YOUR_SOURCE_ID \
    --filter="category:\"Network Security\""
```

## Advanced Analytics Queries

### Detect High-Volume Connections

```sql
SELECT 
    jsonPayload.connection.src_ip,
    jsonPayload.connection.dest_ip,
    COUNT(*) as connection_count,
    SUM(CAST(jsonPayload.bytes_sent AS INT64)) as total_bytes
FROM `your-project.security_monitoring.compute_googleapis_com_vpc_flows_*`
WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
GROUP BY 1, 2
HAVING connection_count > 100
ORDER BY total_bytes DESC
```

### Identify Unusual Port Access

```sql
SELECT 
    jsonPayload.connection.dest_port,
    COUNT(DISTINCT jsonPayload.connection.src_ip) as unique_sources,
    COUNT(*) as total_connections
FROM `your-project.security_monitoring.compute_googleapis_com_vpc_flows_*`
WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
  AND jsonPayload.connection.dest_port NOT IN ('80', '443', '22')
GROUP BY 1
HAVING unique_sources > 5
ORDER BY total_connections DESC
```

## Monitoring and Alerting

### Cloud Monitoring Dashboard

Access your monitoring dashboard at:
```
https://console.cloud.google.com/monitoring/dashboards/custom/[DASHBOARD_ID]
```

The dashboard includes:
- Network traffic volume metrics
- VPC Flow Logs ingestion rates
- Alert policy status
- Security finding trends

### Alert Policies Configured

1. **High Network Traffic Alert**: Triggers when egress traffic exceeds 1GB in 5 minutes
2. **Suspicious Connection Patterns**: Alerts on unusual connection frequencies
3. **External SSH Access**: Monitors SSH connections from external IPs
4. **Potential Data Exfiltration**: Detects large outbound transfers

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete network-security-monitoring \
    --location=${REGION} \
    --delete-policy=DELETE
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

The cleanup process will:
1. Remove all compute instances
2. Delete VPC networks and subnets
3. Remove BigQuery datasets and tables
4. Delete Cloud Monitoring alert policies
5. Clean up IAM service accounts
6. Remove Pub/Sub topics and subscriptions

> **⚠️ Warning**: Cleanup will permanently delete all monitoring data. Export any required logs before running cleanup commands.

## Customization

### Key Configuration Parameters

| Parameter | Description | Default | Customization Notes |
|-----------|-------------|---------|-------------------|
| `project_id` | Google Cloud Project ID | Current project | Required for all deployments |
| `region` | Deployment region | `us-central1` | Choose region closest to users |
| `zone` | VM deployment zone | `us-central1-a` | Must be in selected region |
| `flow_logs_sampling` | Flow logs sampling rate | `1.0` (100%) | Reduce for cost optimization |
| `log_retention_days` | BigQuery log retention | `30` | Increase for compliance requirements |
| `alert_notification_email` | Email for alerts | None | Required for alert notifications |

### Environment-Specific Configurations

#### Development Environment
```bash
# Reduced sampling for cost optimization
export FLOW_LOGS_SAMPLING="0.1"
export VM_MACHINE_TYPE="e2-micro"
export LOG_RETENTION_DAYS="7"
```

#### Production Environment
```bash
# Maximum monitoring coverage
export FLOW_LOGS_SAMPLING="1.0"
export VM_MACHINE_TYPE="e2-standard-2"
export LOG_RETENTION_DAYS="90"
export ENABLE_CROSS_REGION_BACKUP="true"
```

## Security Considerations

### Network Security
- VPC networks use private IP ranges (RFC 1918)
- Firewall rules follow least privilege principle
- SSH access restricted to specific source ranges
- Internal communication encrypted in transit

### Data Protection
- VPC Flow Logs contain potentially sensitive network metadata
- BigQuery datasets use Google-managed encryption at rest
- Log retention policies comply with data governance requirements
- IAM roles follow principle of least privilege

### Monitoring Security
- Service accounts use minimal required permissions
- Alert policies prevent information disclosure
- Security Command Center findings are access-controlled
- Audit logs track all configuration changes

## Troubleshooting

### Common Issues

#### VPC Flow Logs Not Appearing
```bash
# Check subnet flow logs configuration
gcloud compute networks subnets describe your-subnet \
    --region=your-region \
    --format="get(enableFlowLogs,logConfig)"

# Verify required APIs are enabled
gcloud services list --enabled | grep -E "(compute|logging)"
```

#### BigQuery Access Denied
```bash
# Check BigQuery permissions
gcloud projects get-iam-policy YOUR_PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.role:roles/bigquery"

# Verify log sink service account permissions
gcloud logging sinks describe vpc-flow-security-sink \
    --format="get(writerIdentity)"
```

#### No Security Findings Generated
```bash
# Verify Security Command Center is enabled
gcloud services list --enabled | grep securitycenter

# Check for organization-level permissions
gcloud organizations get-iam-policy YOUR_ORG_ID
```

### Performance Optimization

#### Reduce VPC Flow Logs Costs
```bash
# Adjust sampling rate (0.1 = 10% sampling)
gcloud compute networks subnets update your-subnet \
    --region=your-region \
    --flow-logs-sampling=0.1
```

#### Optimize BigQuery Performance
```sql
-- Partition flow logs table by date for better query performance
CREATE TABLE `your-project.security_monitoring.vpc_flows_partitioned`
PARTITION BY DATE(timestamp)
AS SELECT * FROM `your-project.security_monitoring.compute_googleapis_com_vpc_flows_*`
```

## Support and Resources

### Documentation Links
- [VPC Flow Logs Documentation](https://cloud.google.com/vpc/docs/flow-logs)
- [Security Command Center Guide](https://cloud.google.com/security-command-center/docs)
- [Cloud Monitoring Best Practices](https://cloud.google.com/monitoring/best-practices)
- [BigQuery for Security Analytics](https://cloud.google.com/bigquery/docs/security-analytics)

### Community Resources
- [Google Cloud Security Community](https://cloud.google.com/community)
- [Cloud Security Automation Examples](https://github.com/GoogleCloudPlatform/security-analytics)

### Professional Services
- [Google Cloud Professional Services](https://cloud.google.com/consulting)
- [Google Cloud Security Specialists](https://cloud.google.com/security/partners)

---

**📋 Recipe Information**
- **Recipe ID**: f7a8b3e2
- **Difficulty Level**: 200 (Intermediate)
- **Estimated Deployment Time**: 30-45 minutes
- **Recipe Version**: 1.0
- **Last Updated**: 2025-07-12

For issues with this infrastructure code, refer to the [original recipe documentation](../network-security-monitoring-vpc-flow-logs-security-command-center.md) or consult the Google Cloud documentation links provided above.