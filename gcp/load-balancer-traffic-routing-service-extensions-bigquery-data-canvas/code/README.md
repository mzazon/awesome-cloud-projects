# Infrastructure as Code for Load Balancer Traffic Routing with Service Extensions and BigQuery Data Canvas

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Load Balancer Traffic Routing with Service Extensions and BigQuery Data Canvas".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements an intelligent traffic routing system that combines:
- Application Load Balancer with Service Extensions for custom routing logic
- Multiple Cloud Run services as backend targets
- BigQuery Data Canvas for AI-powered traffic analytics
- Real-time performance monitoring and routing optimization

## Prerequisites

- Google Cloud project with billing enabled
- Google Cloud CLI (gcloud) v450.0.0 or later installed and configured
- Terraform v1.5+ (for Terraform deployment)
- Appropriate IAM permissions for:
  - Compute Engine Admin
  - Cloud Run Admin
  - BigQuery Admin
  - Service Extensions Admin
  - Cloud Functions Admin
  - Logging Admin
  - Monitoring Admin
- Estimated cost: $25-50 for running this solution

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended infrastructure as code solution that uses standard Terraform configuration but runs in Google Cloud.

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/intelligent-routing \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="gcp/load-balancer-traffic-routing-service-extensions-bigquery-data-canvas/code/infrastructure-manager" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure your project and region
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `enable_apis` | Enable required APIs | `true` | No |
| `service_count` | Number of Cloud Run services | `3` | No |
| `dataset_location` | BigQuery dataset location | `US` | No |

### Terraform Variables

Configure variables in `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
random_suffix = "abc123"
service_memory = {
  service_a = "512Mi"
  service_b = "1Gi"
  service_c = "2Gi"
}
max_instances = {
  service_a = 10
  service_b = 10
  service_c = 5
}
```

## Deployment Process

### Infrastructure Manager Deployment

1. **Prepare Configuration**:
   ```bash
   # Create service account for Infrastructure Manager
   gcloud iam service-accounts create infra-manager \
       --display-name="Infrastructure Manager Service Account"
   
   # Grant necessary permissions
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="serviceAccount:infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
       --role="roles/editor"
   ```

2. **Deploy Infrastructure**:
   ```bash
   # Create deployment
   gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/intelligent-routing \
       --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
       --local-source="infrastructure-manager/"
   ```

3. **Monitor Deployment**:
   ```bash
   # Check deployment status
   gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/intelligent-routing
   ```

### Terraform Deployment

1. **Initialize and Validate**:
   ```bash
   cd terraform/
   terraform init
   terraform validate
   terraform fmt -check
   ```

2. **Plan and Apply**:
   ```bash
   # Create execution plan
   terraform plan -out=tfplan
   
   # Apply the plan
   terraform apply tfplan
   ```

3. **Verify Outputs**:
   ```bash
   # View important outputs
   terraform output load_balancer_ip
   terraform output service_urls
   terraform output bigquery_dataset
   ```

### Bash Script Deployment

1. **Configure Environment**:
   ```bash
   # Set required environment variables
   export PROJECT_ID="your-project-id"
   export REGION="us-central1"
   export ZONE="us-central1-a"
   ```

2. **Run Deployment**:
   ```bash
   # Execute deployment script
   ./scripts/deploy.sh
   
   # The script will:
   # - Enable required APIs
   # - Create all infrastructure components
   # - Configure Service Extensions
   # - Set up BigQuery analytics
   # - Generate sample traffic for testing
   ```

## Validation and Testing

### Verify Load Balancer Configuration

```bash
# Get load balancer IP
LB_IP=$(gcloud compute forwarding-rules describe intelligent-lb-rule-* \
    --global --format="value(IPAddress)")

# Test basic connectivity
curl -s -o /dev/null -w "Status: %{http_code}, Time: %{time_total}s\n" \
    http://${LB_IP}/

# Test different routing paths
for path in "/api/fast/test" "/api/standard/process" "/api/intensive/compute"; do
    echo "Testing path: ${path}"
    curl -s -w "Status: %{http_code}, Time: %{time_total}s\n" \
        -o /dev/null \
        "http://${LB_IP}${path}"
done
```

### Validate BigQuery Analytics

```bash
# Check BigQuery dataset and tables
bq ls your-project-id:traffic_analytics_*

# Query traffic metrics
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) as total_requests, 
            AVG(response_time) as avg_response_time 
     FROM \`your-project-id.traffic_analytics_*.lb_metrics\` 
     WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)"

# Check routing decisions
bq query --use_legacy_sql=false \
    "SELECT target_service, 
            AVG(confidence_score) as avg_confidence,
            COUNT(*) as decision_count
     FROM \`your-project-id.traffic_analytics_*.routing_decisions\` 
     WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
     GROUP BY target_service"
```

### Test Service Extensions

```bash
# Verify Service Extensions configuration
gcloud service-extensions extensions list --location=${REGION}

# Check extension logs
gcloud logging read 'resource.type="cloud_function" AND resource.labels.function_name:"traffic-router"' \
    --limit=10 \
    --format="table(timestamp,severity,textPayload)"
```

## Monitoring and Observability

### Cloud Monitoring Dashboards

Access pre-configured dashboards:
- Load Balancer Performance: Monitor request rates, latency, and error rates
- Service Extensions Metrics: Track routing decisions and confidence scores
- BigQuery Analytics: Monitor query performance and data ingestion

### Cloud Logging

Key log sources to monitor:
- `gce_instance`: Load balancer access logs
- `cloud_function`: Service Extensions routing logic logs
- `cloud_run_revision`: Backend service logs
- `bigquery_resource`: Analytics query logs

### Custom Metrics

The solution creates custom metrics for:
- Routing decision confidence scores
- Service-specific response times
- Traffic distribution patterns
- AI recommendation accuracy

## Troubleshooting

### Common Issues

1. **Service Extensions Not Working**:
   ```bash
   # Check extension status
   gcloud service-extensions extensions describe EXTENSION_NAME --location=REGION
   
   # Verify function deployment
   gcloud functions describe traffic-router-* --region=REGION
   ```

2. **BigQuery Data Not Populating**:
   ```bash
   # Check logging sink configuration
   gcloud logging sinks list
   
   # Verify BigQuery dataset permissions
   bq show --format=prettyjson DATASET_NAME
   ```

3. **Load Balancer Health Check Failures**:
   ```bash
   # Check backend service health
   gcloud compute backend-services get-health BACKEND_SERVICE_NAME --global
   
   # Verify Cloud Run service status
   gcloud run services list --region=REGION
   ```

### Performance Optimization

1. **Tune Service Extensions Timeout**:
   - Default: 30 seconds
   - Recommended: 5-10 seconds for production
   - Adjust based on routing logic complexity

2. **Optimize BigQuery Queries**:
   - Use partitioned tables for large datasets
   - Implement query caching for repeated analytics
   - Consider BigQuery slots for consistent performance

3. **Scale Cloud Run Services**:
   - Adjust max instances based on traffic patterns
   - Configure CPU and memory allocation per service
   - Use concurrency settings to optimize resource usage

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/intelligent-routing

# Clean up service account
gcloud iam service-accounts delete infra-manager@${PROJECT_ID}.iam.gserviceaccount.com
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl
rm -rf .terraform/
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before:
# - Deleting load balancer components
# - Removing Service Extensions
# - Cleaning up Cloud Run services
# - Deleting BigQuery datasets
# - Removing Cloud Functions and Workflows
```

### Manual Cleanup Verification

Verify all resources are removed:

```bash
# Check for remaining compute resources
gcloud compute forwarding-rules list --global
gcloud compute backend-services list --global
gcloud compute url-maps list --global

# Check Cloud Run services
gcloud run services list --region=${REGION}

# Check BigQuery datasets
bq ls --project_id=${PROJECT_ID}

# Check Service Extensions
gcloud service-extensions extensions list --location=${REGION}

# Check Cloud Functions
gcloud functions list --region=${REGION}
```

## Security Considerations

### IAM and Permissions

- Service accounts use principle of least privilege
- BigQuery datasets have restricted access controls
- Cloud Run services use IAM for authentication
- Load balancer uses Google-managed SSL certificates

### Network Security

- Application Load Balancer provides DDoS protection
- Cloud Run services are not publicly accessible
- Service Extensions run in isolated environments
- All inter-service communication uses HTTPS

### Data Protection

- BigQuery data is encrypted at rest and in transit
- Traffic logs exclude sensitive headers by default
- Service Extensions logs are centralized and monitored
- Access logging tracks all administrative actions

## Cost Optimization

### Resource Sizing Recommendations

1. **Cloud Run Services**:
   - Start with minimum CPU/memory allocation
   - Use concurrency settings to maximize efficiency
   - Enable CPU throttling for cost savings

2. **BigQuery Storage**:
   - Use table partitioning for large datasets
   - Set up data retention policies
   - Consider BigQuery slots for predictable workloads

3. **Load Balancer**:
   - Use regional load balancing when global isn't required
   - Optimize health check intervals
   - Consider Premium vs Standard network tiers

### Monitoring Costs

```bash
# View billing information
gcloud billing budgets list --billing-account=BILLING_ACCOUNT_ID

# Monitor resource usage
gcloud monitoring metrics list --filter="resource.type:gce_instance"
```

## Advanced Configuration

### Custom Service Extensions

To modify the routing logic:

1. Edit the Cloud Function code in `traffic-router-function.py`
2. Redeploy using: `gcloud functions deploy ...`
3. Update the Service Extension configuration if needed

### BigQuery Data Canvas Integration

Configure natural language queries:

1. Enable BigQuery Data Canvas in the Console
2. Connect to your traffic analytics dataset
3. Use queries like:
   - "Show me the slowest services in the last hour"
   - "Which routing decisions had the highest confidence?"
   - "What are the traffic patterns by hour of day?"

### Multi-Region Deployment

For global traffic distribution:

1. Deploy Cloud Run services in multiple regions
2. Configure regional load balancers
3. Use global load balancer for traffic steering
4. Implement cross-region analytics aggregation

## Support and Documentation

### Additional Resources

- [Google Cloud Load Balancing Documentation](https://cloud.google.com/load-balancing/docs)
- [Service Extensions Documentation](https://cloud.google.com/service-extensions/docs)
- [BigQuery Data Canvas Guide](https://cloud.google.com/bigquery/docs/data-canvas)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review Google Cloud Console for error messages
3. Consult the original recipe documentation
4. Contact Google Cloud Support for platform issues

### Contributing

To improve this infrastructure code:
1. Test changes thoroughly in a development environment
2. Follow Google Cloud best practices
3. Update documentation for any configuration changes
4. Validate all IaC implementations work correctly