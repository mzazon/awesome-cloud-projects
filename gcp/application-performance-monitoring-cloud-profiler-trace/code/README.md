# Infrastructure as Code for Enhancing Application Performance with Cloud Profiler and Cloud Trace

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enhancing Application Performance with Cloud Profiler and Cloud Trace".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Docker installed for containerization
- Appropriate GCP permissions for resource creation:
  - Cloud Run Admin
  - Service Account Admin
  - Cloud Profiler Agent
  - Cloud Trace Agent
  - Cloud Monitoring Admin
  - Cloud Build Editor
- Project with billing enabled
- APIs enabled:
  - Cloud Run API
  - Cloud Profiler API
  - Cloud Trace API
  - Cloud Monitoring API
  - Cloud Logging API
  - Cloud Build API

## Architecture Overview

This recipe deploys a microservices architecture with comprehensive performance monitoring:

- **Frontend Service**: User-facing service with CPU profiling instrumentation
- **API Gateway Service**: Central routing with custom tracing spans
- **Auth Service**: Authentication with memory-intensive operations
- **Data Service**: Database operations with performance monitoring
- **Observability Stack**: Cloud Profiler, Cloud Trace, and Cloud Monitoring integration

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create performance-monitoring-demo \
    --location=${REGION} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="gcp/application-performance-monitoring-cloud-profiler-trace/code/infrastructure-manager" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment progress
gcloud infra-manager deployments describe performance-monitoring-demo \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/status.sh
```

## Configuration

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

- `project_id`: Your GCP project ID
- `region`: Deployment region (default: us-central1)
- `service_account_name`: Service account for profiling/tracing
- `max_instances`: Maximum Cloud Run instances per service
- `memory_limit`: Memory allocation for services
- `cpu_limit`: CPU allocation for services

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
project_id     = "your-project-id"
region         = "us-central1"
zone           = "us-central1-a"
environment    = "demo"

# Service configuration
max_instances  = 10
memory_limit   = "1Gi"
cpu_limit      = "1"

# Monitoring configuration
profiler_enabled = true
trace_enabled    = true
monitoring_retention_days = 30
```

### Bash Script Variables

Edit variables in `scripts/deploy.sh`:

```bash
# Project configuration
PROJECT_ID="your-project-id"
REGION="us-central1"
ENVIRONMENT="demo"

# Service configuration
MAX_INSTANCES=10
MEMORY_LIMIT="1Gi"
CPU_LIMIT="1"
```

## Deployment Details

### Services Deployed

1. **Frontend Service**
   - Cloud Run service with profiling instrumentation
   - CPU-intensive operations for profiling demonstration
   - Integrated with Cloud Trace for request tracking

2. **API Gateway Service**
   - Central routing service with custom tracing spans
   - Authentication verification integration
   - Data service communication with performance monitoring

3. **Authentication Service**
   - Memory-intensive operations for profiling
   - Session management with memory allocation patterns
   - Cryptographic operations for CPU profiling

4. **Data Service**
   - Database operations with performance monitoring
   - Complex query processing with tracing
   - CPU-intensive data processing for profiling

### Monitoring Components

- **Cloud Profiler**: Continuous CPU and memory profiling
- **Cloud Trace**: Distributed request tracing
- **Cloud Monitoring**: Metrics aggregation and dashboards
- **Cloud Logging**: Centralized log collection

## Post-Deployment Steps

1. **Verify Services**:
   ```bash
   # Check service status
   gcloud run services list --region=${REGION}
   
   # Test service health
   curl -s $(gcloud run services describe frontend --region=${REGION} --format="value(status.url)")/health
   ```

2. **Generate Load**:
   ```bash
   # Use the provided load generator
   python3 scripts/load_generator.py
   ```

3. **Access Monitoring**:
   - **Cloud Profiler**: `https://console.cloud.google.com/profiler`
   - **Cloud Trace**: `https://console.cloud.google.com/traces`
   - **Cloud Monitoring**: `https://console.cloud.google.com/monitoring`

## Monitoring and Observability

### Cloud Profiler Access

```bash
# View profiler data
gcloud profiler profiles list --service=frontend-service

# Access profiler console
echo "Profiler URL: https://console.cloud.google.com/profiler?project=${PROJECT_ID}"
```

### Cloud Trace Access

```bash
# View recent traces
gcloud logging read "resource.type=cloud_run_revision AND jsonPayload.trace_id!=\"\"" --limit=10

# Access trace console
echo "Trace URL: https://console.cloud.google.com/traces/list?project=${PROJECT_ID}"
```

### Custom Dashboards

The deployment includes a custom monitoring dashboard with:
- Service request latency trends
- CPU utilization by service
- Memory usage patterns
- Error rate monitoring
- Trace span analysis

## Performance Testing

### Load Generation

```bash
# Generate sustained load for profiling
cd scripts/
python3 load_generator.py --requests 200 --concurrent 20 --duration 300

# Monitor resource usage during load
gcloud monitoring metrics list --filter="resource.type=cloud_run_revision"
```

### Performance Analysis

1. **CPU Profiling**: Identify CPU-intensive functions using flame graphs
2. **Memory Profiling**: Detect memory allocation patterns and potential leaks
3. **Distributed Tracing**: Analyze request latency across services
4. **Custom Metrics**: Monitor application-specific performance indicators

## Troubleshooting

### Common Issues

1. **Profiler Not Starting**:
   ```bash
   # Check service logs
   gcloud logs read "resource.type=cloud_run_revision AND textPayload:Profiler" --limit=10
   
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" --filter="bindings.members:*profiler*"
   ```

2. **Trace Data Missing**:
   ```bash
   # Verify trace agent permissions
   gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" --filter="bindings.members:*trace*"
   
   # Check trace configuration
   gcloud logging read "resource.type=cloud_run_revision AND jsonPayload.trace_id!=\"\"" --limit=5
   ```

3. **Service Communication Issues**:
   ```bash
   # Check service URLs
   gcloud run services list --region=${REGION} --format="table(metadata.name,status.url)"
   
   # Test service connectivity
   curl -s ${SERVICE_URL}/health
   ```

### Debug Commands

```bash
# Check all deployed resources
gcloud run services list --region=${REGION}
gcloud iam service-accounts list --filter="name:*profiler*"

# View recent logs
gcloud logs read "resource.type=cloud_run_revision" --limit=20

# Check API enablement
gcloud services list --enabled --filter="name:*profiler* OR name:*trace* OR name:*monitoring*"
```

## Cost Optimization

### Resource Scaling

- **Auto-scaling**: Services automatically scale to zero when not in use
- **Resource Limits**: Configure appropriate CPU and memory limits
- **Request Concurrency**: Optimize concurrent request handling

### Monitoring Costs

- **Profiler**: Minimal cost impact (~$0.50/month per service)
- **Trace**: Pay-per-span pricing (~$0.20 per million spans)
- **Monitoring**: First 150 metrics free, then $0.58 per metric

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete performance-monitoring-demo \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
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

### Manual Cleanup (if needed)

```bash
# Delete Cloud Run services
gcloud run services delete frontend --region=${REGION} --quiet
gcloud run services delete api-gateway --region=${REGION} --quiet
gcloud run services delete auth-service --region=${REGION} --quiet
gcloud run services delete data-service --region=${REGION} --quiet

# Delete service accounts
gcloud iam service-accounts delete profiler-trace-sa@${PROJECT_ID}.iam.gserviceaccount.com --quiet

# Delete container images
gcloud container images delete gcr.io/${PROJECT_ID}/frontend:latest --force-delete-tags --quiet
gcloud container images delete gcr.io/${PROJECT_ID}/api-gateway:latest --force-delete-tags --quiet
gcloud container images delete gcr.io/${PROJECT_ID}/auth-service:latest --force-delete-tags --quiet
gcloud container images delete gcr.io/${PROJECT_ID}/data-service:latest --force-delete-tags --quiet
```

## Security Considerations

### IAM Best Practices

- **Least Privilege**: Service accounts have minimal required permissions
- **Service-Specific Accounts**: Separate service accounts for different functions
- **Regular Rotation**: Rotate service account keys regularly

### Network Security

- **Private Services**: Consider using private Cloud Run services with VPC connectors
- **HTTPS Only**: All service communication uses HTTPS
- **Authentication**: Implement proper authentication between services

### Data Protection

- **Encryption**: Data encrypted in transit and at rest
- **Audit Logging**: Comprehensive audit logging enabled
- **Access Controls**: Proper IAM controls for monitoring data access

## Support and Resources

### Documentation

- [Cloud Profiler Documentation](https://cloud.google.com/profiler/docs)
- [Cloud Trace Documentation](https://cloud.google.com/trace/docs)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Cloud Monitoring Documentation](https://cloud.google.com/monitoring/docs)

### Best Practices

- [Application Performance Monitoring Best Practices](https://cloud.google.com/architecture/best-practices-for-operating-containers)
- [Microservices Observability](https://cloud.google.com/architecture/microservices-architecture-introduction)
- [Cloud Profiler Best Practices](https://cloud.google.com/profiler/docs/best-practices)

### Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation
4. Contact Google Cloud Support for platform-specific issues

## Contributing

When modifying this infrastructure code:
1. Update both Terraform and Infrastructure Manager implementations
2. Test changes in a development environment
3. Update documentation and examples
4. Follow Google Cloud best practices
5. Ensure security configurations remain intact