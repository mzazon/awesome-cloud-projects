# Infrastructure as Code for Dynamic Delivery Route Optimization with Maps Platform and BigQuery

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Dynamic Delivery Route Optimization with Maps Platform and BigQuery".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code using YAML configuration
- **Terraform**: Multi-cloud infrastructure as code using HashiCorp Configuration Language (HCL)
- **Scripts**: Bash deployment and cleanup scripts for manual execution

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Terraform 1.5+ installed (for Terraform implementation)
- Google Cloud project with billing enabled
- Required APIs enabled:
  - Cloud Functions API
  - BigQuery API
  - Route Optimization API
  - Cloud Storage API
  - Cloud Build API
  - Cloud Scheduler API
- Appropriate IAM permissions:
  - Project Editor or custom role with:
    - BigQuery Admin
    - Cloud Functions Developer
    - Storage Admin
    - Cloud Scheduler Admin
    - Service Usage Admin
- Maps Platform API key with Route Optimization API enabled
- Estimated cost: $15-25 for testing deployment

> **Note**: The Maps Platform Route Optimization API requires a paid Google Cloud account and charges per optimization request. Review current pricing at [cloud.google.com/maps-platform/pricing](https://cloud.google.com/maps-platform/pricing).

## Quick Start

### Using Infrastructure Manager

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments create route-optimization-deployment \
    --location=${REGION} \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --git-source-repo="https://source.developers.google.com/p/${PROJECT_ID}" \
    --git-source-directory="infrastructure-manager" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe route-optimization-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"

# Apply infrastructure
terraform apply \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}" \
    -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for confirmation and display progress
```

## Configuration Options

### Infrastructure Manager Variables

Configure deployment by modifying `infrastructure-manager/main.yaml`:

```yaml
inputs:
  - name: project_id
    description: "Google Cloud Project ID"
    required: true
  - name: region
    description: "Google Cloud region for resources"
    default: "us-central1"
  - name: dataset_name
    description: "BigQuery dataset name"
    default: "delivery_analytics"
  - name: function_memory
    description: "Cloud Function memory allocation"
    default: "1Gi"
  - name: scheduler_frequency
    description: "Route optimization schedule (cron format)"
    default: "0 */2 * * *"
```

### Terraform Variables

Customize deployment by setting variables in `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"

# Dataset configuration
dataset_name = "delivery_analytics"
dataset_location = "US"

# Function configuration
function_name = "route-optimizer"
function_memory = "1Gi"
function_timeout = 300

# Storage configuration
bucket_name = "your-project-delivery-data"
bucket_location = "US"

# Scheduler configuration
scheduler_frequency = "0 */2 * * *"
scheduler_timezone = "America/New_York"

# Sample data configuration
load_sample_data = true
```

### Script Configuration

Modify variables at the top of `scripts/deploy.sh`:

```bash
# Deployment configuration
PROJECT_ID="${PROJECT_ID:-route-optimization-demo}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"

# Resource naming
DATASET_NAME="delivery_analytics"
FUNCTION_NAME="route-optimizer"
BUCKET_NAME="${PROJECT_ID}-delivery-data"

# Function configuration
FUNCTION_MEMORY="1Gi"
FUNCTION_TIMEOUT="300s"

# Scheduler configuration
SCHEDULER_FREQUENCY="0 */2 * * *"
```

## Validation & Testing

After deployment, verify the infrastructure:

```bash
# Check BigQuery dataset and tables
bq ls ${PROJECT_ID}:delivery_analytics
bq show ${PROJECT_ID}:delivery_analytics.delivery_history

# Verify Cloud Function deployment
gcloud functions describe route-optimizer \
    --region=${REGION} \
    --gen2

# Test Cloud Function
FUNCTION_URL=$(gcloud functions describe route-optimizer \
    --region=${REGION} \
    --format="value(serviceConfig.uri)")

curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "deliveries": [
            {"delivery_id": "TEST001", "lat": 37.7749, "lng": -122.4194},
            {"delivery_id": "TEST002", "lat": 37.7849, "lng": -122.4094}
        ],
        "vehicle_id": "TEST_VEH",
        "driver_id": "TEST_DRV",
        "vehicle_capacity": 5
    }'

# Check Cloud Storage bucket
gsutil ls gs://${PROJECT_ID}-delivery-data/

# Verify Cloud Scheduler job
gcloud scheduler jobs describe optimize-routes-hourly \
    --location=${REGION}
```

## Monitoring and Logs

### View Cloud Function Logs

```bash
# View recent function execution logs
gcloud functions logs read route-optimizer \
    --region=${REGION} \
    --limit=50

# Stream live logs
gcloud functions logs tail route-optimizer \
    --region=${REGION}
```

### Monitor BigQuery Usage

```bash
# Check dataset information
bq show --format=prettyjson ${PROJECT_ID}:delivery_analytics

# Query recent route optimizations
bq query --use_legacy_sql=false \
    "SELECT * FROM \`${PROJECT_ID}.delivery_analytics.optimized_routes\` 
     ORDER BY route_date DESC LIMIT 10"
```

### Check Scheduler Job Status

```bash
# View job execution history
gcloud scheduler jobs describe optimize-routes-hourly \
    --location=${REGION}

# View recent job runs
gcloud logging read "resource.type=cloud_scheduler_job" \
    --limit=10 \
    --format=json
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete route-optimization-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all infrastructure
terraform destroy \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}" \
    -auto-approve

# Clean up Terraform state
rm -rf .terraform/ terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

### Manual Cleanup Verification

```bash
# Verify BigQuery dataset deletion
bq ls ${PROJECT_ID}: | grep delivery_analytics

# Verify Cloud Function deletion
gcloud functions list --filter="name:route-optimizer"

# Verify Cloud Storage bucket deletion
gsutil ls gs://${PROJECT_ID}-delivery-data 2>/dev/null || echo "Bucket deleted"

# Verify Cloud Scheduler job deletion
gcloud scheduler jobs list --location=${REGION} --filter="name:optimize-routes-hourly"
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled:
   ```bash
   gcloud services list --enabled --filter="name:(cloudfunctions OR bigquery OR routeoptimization OR storage OR cloudbuild OR cloudscheduler)"
   ```

2. **Insufficient Permissions**: Verify IAM roles:
   ```bash
   gcloud projects get-iam-policy ${PROJECT_ID} \
       --flatten="bindings[].members" \
       --filter="bindings.members:user:$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
   ```

3. **Route Optimization API Errors**: Check Maps Platform configuration:
   ```bash
   gcloud services list --enabled --filter="name:routeoptimization.googleapis.com"
   ```

4. **Function Deployment Failures**: Check Cloud Build logs:
   ```bash
   gcloud builds list --limit=5
   ```

### Debug Mode

Enable debug logging for Terraform:

```bash
export TF_LOG=DEBUG
terraform apply -var="project_id=${PROJECT_ID}"
```

Enable verbose output for gcloud commands:

```bash
gcloud functions deploy route-optimizer --verbosity=debug
```

## Performance Optimization

### BigQuery Optimization

- **Partitioning**: Tables are partitioned by date for efficient querying
- **Clustering**: Delivery zones and vehicle types are clustered for geospatial queries
- **Cost Control**: Use query cost controls and slot reservations for predictable pricing

### Cloud Function Optimization

- **Memory Allocation**: Adjust function memory based on route complexity
- **Timeout Settings**: Configure appropriate timeout for large route optimization requests
- **Concurrency**: Set max instances to control costs and API usage

### Storage Optimization

- **Lifecycle Policies**: Automatic transition to cheaper storage classes for older data
- **Regional Storage**: Use regional storage for frequently accessed data
- **Compression**: Enable compression for stored route optimization results

## Security Considerations

### IAM Best Practices

- Use least privilege principle for service accounts
- Enable audit logging for all resource access
- Implement VPC Service Controls for additional security
- Use Cloud KMS for encryption key management

### Network Security

- Configure firewall rules for restricted access
- Use Private Google Access for internal communication
- Implement VPC-native clusters for enhanced security
- Enable private IP allocation for Cloud Functions

### Data Protection

- Enable BigQuery encryption at rest
- Use Cloud Storage bucket-level permissions
- Implement data loss prevention (DLP) for sensitive data
- Regular security audits using Security Command Center

## Cost Management

### Cost Monitoring

```bash
# Set up budget alerts
gcloud billing budgets create \
    --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="Route Optimization Budget" \
    --budget-amount=100USD \
    --threshold-rules-percent=50,75,90

# Monitor current costs
gcloud billing budgets list --billing-account=${BILLING_ACCOUNT_ID}
```

### Cost Optimization Tips

1. **Use Committed Use Discounts**: For predictable workloads
2. **Implement Preemptible Instances**: For batch processing tasks
3. **Optimize BigQuery Queries**: Use clustered tables and avoid SELECT *
4. **Monitor Maps API Usage**: Track Route Optimization API calls
5. **Use Cloud Storage Lifecycle Policies**: Automatic cost optimization

## Integration Examples

### Webhook Integration

```bash
# Create webhook endpoint for real-time route requests
gcloud functions deploy route-webhook \
    --gen2 \
    --runtime=python311 \
    --trigger=http \
    --allow-unauthenticated \
    --source=. \
    --entry-point=webhook_handler
```

### Mobile App Integration

```javascript
// Example client code for mobile app integration
const functionUrl = 'https://us-central1-project.cloudfunctions.net/route-optimizer';

const optimizeRoute = async (deliveries) => {
    const response = await fetch(functionUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            deliveries: deliveries,
            vehicle_id: getCurrentVehicleId(),
            driver_id: getCurrentDriverId()
        })
    });
    return response.json();
};
```

## Support and Documentation

- [Google Cloud Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Maps Platform Route Optimization API](https://developers.google.com/maps/documentation/route-optimization)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the project repository.

## Contributing

When modifying the infrastructure code:

1. Test changes in a development environment
2. Validate Terraform configurations with `terraform validate`
3. Run security scans using `terraform plan` with security tools
4. Update documentation for any configuration changes
5. Follow Google Cloud security best practices

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify according to your organization's requirements and policies.