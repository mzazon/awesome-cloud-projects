# Terraform Infrastructure for GCP Disaster Recovery with Cloud WAN and Parallelstore

This Terraform configuration deploys a comprehensive disaster recovery solution for high-performance computing (HPC) workloads using Google Cloud Platform's Network Connectivity Center (Cloud WAN), Parallelstore, Cloud Workflows, and Cloud Monitoring.

## Architecture Overview

The solution implements:

- **Multi-region VPC networks** with optimized subnetting for HPC workloads
- **Network Connectivity Center hub** providing Cloud WAN functionality
- **HA VPN connectivity** with BGP routing between regions
- **Parallelstore instances** (100 TiB each) for high-performance storage
- **Cloud Functions** for health monitoring and automated replication
- **Cloud Workflows** for disaster recovery orchestration
- **Cloud Monitoring** with intelligent alerting policies
- **Pub/Sub messaging** for event-driven automation
- **Cloud Scheduler** for automated replication jobs

## Prerequisites

1. **Google Cloud Project** with billing enabled
2. **APIs Enabled**:
   - Compute Engine API
   - Cloud Workflows API
   - Cloud Monitoring API
   - Parallelstore API (requires allowlist access)
   - Pub/Sub API
   - Cloud Functions API
   - Network Connectivity API
   - Cloud Scheduler API

3. **Terraform** v1.5.0 or later
4. **gcloud CLI** v450.0.0 or later, authenticated and configured
5. **Parallelstore Access**: Contact Google Cloud sales for allowlist approval

## Quick Start

1. **Clone and Configure**:
   ```bash
   # Copy the example variables file
   cp terraform.tfvars.example terraform.tfvars
   
   # Edit terraform.tfvars with your project settings
   vim terraform.tfvars
   ```

2. **Initialize and Plan**:
   ```bash
   # Initialize Terraform
   terraform init
   
   # Review the execution plan
   terraform plan
   ```

3. **Deploy Infrastructure**:
   ```bash
   # Apply the configuration
   terraform apply
   
   # Confirm with 'yes' when prompted
   ```

4. **Verify Deployment**:
   ```bash
   # Check Parallelstore instances
   gcloud parallelstore instances list
   
   # Verify VPN connectivity
   gcloud compute vpn-tunnels list
   
   # Check workflow status
   gcloud workflows list
   ```

## Configuration

### Required Variables

```hcl
project_id = "your-gcp-project-id"
```

### Important Configuration Options

- **Parallelstore Capacity**: Minimum 12 TiB, scales to petabytes
- **Replication Schedule**: Default every 15 minutes, customizable
- **Monitoring Thresholds**: Configurable lag and performance alerts
- **Security Settings**: Deletion protection and audit logging options

### Cost Considerations

- **Parallelstore**: ~$0.60/GiB/month per instance
- **VPN Gateways**: ~$36/month for HA VPN pair
- **Cloud Functions**: Pay-per-invocation model
- **Monitoring**: Based on metrics volume and alerting frequency

Estimated monthly cost for default configuration: $1,440-2,160

## Usage Examples

### Trigger Manual Failover

```bash
# Execute disaster recovery workflow
gcloud workflows run hpc-dr-XXXX-dr-orchestrator \
    --location=us-central1 \
    --data='{"trigger":"manual_failover","severity":"critical"}'
```

### Test Health Monitoring

```bash
# Get health monitoring function URL
HEALTH_URL=$(terraform output -raw health_monitor_function_url)

# Invoke health check
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
     -X GET "$HEALTH_URL"
```

### Monitor Replication Status

```bash
# Check recent workflow executions
gcloud workflows executions list \
    --workflow=hpc-dr-XXXX-dr-orchestrator \
    --location=us-central1 \
    --limit=5
```

## Mounting Parallelstore

After deployment, mount Parallelstore on your compute instances:

```bash
# Primary region mount
sudo mount -t lustre \
    $(terraform output -raw primary_parallelstore_access_points | jq -r '.[0].network_endpoint'):/ \
    /mnt/parallelstore-primary

# Secondary region mount
sudo mount -t lustre \
    $(terraform output -raw secondary_parallelstore_access_points | jq -r '.[0].network_endpoint'):/ \
    /mnt/parallelstore-secondary
```

## Monitoring and Alerting

The solution includes comprehensive monitoring:

- **Parallelstore Health**: Instance state and performance metrics
- **Replication Lag**: Data synchronization delays
- **Network Performance**: VPN tunnel status and throughput
- **Workflow Execution**: Disaster recovery automation status

Access monitoring dashboards in the [Google Cloud Console](https://console.cloud.google.com/monitoring).

## Troubleshooting

### Common Issues

1. **Parallelstore Access Denied**:
   - Ensure your project is allowlisted for Parallelstore
   - Contact Google Cloud support for access

2. **VPN Tunnels Not Connecting**:
   - Verify BGP ASN values are unique
   - Check firewall rules allow VPN traffic

3. **Function Deployment Fails**:
   - Ensure Cloud Build API is enabled
   - Verify service account permissions

4. **Workflow Execution Errors**:
   - Check Cloud Workflows logs
   - Verify Pub/Sub topic permissions

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled

# Verify Parallelstore quota
gcloud parallelstore instances describe INSTANCE_NAME \
    --location=ZONE

# Monitor workflow logs
gcloud logging read 'resource.type="cloud_workflow"' \
    --limit=50 --format=json
```

## Security Considerations

- **Service Accounts**: Principle of least privilege applied
- **Network Security**: Private Google Access enabled
- **Data Encryption**: Encryption at rest and in transit
- **Access Control**: IAM roles for function and workflow access
- **Audit Logging**: Comprehensive activity tracking

## Customization

### Adding Custom Metrics

Extend the health monitoring function in `functions/health_monitor.py`:

```python
def check_custom_metrics(client):
    # Add your custom health checks
    return {"status": "healthy", "custom_metric": value}
```

### Modifying Replication Logic

Update replication behavior in `functions/replication.py`:

```python
def custom_replication_logic():
    # Implement custom data synchronization
    pass
```

### Workflow Customization

Modify disaster recovery procedures in `workflows/dr_orchestration.yaml`:

```yaml
- custom_recovery_step:
    call: your.custom.api
    args:
      parameter: value
```

## Cleanup

To destroy all resources:

```bash
# Destroy infrastructure
terraform destroy

# Confirm with 'yes' when prompted
```

**Warning**: This will permanently delete all data in Parallelstore instances. Ensure you have backups before proceeding.

## Support and Resources

- [Parallelstore Documentation](https://cloud.google.com/parallelstore/docs)
- [Network Connectivity Center](https://cloud.google.com/network-connectivity/docs/network-connectivity-center)
- [Cloud Workflows](https://cloud.google.com/workflows/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

For issues with this Terraform configuration, refer to the [original recipe documentation](../disaster-recovery-cloud-wan-parallelstore.md) or contact your cloud infrastructure team.