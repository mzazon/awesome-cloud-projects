# Infrastructure as Code for Continuous Performance Optimization with Cloud Build Triggers and Cloud Monitoring

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Continuous Performance Optimization with Cloud Build Triggers and Cloud Monitoring".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Build API
  - Cloud Monitoring API
  - Cloud Source Repositories API
  - Cloud Run API
  - Container Registry API
  - Infrastructure Manager API (for Infrastructure Manager deployment)
- Basic understanding of containerized applications and CI/CD concepts

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

Infrastructure Manager is Google Cloud's recommended infrastructure as code solution.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments create continuous-perf-optimization \
    --location=us-central1 \
    --source=main.yaml \
    --input-values=project_id=YOUR_PROJECT_ID,region=us-central1

# Check deployment status
gcloud infra-manager deployments describe continuous-perf-optimization \
    --location=us-central1

# Get deployment outputs
gcloud infra-manager deployments describe continuous-perf-optimization \
    --location=us-central1 \
    --format="value(serviceEndpoint.outputs)"
```

### Using Terraform

Terraform provides a declarative approach to infrastructure management with extensive provider support.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply infrastructure changes
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide imperative deployment using Google Cloud CLI commands.

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./deploy.sh

# View deployment status
gcloud run services list --region=$REGION
gcloud builds triggers list
```

## Architecture Overview

This infrastructure deploys:

- **Cloud Source Repository**: Git repository for application code
- **Cloud Build Trigger**: Automated build and deployment pipeline
- **Cloud Run Service**: Containerized application hosting
- **Cloud Monitoring**: Performance monitoring and alerting
- **Notification Channels**: Webhook integration for automated responses
- **Alerting Policies**: Performance threshold monitoring
- **IAM Roles**: Service account permissions and access controls

## Configuration Options

### Infrastructure Manager Variables

The `main.yaml` file supports these configuration options:

```yaml
# Project and region settings
project_id: "your-project-id"
region: "us-central1"
zone: "us-central1-a"

# Resource naming
repository_name: "app-performance-repo"
service_name: "performance-app"
build_trigger_name: "perf-optimization-trigger"

# Performance thresholds
response_time_threshold: 1.0  # seconds
memory_threshold: 0.8         # percentage
cpu_threshold: 0.8           # percentage

# Scaling configuration
min_instances: 1
max_instances: 10
memory_limit: "512Mi"
cpu_limit: "1000m"
```

### Terraform Variables

Configure deployment through `terraform.tfvars`:

```hcl
# Required variables
project_id = "your-project-id"
region     = "us-central1"

# Optional customization
service_name           = "performance-app"
repository_name        = "app-performance-repo"
build_trigger_name     = "perf-optimization-trigger"
response_time_threshold = 1.0
memory_threshold       = 0.8
min_instances         = 1
max_instances         = 10
memory_limit          = "512Mi"
cpu_limit             = "1000m"

# Monitoring settings
alert_duration        = "300s"
evaluation_interval   = "60s"
notification_channels = []
```

### Bash Script Environment Variables

Set these environment variables before running scripts:

```bash
# Required
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Optional customization
export SERVICE_NAME="performance-app"
export REPOSITORY_NAME="app-performance-repo"
export BUILD_TRIGGER_NAME="perf-optimization-trigger"
export RESPONSE_TIME_THRESHOLD="1.0"
export MEMORY_THRESHOLD="0.8"
export MIN_INSTANCES="1"
export MAX_INSTANCES="10"
export MEMORY_LIMIT="512Mi"
export CPU_LIMIT="1000m"
```

## Deployment Verification

After successful deployment, verify the infrastructure:

```bash
# Check Cloud Run service
gcloud run services describe $SERVICE_NAME --region=$REGION

# Verify build trigger
gcloud builds triggers describe $BUILD_TRIGGER_NAME

# Check monitoring policies
gcloud alpha monitoring policies list

# Test application endpoint
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME \
    --region=$REGION --format="value(status.url)")
curl -s "$SERVICE_URL/health" | jq '.'
```

## Performance Testing

Test the deployed performance monitoring system:

```bash
# Generate baseline performance metrics
for i in {1..10}; do
    curl -s "$SERVICE_URL/" > /dev/null
    sleep 1
done

# Trigger performance alerts (high load)
for i in {1..20}; do
    curl -s "$SERVICE_URL/load-test" > /dev/null &
done
wait

# Monitor triggered builds
gcloud builds list --limit=5 --format="table(id,status,createTime)"

# Check alerting policy incidents
gcloud alpha monitoring incidents list
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete continuous-perf-optimization \
    --location=us-central1 \
    --delete-policy=DELETE

# Verify deletion
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Verify resource deletion
gcloud run services list --region=$REGION
gcloud builds triggers list
gcloud alpha monitoring policies list
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
   ```bash
   gcloud services enable cloudbuild.googleapis.com \
       monitoring.googleapis.com \
       sourcerepo.googleapis.com \
       run.googleapis.com
   ```

2. **IAM Permissions**: Verify service account has required permissions
   ```bash
   gcloud projects get-iam-policy $PROJECT_ID
   ```

3. **Build Failures**: Check Cloud Build logs
   ```bash
   gcloud builds log --region=$REGION BUILD_ID
   ```

4. **Monitoring Alerts**: Verify alerting policy configuration
   ```bash
   gcloud alpha monitoring policies list --format="table(displayName,enabled)"
   ```

### Resource Limits

- **Cloud Build**: 120 builds per hour by default
- **Cloud Run**: 1000 concurrent requests per service
- **Container Registry**: 10GB storage included
- **Cloud Monitoring**: 150 metrics per billable resource

### Performance Optimization

- **Memory Configuration**: Adjust based on application requirements
- **CPU Allocation**: Use fractional CPU for cost optimization
- **Concurrency**: Tune based on application thread safety
- **Scaling**: Configure min/max instances based on traffic patterns

## Security Considerations

- **Service Account**: Uses least privilege IAM roles
- **Container Security**: Images scanned for vulnerabilities
- **Network Security**: Cloud Run uses Google's secure-by-default networking
- **Secret Management**: Use Secret Manager for sensitive configuration
- **Monitoring Access**: Restrict monitoring dashboard access

## Cost Optimization

- **Cloud Run**: Pay-per-use pricing with generous free tier
- **Cloud Build**: 120 build-minutes per day free
- **Container Registry**: 0.5GB storage free per month
- **Cloud Monitoring**: First 150 metrics free per billable resource

Monitor costs using:
```bash
gcloud billing budgets list
gcloud alpha billing budgets alerts-config describe BUDGET_ID
```

## Monitoring and Observability

The infrastructure includes comprehensive monitoring:

- **Application Metrics**: Response time, error rate, throughput
- **Infrastructure Metrics**: CPU, memory, network utilization
- **Build Metrics**: Build success rate, duration, frequency
- **Alert Policies**: Automated performance threshold detection
- **Notification Channels**: Webhook integration for automated responses

Access monitoring dashboards:
```bash
# Cloud Monitoring console
gcloud monitoring dashboards list

# View alerting policies
gcloud alpha monitoring policies list

# Check notification channels
gcloud alpha monitoring channels list
```

## Integration with CI/CD

The infrastructure supports integration with external CI/CD systems:

- **GitHub Actions**: Use workload identity for authentication
- **GitLab CI**: Configure service account keys
- **Jenkins**: Use Google Cloud Build plugin
- **Custom Webhooks**: Leverage Cloud Build trigger webhooks

## Advanced Configuration

### Custom Build Configuration

Modify `cloudbuild.yaml` for advanced build steps:

```yaml
steps:
  # Add custom optimization steps
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '--build-arg', 'OPTIMIZATION_LEVEL=high', '-t', 'gcr.io/$PROJECT_ID/app:$BUILD_ID', '.']
  
  # Add performance testing
  - name: 'gcr.io/cloud-builders/curl'
    args: ['--fail', '--silent', 'https://app-url/health']
```

### Multi-Environment Support

Deploy to multiple environments:

```bash
# Development environment
terraform apply -var="project_id=dev-project" -var="environment=dev"

# Production environment
terraform apply -var="project_id=prod-project" -var="environment=prod"
```

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Google Cloud documentation for specific services
3. Consult Terraform Google Cloud Provider documentation
4. Use Google Cloud Support for service-specific issues

## Contributing

To contribute improvements to this infrastructure code:

1. Follow Google Cloud best practices
2. Test changes in a development environment
3. Update documentation for any new features
4. Ensure backward compatibility when possible

## License

This infrastructure code is provided under the same license as the parent recipe repository.