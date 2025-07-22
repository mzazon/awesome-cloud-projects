# Infrastructure as Code for Batch Processing Workflows with Cloud Run Jobs and Cloud Scheduler

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Batch Processing Workflows with Cloud Run Jobs and Cloud Scheduler".

## Overview

This serverless batch processing solution automates recurring data processing tasks, ETL operations, and periodic maintenance workflows using Cloud Run Jobs and Cloud Scheduler. The infrastructure provides enterprise-grade reliability, automatic scaling, and pay-per-use pricing while maintaining complete control over processing logic and scheduling parameters.

## Architecture Components

- **Cloud Run Jobs**: Serverless execution environment for containerized batch workloads
- **Cloud Scheduler**: Enterprise-grade cron job scheduling with built-in retry mechanisms
- **Cloud Build**: Serverless CI/CD for automated container image builds
- **Artifact Registry**: Secure container image storage with vulnerability scanning
- **Cloud Storage**: Data storage for input files and processed output
- **Cloud Monitoring & Logging**: Comprehensive observability and alerting

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native Infrastructure as Code solution (YAML)
- **Terraform**: Multi-cloud infrastructure as code using HashiCorp Configuration Language
- **Scripts**: Bash deployment and cleanup scripts for manual or automated execution

## Prerequisites

### General Requirements

- Google Cloud project with Owner or Editor permissions for resource creation
- Google Cloud CLI (gcloud) installed and authenticated, or access to Cloud Shell
- Basic understanding of containerization and Docker concepts
- Familiarity with cron schedule expressions and batch processing workflows
- Understanding of Google Cloud IAM service accounts and permissions

### Tool-Specific Prerequisites

#### Infrastructure Manager
- gcloud CLI version 455.0.0 or higher
- Infrastructure Manager API enabled in your project

#### Terraform
- Terraform v1.5.0 or higher installed
- Google Cloud provider v5.0.0 or higher

#### Bash Scripts
- bash shell environment (Linux, macOS, or WSL on Windows)
- Google Cloud CLI configured with appropriate permissions

### Cost Estimation

Estimated cost: $10-20 per month for moderate batch processing workloads (depends on execution frequency and resource usage)

> **Note**: Cloud Run Jobs follow a pay-per-use model, charging only for actual execution time. Review [Cloud Run pricing](https://cloud.google.com/run/pricing) and [Cloud Scheduler pricing](https://cloud.google.com/scheduler/pricing) for detailed cost calculations.

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

Infrastructure Manager provides Google Cloud's native Infrastructure as Code experience with YAML configuration files.

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="batch-processing-$(date +%s)"

# Create deployment
cd infrastructure-manager/
gcloud infra-manager deployments create ${DEPLOYMENT_NAME} \
    --location=${REGION} \
    --source=main.yaml \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe ${DEPLOYMENT_NAME} \
    --location=${REGION}
```

### Using Terraform

Terraform provides multi-cloud Infrastructure as Code with extensive provider ecosystem and state management.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform and download providers
terraform init

# Set required variables
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"

# Review infrastructure plan
terraform plan

# Apply infrastructure changes
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide direct gcloud CLI execution for environments that prefer imperative deployment approaches.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud run jobs list --region=${REGION}
gcloud scheduler jobs list --location=${REGION}
```

## Configuration Options

### Environment Variables

All implementations support the following environment variables for customization:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud project ID | - | Yes |
| `REGION` | Google Cloud region for resources | `us-central1` | No |
| `JOB_NAME` | Cloud Run Job name | `data-processor-${random}` | No |
| `REGISTRY_NAME` | Artifact Registry repository name | `batch-registry-${random}` | No |
| `SCHEDULER_JOB_NAME` | Cloud Scheduler job name | `batch-schedule-${random}` | No |
| `SCHEDULE_EXPRESSION` | Cron schedule for job execution | `0 * * * *` (hourly) | No |
| `TASK_TIMEOUT` | Cloud Run Job task timeout in seconds | `3600` (1 hour) | No |
| `CPU_ALLOCATION` | CPU allocation for Cloud Run Job | `1` | No |
| `MEMORY_ALLOCATION` | Memory allocation for Cloud Run Job | `2Gi` | No |
| `MAX_RETRIES` | Maximum retry attempts for failed jobs | `3` | No |

### Terraform Variables

For Terraform deployments, customize the deployment by creating a `terraform.tfvars` file:

```hcl
project_id = "your-project-id"
region     = "us-central1"

# Optional customizations
job_name             = "custom-batch-processor"
schedule_expression  = "0 */2 * * *"  # Every 2 hours
task_timeout_seconds = 7200            # 2 hours
cpu_allocation       = "2"
memory_allocation    = "4Gi"
max_retries         = 5

# Environment variables for the batch job
job_environment_variables = {
  BATCH_SIZE      = "50"
  LOG_LEVEL       = "INFO"
  CUSTOM_SETTING  = "production"
}
```

## Deployment Features

### Automated Container Building

All implementations include automated container image building with:

- Python 3.11-based runtime environment
- Google Cloud client libraries pre-installed
- Optimized multi-stage builds for reduced image size
- Vulnerability scanning through Artifact Registry
- Automated tagging with git commit SHA and latest

### Security Best Practices

The infrastructure implements security best practices including:

- Least privilege IAM service accounts for Cloud Run Jobs
- Private Artifact Registry repositories with access controls
- Encrypted data at rest and in transit
- VPC connector support for private resource access
- Secrets management integration for sensitive configuration
- Network security through Cloud Armor and VPC firewall rules

### Monitoring and Observability

Comprehensive monitoring features include:

- Cloud Logging integration for structured application logs
- Cloud Monitoring dashboards for job execution metrics
- Alert policies for job failures and performance issues
- Log-based metrics for custom monitoring requirements
- Error reporting integration for application error tracking
- Cloud Trace support for distributed tracing

### High Availability and Reliability

The architecture provides enterprise-grade reliability through:

- Automatic retry mechanisms for failed job executions
- Health checks and readiness probes for container health
- Multi-zone deployment for increased availability
- Graceful shutdown handling for clean job termination
- Dead letter queue support for failed message processing
- Circuit breaker patterns for downstream service protection

## Testing and Validation

### Smoke Tests

Each implementation includes smoke tests to verify deployment success:

```bash
# Test Cloud Run Job creation and execution
gcloud run jobs execute ${JOB_NAME} --region=${REGION} --wait

# Test Cloud Scheduler job execution
gcloud scheduler jobs run ${SCHEDULER_JOB_NAME} --location=${REGION}

# Verify sample data processing
gsutil ls gs://${BUCKET_NAME}/output/
```

### Integration Tests

For comprehensive testing, the infrastructure supports:

- End-to-end workflow testing with sample data files
- Performance testing with configurable data volumes
- Failure scenario testing with error injection
- Security testing with vulnerability scans
- Cost optimization testing with resource monitoring

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete ${DEPLOYMENT_NAME} \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all infrastructure
terraform destroy

# Verify state is clean
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource removal
gcloud run jobs list --region=${REGION}
gcloud scheduler jobs list --location=${REGION}
```

### Manual Cleanup (Emergency)

If automated cleanup fails, manually remove resources:

```bash
# Delete Cloud Run Jobs
gcloud run jobs delete ${JOB_NAME} --region=${REGION} --quiet

# Delete Cloud Scheduler Jobs
gcloud scheduler jobs delete ${SCHEDULER_JOB_NAME} --location=${REGION} --quiet

# Delete Artifact Registry repository
gcloud artifacts repositories delete ${REGISTRY_NAME} --location=${REGION} --quiet

# Delete Cloud Storage bucket
gsutil -m rm -r gs://${BUCKET_NAME}

# Delete Cloud Build triggers (if any)
gcloud builds triggers list --format="value(name)" | xargs -I {} gcloud builds triggers delete {} --quiet

# Delete service accounts (if custom ones were created)
gcloud iam service-accounts delete batch-processor@${PROJECT_ID}.iam.gserviceaccount.com --quiet
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Cloud Run Job Fails to Execute

**Symptoms**: Job execution fails with permission errors or timeout issues

**Solutions**:
- Verify service account has necessary permissions for Cloud Storage and logging
- Check container image is accessible in Artifact Registry
- Review job resource limits (CPU, memory, timeout)
- Examine application logs for runtime errors

```bash
# Check job execution logs
gcloud logging read "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${JOB_NAME}\"" --limit=20

# Verify service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" --filter="bindings.members:*${PROJECT_ID}*"
```

#### 2. Cloud Scheduler Cannot Trigger Jobs

**Symptoms**: Scheduler runs but Cloud Run Job is not executed

**Solutions**:
- Verify scheduler service account has Cloud Run Invoker role
- Check scheduler job configuration and endpoint URL
- Confirm OAuth authentication is properly configured
- Review scheduler execution history for error details

```bash
# Check scheduler job status
gcloud scheduler jobs describe ${SCHEDULER_JOB_NAME} --location=${REGION}

# View scheduler execution history
gcloud logging read "resource.type=\"gce_instance\" AND jsonPayload.jobName=\"${SCHEDULER_JOB_NAME}\"" --limit=10
```

#### 3. Container Image Build Failures

**Symptoms**: Cloud Build fails to create container images

**Solutions**:
- Verify Cloud Build API is enabled and has necessary permissions
- Check Dockerfile syntax and build context
- Review build logs for specific error messages
- Ensure Artifact Registry repository exists and is accessible

```bash
# View recent build history
gcloud builds list --limit=5

# Check build logs for specific build
gcloud builds log BUILD_ID
```

#### 4. Resource Quota Exceeded

**Symptoms**: Deployment fails with quota exceeded errors

**Solutions**:
- Check current quota usage in Google Cloud Console
- Request quota increases for specific resources
- Optimize resource allocation in job configuration
- Consider multi-region deployment for distributed load

```bash
# Check current quota usage
gcloud compute project-info describe --format="table(quotas.metric,quotas.usage,quotas.limit)"
```

### Performance Optimization

#### Job Execution Performance

- **Parallel Processing**: Increase task count for data partitioning
- **Resource Allocation**: Optimize CPU and memory based on workload characteristics
- **Container Optimization**: Use multi-stage builds and minimal base images
- **Data Locality**: Process data in the same region as storage

#### Cost Optimization

- **Execution Frequency**: Review scheduling patterns and optimize frequency
- **Resource Right-sizing**: Monitor actual resource usage and adjust allocations
- **Data Lifecycle**: Implement Cloud Storage lifecycle policies for processed data
- **Preemptible Resources**: Consider spot instances for cost-sensitive workloads

#### Monitoring and Alerting

- **Custom Metrics**: Implement application-specific metrics for business logic
- **SLI/SLO Definition**: Define service level indicators and objectives
- **Alert Tuning**: Configure alert thresholds to reduce noise while maintaining coverage
- **Dashboard Creation**: Build custom dashboards for operational visibility

### Support and Documentation

For issues with this infrastructure code:

1. **Original Recipe**: Refer to the complete recipe documentation in the parent directory
2. **Google Cloud Documentation**: Consult official [Cloud Run](https://cloud.google.com/run/docs) and [Cloud Scheduler](https://cloud.google.com/scheduler/docs) documentation
3. **Terraform Provider**: Review [Google Cloud Terraform provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs) documentation
4. **Community Support**: Engage with the Google Cloud community on [Stack Overflow](https://stackoverflow.com/questions/tagged/google-cloud-platform)

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes thoroughly in a development environment
2. Follow infrastructure as code best practices and security guidelines
3. Update documentation to reflect any configuration changes
4. Ensure compatibility across all implementation types
5. Validate cost implications of infrastructure modifications

## License

This infrastructure code is provided as part of the cloud recipes collection and follows the same licensing terms as the parent repository.