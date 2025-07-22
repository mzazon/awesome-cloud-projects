# Infrastructure as Code for Weather-Aware Infrastructure Scaling with Google Maps Platform Weather API and Cluster Toolkit

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Weather-Aware Infrastructure Scaling with Google Maps Platform Weather API and Cluster Toolkit".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud Project with billing enabled
- Appropriate IAM permissions for:
  - Compute Engine (create/manage instances and instance groups)
  - Cloud Functions (create/deploy functions)
  - Cloud Storage (create/manage buckets)
  - Pub/Sub (create/manage topics and subscriptions)
  - Cloud Monitoring (create dashboards and metrics)
  - Cloud Scheduler (create/manage jobs)
  - Google Maps Platform Weather API (enabled and API key)
  - Infrastructure Manager (for Infrastructure Manager deployment)
- Terraform >= 1.0 (for Terraform deployment)
- Python 3.7+ with pip (for Cloud Functions)
- Git (for Cluster Toolkit)

## Architecture Overview

This solution creates a weather-aware HPC infrastructure that automatically scales compute clusters based on real-time weather data. The architecture includes:

- **Weather Data Processing**: Cloud Functions that integrate with Google Maps Platform Weather API
- **Messaging System**: Pub/Sub for reliable scaling event distribution
- **HPC Cluster**: Cluster Toolkit-based Slurm cluster with auto-scaling capabilities
- **Monitoring**: Cloud Monitoring dashboards for weather and cluster metrics
- **Automation**: Cloud Scheduler for regular weather data collection

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/weather-hpc-deployment \
    --service-account="your-service-account@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="variables.yaml"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure your deployment
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
# Required
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export WEATHER_API_KEY="your-google-maps-weather-api-key"

# Optional (will be generated if not provided)
export CLUSTER_NAME="weather-cluster-$(date +%s)"
export BUCKET_NAME="weather-data-${PROJECT_ID}"
export FUNCTION_NAME="weather-processor"
export TOPIC_NAME="weather-scaling"
```

### Weather API Setup

1. Enable Google Maps Platform Weather API in your project:
   ```bash
   gcloud services enable maps-weather.googleapis.com
   ```

2. Create an API key with Weather API access:
   ```bash
   gcloud alpha services api-keys create --display-name="Weather API Key"
   ```

3. Set the API key in your environment:
   ```bash
   export WEATHER_API_KEY="your-api-key-here"
   ```

### Customization Options

#### Terraform Variables

Create a `terraform.tfvars` file to customize your deployment:

```hcl
# Project Configuration
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Cluster Configuration
cluster_name     = "weather-hpc-cluster"
max_node_count   = 20
machine_type     = "c2-standard-60"
enable_spot_vms  = true

# Weather Monitoring
weather_check_schedule = "*/15 * * * *"  # Every 15 minutes
storm_monitor_schedule = "*/5 * * * *"   # Every 5 minutes during storms

# Storage Configuration
bucket_name = "my-weather-data-bucket"
storage_class = "STANDARD"
```

#### Infrastructure Manager Variables

Create a `variables.yaml` file:

```yaml
project_id: "your-project-id"
region: "us-central1"
zone: "us-central1-a"
cluster_name: "weather-hpc-cluster"
weather_api_key: "your-weather-api-key"
max_node_count: 20
machine_type: "c2-standard-60"
enable_spot_vms: true
```

## Deployment Details

### Infrastructure Manager Deployment

The Infrastructure Manager configuration includes:

- **Compute Resources**: HPC cluster with Slurm scheduler
- **Storage**: Cloud Storage bucket for weather data
- **Functions**: Weather processing and scaling logic
- **Monitoring**: Custom dashboards and alerting
- **Networking**: VPC and firewall rules for cluster communication

### Terraform Deployment

The Terraform configuration is organized into modules:

- **`main.tf`**: Primary resource definitions
- **`variables.tf`**: Input variable definitions
- **`outputs.tf`**: Output values for verification
- **`versions.tf`**: Provider version constraints

### Bash Script Deployment

The deployment script handles:

1. Project setup and API enablement
2. Storage bucket creation
3. Cloud Function deployment
4. Cluster Toolkit installation and configuration
5. HPC cluster deployment
6. Monitoring setup
7. Scheduler configuration

## Post-Deployment

### Verification Steps

1. **Check Cluster Status**:
   ```bash
   gcloud compute instances list --filter="name~'weather-cluster'"
   ```

2. **Verify Weather Function**:
   ```bash
   gcloud functions describe weather-processor --region=us-central1
   ```

3. **Test Weather API Integration**:
   ```bash
   curl -X GET "https://us-central1-${PROJECT_ID}.cloudfunctions.net/weather-processor"
   ```

4. **Monitor Scaling Events**:
   ```bash
   gcloud pubsub topics list --filter="name~'weather-scaling'"
   ```

### Accessing the Cluster

1. **Get Login Node IP**:
   ```bash
   LOGIN_IP=$(gcloud compute instances describe weather-cluster-login \
       --zone=us-central1-a --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
   ```

2. **SSH to Login Node**:
   ```bash
   gcloud compute ssh weather-cluster-login --zone=us-central1-a
   ```

3. **Submit Sample Jobs**:
   ```bash
   # On the login node
   sbatch climate-model-job.sh
   sbatch energy-forecast-job.sh
   ```

### Monitoring and Logs

- **Cloud Monitoring**: View the weather-aware scaling dashboard
- **Function Logs**: Check Cloud Functions logs for weather processing
- **Cluster Logs**: Monitor Slurm logs on the controller node
- **Pub/Sub Monitoring**: Track message flow and processing

## Scaling Configuration

### Weather Scaling Logic

The system automatically scales based on:

- **Precipitation**: Heavy rain/snow increases compute demand
- **Wind Speed**: High winds trigger renewable energy forecasting
- **Temperature Variance**: Weather instability increases modeling needs

### Scaling Factors

- **Base Scaling**: 1.0x (minimum 2 nodes)
- **Moderate Weather**: 1.1-1.4x scaling
- **Severe Weather**: Up to 2.0x scaling (capped for cost control)

### Customizing Scaling Rules

Modify the scaling logic in the Cloud Function:

```python
# In weather-function/main.py
def analyze_weather_conditions(weather_data):
    # Customize scaling logic here
    if total_precipitation > 10:  # Heavy rain/snow
        scaling_factor *= 1.5
    # Add your custom conditions
```

## Cost Optimization

### Estimated Costs

- **Compute Engine**: $0.10-0.50/hour per node (depends on machine type)
- **Cloud Functions**: $0.0000004/invocation
- **Cloud Storage**: $0.020/GB/month
- **Weather API**: $0.005/1000 requests
- **Pub/Sub**: $0.40/million messages

### Cost Control Measures

1. **Spot Instances**: Enabled by default for compute nodes
2. **Scaling Limits**: Maximum 20 nodes by default
3. **Automatic Cleanup**: Idle resources are terminated
4. **Storage Lifecycle**: Old weather data is automatically archived

## Troubleshooting

### Common Issues

1. **Weather API Errors**:
   - Verify API key is valid and has Weather API access
   - Check API quotas and billing

2. **Cluster Deployment Failures**:
   - Ensure sufficient compute quotas
   - Verify VPC and firewall configurations

3. **Scaling Not Working**:
   - Check Pub/Sub message flow
   - Verify Cloud Function logs
   - Ensure proper IAM permissions

### Debug Commands

```bash
# Check function logs
gcloud functions logs read weather-processor --limit=50

# Monitor Pub/Sub messages
gcloud pubsub subscriptions pull weather-scaling-sub --limit=10

# Check cluster status
gcloud compute instances list --filter="name~'weather-cluster'"

# Verify API enablement
gcloud services list --enabled --filter="name~'weather'"
```

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/weather-hpc-deployment
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

### Manual Cleanup

If automated cleanup fails:

```bash
# Delete cluster resources
gcloud compute instances delete weather-cluster-login --zone=us-central1-a --quiet
gcloud compute instances delete weather-cluster-controller --zone=us-central1-a --quiet

# Remove Cloud Functions
gcloud functions delete weather-processor --region=us-central1 --quiet

# Delete storage bucket
gsutil -m rm -r gs://weather-data-${PROJECT_ID}

# Remove Pub/Sub resources
gcloud pubsub subscriptions delete weather-scaling-sub --quiet
gcloud pubsub topics delete weather-scaling --quiet

# Delete scheduler jobs
gcloud scheduler jobs delete weather-check-job --quiet
gcloud scheduler jobs delete weather-storm-monitor --quiet
```

## Security Considerations

### IAM Permissions

The deployment creates service accounts with minimal required permissions:

- **Compute Service Account**: Instance management and monitoring
- **Function Service Account**: Storage and Pub/Sub access
- **Cluster Service Account**: HPC cluster operations

### Network Security

- **VPC Isolation**: Cluster runs in dedicated VPC
- **Firewall Rules**: Restrictive rules for cluster communication
- **SSH Access**: Secure key-based authentication

### Data Protection

- **Encryption**: All data encrypted at rest and in transit
- **API Keys**: Stored securely in Secret Manager
- **Access Controls**: Principle of least privilege

## Advanced Configuration

### Multi-Region Deployment

For multi-region weather monitoring:

```hcl
# In terraform.tfvars
regions = [
  {
    name = "us-central1"
    zone = "us-central1-a"
  },
  {
    name = "us-east1"
    zone = "us-east1-b"
  }
]
```

### Custom Weather Locations

Add monitoring locations in the Cloud Function:

```python
# Custom weather monitoring locations
locations = [
    {"lat": 37.7749, "lng": -122.4194, "name": "san-francisco"},
    {"lat": 40.7128, "lng": -74.0060, "name": "new-york"},
    # Add your locations here
]
```

### Integration with Existing Infrastructure

To integrate with existing GCP resources:

1. **Use Existing VPC**:
   ```hcl
   # In terraform.tfvars
   vpc_name = "existing-vpc-name"
   create_vpc = false
   ```

2. **Use Existing Storage**:
   ```hcl
   # In terraform.tfvars
   bucket_name = "existing-bucket-name"
   create_bucket = false
   ```

## Support and Contributing

### Getting Help

- Review the original recipe documentation
- Check Google Cloud documentation for specific services
- Review Cluster Toolkit documentation
- Submit issues to the recipes repository

### Contributing

To contribute improvements:

1. Fork the repository
2. Create a feature branch
3. Test your changes
4. Submit a pull request

## License

This infrastructure code is provided as-is under the same license as the recipes repository.

## Related Resources

- [Google Maps Platform Weather API Documentation](https://developers.google.com/maps/documentation/weather)
- [Cluster Toolkit Documentation](https://cloud.google.com/cluster-toolkit/docs)
- [Slurm Workload Manager Documentation](https://slurm.schedmd.com/documentation.html)
- [Google Cloud Infrastructure Manager](https://cloud.google.com/infrastructure-manager)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest)