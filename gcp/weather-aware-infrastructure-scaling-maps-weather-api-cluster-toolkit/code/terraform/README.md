# Weather-Aware Infrastructure Scaling - Terraform Implementation

This Terraform implementation creates a weather-aware High Performance Computing (HPC) infrastructure on Google Cloud Platform that automatically scales based on real-time weather data from Google Maps Platform Weather API.

## Architecture Overview

The solution deploys:

- **Weather Processing**: Cloud Function that analyzes weather data and generates scaling decisions
- **HPC Cluster**: Auto-scaling compute cluster with Slurm job scheduler
- **Storage**: Cloud Storage for weather data and Filestore for shared cluster storage
- **Messaging**: Pub/Sub for reliable scaling event distribution
- **Monitoring**: Cloud Monitoring with custom dashboards and alerts
- **Automation**: Cloud Scheduler for regular weather data collection
- **Security**: KMS encryption, Secret Manager, and IAM controls

## Prerequisites

1. **Google Cloud Account**: Project with billing enabled
2. **APIs Enabled**: Required APIs will be enabled automatically by Terraform
3. **Terraform**: Version 1.0 or later
4. **Google Cloud CLI**: Configured with appropriate permissions
5. **Weather API Key**: Google Maps Platform Weather API key

### Required Permissions

Your Google Cloud account needs these IAM roles:
- `roles/owner` or `roles/editor` (for comprehensive resource management)
- `roles/compute.admin` (for compute resources)
- `roles/storage.admin` (for storage resources)
- `roles/pubsub.admin` (for messaging)
- `roles/cloudfunctions.admin` (for Cloud Functions)
- `roles/monitoring.admin` (for monitoring resources)

## Quick Start

### 1. Clone and Setup

```bash
# Clone the repository (if not already done)
git clone <repository-url>
cd gcp/weather-aware-infrastructure-scaling-maps-weather-api-cluster-toolkit/code/terraform

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id      = "your-project-id"
weather_api_key = "your-weather-api-key"

# Optional customization
region                  = "us-central1"
zone                   = "us-central1-a"
cluster_name           = "weather-hpc-cluster"
cluster_machine_type   = "c2-standard-60"
cluster_max_nodes      = 20
cluster_min_nodes      = 2
enable_spot_instances  = true
filestore_capacity_gb  = 1024
budget_amount         = 1000

# Weather monitoring locations (optional)
weather_monitoring_locations = [
  {
    name      = "us-east1"
    latitude  = 39.0458
    longitude = -76.6413
    region    = "us-east1"
  },
  {
    name      = "us-central1"
    latitude  = 41.2619
    longitude = -95.8608
    region    = "us-central1"
  },
  {
    name      = "us-west1"
    latitude  = 45.5152
    longitude = -122.6784
    region    = "us-west1"
  }
]

# Labels for resource organization
labels = {
  environment = "production"
  application = "weather-aware-hpc"
  team        = "research"
  cost-center = "engineering"
}
```

### 3. Deploy Infrastructure

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# Confirm deployment when prompted
# Enter 'yes' to proceed
```

### 4. Verify Deployment

```bash
# Check cluster status
gcloud compute instances list --filter="name~'hpc-node'"

# Test weather function
curl -X GET $(terraform output -raw weather_function_url)

# View weather data
gsutil ls $(terraform output -raw weather_data_bucket)/weather-data/

# Check monitoring dashboard
echo "Dashboard URL: $(terraform output -raw monitoring_dashboard_url)"
```

## Configuration

### Core Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `weather_api_key` | Google Maps Platform Weather API key | - | Yes |
| `region` | Google Cloud region | `us-central1` | No |
| `zone` | Google Cloud zone | `us-central1-a` | No |

### Cluster Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `cluster_name` | HPC cluster name | `weather-hpc-cluster` | No |
| `cluster_machine_type` | Machine type for compute nodes | `c2-standard-60` | No |
| `cluster_max_nodes` | Maximum cluster nodes | `20` | No |
| `cluster_min_nodes` | Minimum cluster nodes | `2` | No |
| `enable_spot_instances` | Use spot instances for cost savings | `true` | No |

### Storage Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `filestore_capacity_gb` | Shared storage capacity | `1024` | No |
| `filestore_tier` | Filestore performance tier | `STANDARD` | No |

### Monitoring Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `weather_check_schedule` | Regular weather check cron | `*/15 * * * *` | No |
| `storm_monitor_schedule` | Storm monitoring cron | `*/5 * * * *` | No |
| `budget_amount` | Monthly budget in USD | `1000` | No |

### Security Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_iap` | Enable Identity-Aware Proxy | `true` | No |
| `authorized_networks` | Authorized network CIDRs | `["0.0.0.0/0"]` | No |
| `deletion_protection` | Enable deletion protection | `true` | No |

## Weather Monitoring Locations

The system monitors weather conditions at multiple geographic locations. Each location is configured with:

- **Name**: Identifier for the location
- **Latitude/Longitude**: Geographic coordinates
- **Region**: Associated Google Cloud region

Default locations monitor major data center regions:
- US East (Virginia): 39.0458°N, -76.6413°W
- US Central (Iowa): 41.2619°N, -95.8608°W
- US West (Oregon): 45.5152°N, -122.6784°W

## Scaling Logic

The weather-aware scaling system uses the following logic:

### Precipitation Scaling
- Heavy precipitation (>10mm): 1.5x scaling factor
- Moderate precipitation (5-10mm): 1.2x scaling factor
- Light precipitation (<5mm): 1.0x scaling factor

### Wind Speed Scaling
- Strong winds (>50 km/h): 1.4x scaling factor
- Moderate winds (30-50 km/h): 1.1x scaling factor
- Light winds (<30 km/h): 1.0x scaling factor

### Temperature Variance Scaling
- High variance (>25°C²): 1.3x scaling factor
- Moderate variance (10-25°C²): 1.1x scaling factor
- Low variance (<10°C²): 1.0x scaling factor

### Humidity Scaling
- High humidity (>80%): 1.2x scaling factor
- Moderate humidity (60-80%): 1.0x scaling factor
- Low humidity (<60%): 1.0x scaling factor

**Maximum Scaling**: All factors are capped at 2.0x for cost control.

## Outputs

After deployment, Terraform provides these key outputs:

```bash
# Network information
terraform output network_name
terraform output subnet_cidr

# Storage information
terraform output weather_data_bucket
terraform output filestore_ip_address

# Function information
terraform output weather_function_url

# Cluster information
terraform output cluster_name
terraform output cluster_instance_group_manager

# Monitoring information
terraform output monitoring_dashboard_url

# Sample commands
terraform output sample_commands
```

## Operations

### Testing Weather Function

```bash
# Manual weather function trigger
curl -X GET $(terraform output -raw weather_function_url)

# Check function logs
gcloud functions logs read weather-processor-$(terraform output -raw random_suffix) --region=$(terraform output -raw region)
```

### Monitoring Weather Data

```bash
# List weather data files
gsutil ls $(terraform output -raw weather_data_bucket)/weather-data/

# Download recent weather data
gsutil cp $(terraform output -raw weather_data_bucket)/weather-data/us-central1/$(date +%Y%m%d)*.json .

# View scaling messages
gcloud pubsub subscriptions pull $(terraform output -raw pubsub_subscription_name) --auto-ack
```

### Cluster Operations

```bash
# Check cluster status
gcloud compute instances list --filter="name~'hpc-node'"

# View cluster metrics
gcloud compute instance-groups managed describe $(terraform output -raw cluster_instance_group_manager) --region=$(terraform output -raw region)

# Scale cluster manually (if needed)
gcloud compute instance-groups managed resize $(terraform output -raw cluster_instance_group_manager) --size=5 --region=$(terraform output -raw region)
```

### Monitoring Dashboard

Access the monitoring dashboard:
```bash
echo "Dashboard URL: $(terraform output -raw monitoring_dashboard_url)"
```

The dashboard shows:
- Weather scaling factors by region
- Cluster CPU utilization
- Custom weather metrics
- Scaling events timeline

## Cost Management

### Budget Alerts

The system creates a budget with alerts at:
- 50% of budget threshold
- 80% of budget threshold
- 90% of budget threshold
- 100% of budget threshold

### Cost Optimization

1. **Spot Instances**: Enable `enable_spot_instances = true` for 60-91% cost savings
2. **Right-sizing**: Adjust `cluster_machine_type` based on workload requirements
3. **Auto-scaling**: Configure `cluster_min_nodes` and `cluster_max_nodes` appropriately
4. **Storage Tiers**: Use appropriate `filestore_tier` for performance vs. cost balance

### Monitoring Costs

```bash
# View current costs
gcloud billing budgets list --billing-account=$(gcloud billing accounts list --filter="open:true" --format="value(name)")

# Check resource usage
gcloud compute instances list --format="table(name,status,machineType,zone)"
```

## Security

### Encryption
- **Data at Rest**: All storage encrypted with customer-managed KMS keys
- **Data in Transit**: HTTPS/TLS for all communications
- **Secrets**: API keys stored in Secret Manager

### Access Control
- **IAM**: Least privilege access for all service accounts
- **Network Security**: Firewall rules restrict access to cluster resources
- **Identity-Aware Proxy**: Optional IAP for secure access without VPN

### Monitoring
- **Cloud Logging**: All activities logged for audit trail
- **Cloud Monitoring**: Security metrics and alerts
- **Access Transparency**: Optional transparency logs for Google access

## Troubleshooting

### Common Issues

1. **Weather Function Errors**
   ```bash
   # Check function logs
   gcloud functions logs read weather-processor-$(terraform output -raw random_suffix) --region=$(terraform output -raw region)
   
   # Verify API key
   gcloud secrets versions access latest --secret=$(terraform output -raw weather_api_secret_name)
   ```

2. **Cluster Nodes Not Starting**
   ```bash
   # Check startup script logs
   gcloud compute instances get-serial-port-output hpc-node-instance-name --zone=$(terraform output -raw zone)
   
   # Verify service account permissions
   gcloud projects get-iam-policy $(terraform output -raw project_id) --filter="bindings.members:serviceAccount:$(terraform output -raw cluster_service_account)"
   ```

3. **Scaling Not Working**
   ```bash
   # Check Pub/Sub messages
   gcloud pubsub subscriptions pull $(terraform output -raw pubsub_subscription_name) --auto-ack
   
   # Verify autoscaler configuration
   gcloud compute autoscalers describe $(terraform output -raw cluster_autoscaler_name) --region=$(terraform output -raw region)
   ```

### Debug Commands

```bash
# Check all resources
terraform state list

# Verify resource configuration
terraform show

# Check for configuration drift
terraform plan

# Enable debug logging
export TF_LOG=DEBUG
terraform apply
```

## Customization

### Adding New Weather Locations

Add locations to the `weather_monitoring_locations` variable:

```hcl
weather_monitoring_locations = [
  {
    name      = "europe-west1"
    latitude  = 50.4501
    longitude = 3.8196
    region    = "europe-west1"
  },
  # ... existing locations
]
```

### Custom Scaling Logic

Modify the `weather_function.py.tpl` file to implement custom scaling algorithms:

```python
def analyze_weather_conditions(self, weather_data):
    # Custom scaling logic here
    scaling_factor = custom_scaling_algorithm(weather_data)
    return scaling_factor, weather_summary
```

### Additional Monitoring

Add custom metrics to the monitoring configuration:

```hcl
# In main.tf, add new monitoring alerts
resource "google_monitoring_alert_policy" "custom_alert" {
  display_name = "Custom Weather Alert"
  # ... configuration
}
```

## Cleanup

To remove all resources:

```bash
# Destroy all infrastructure
terraform destroy

# Confirm destruction when prompted
# Enter 'yes' to proceed

# Clean up local files
rm -f terraform.tfstate*
rm -f .terraform.lock.hcl
rm -rf .terraform/
```

**Warning**: This will permanently delete all resources and data. Ensure you have backups of any important data before running destroy.

## Support

For issues with this Terraform implementation:

1. Check the troubleshooting section above
2. Review Terraform and Google Cloud documentation
3. Check Google Cloud Console for resource status
4. Review Cloud Logging for detailed error messages

## Contributing

To contribute improvements to this implementation:

1. Test changes in a development environment
2. Follow Terraform best practices
3. Update documentation for any changes
4. Ensure all variables are properly validated
5. Add appropriate outputs for new resources

## License

This implementation is provided as-is for educational and development purposes. Ensure you comply with Google Cloud terms of service and any applicable licenses for the weather data and other services used.