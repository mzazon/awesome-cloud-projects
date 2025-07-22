# Infrastructure as Code for Performance Testing Pipelines with Cloud Load Balancing and Cloud Monitoring

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Performance Testing Pipelines with Cloud Load Balancing and Cloud Monitoring".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud CLI) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for the following services:
  - Cloud Functions
  - Cloud Scheduler
  - Compute Engine
  - Cloud Load Balancing
  - Cloud Monitoring
  - Cloud Storage
  - Cloud Logging
  - IAM and Service Accounts
- For Terraform: Terraform CLI installed (version >= 1.0)
- For Infrastructure Manager: Access to Google Cloud Infrastructure Manager service

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended way to deploy and manage infrastructure using declarative configuration files.

```bash
# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Create a deployment
gcloud infra-manager deployments create performance-testing-deployment \
    --location=us-central1 \
    --source-blueprint=main.yaml \
    --input-values project_id=YOUR_PROJECT_ID,region=us-central1

# Monitor deployment progress
gcloud infra-manager deployments describe performance-testing-deployment \
    --location=us-central1

# Wait for deployment to complete
gcloud infra-manager deployments wait performance-testing-deployment \
    --location=us-central1
```

### Using Terraform

Terraform provides cross-platform infrastructure management with extensive provider support.

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide a traditional deployment approach using gcloud CLI commands.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the script prompts and wait for completion
```

## Architecture Overview

This infrastructure deploys a comprehensive performance testing pipeline including:

- **Load Generation**: Cloud Functions for executing configurable HTTP load tests
- **Target Application**: Managed instance group with auto-scaling behind a load balancer
- **Load Balancing**: HTTP(S) Load Balancer with health checks and backend services
- **Automation**: Cloud Scheduler jobs for regular performance testing
- **Monitoring**: Custom dashboards and alert policies for performance metrics
- **Storage**: Cloud Storage bucket for test results and logs
- **Security**: Dedicated service account with least-privilege permissions

## Configuration Options

### Infrastructure Manager

Customize your deployment by modifying the input values:

```yaml
# Example input values
project_id: "your-project-id"
region: "us-central1"
zone: "us-central1-a"
test_frequency: "0 2 * * *"  # Daily at 2 AM UTC
concurrent_users: 20
requests_per_second: 10
```

### Terraform

Customize your deployment using variables:

```bash
# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
function_memory = "512MB"
function_timeout = "540s"
instance_type = "e2-medium"
min_replicas = 2
max_replicas = 10
test_duration = 300
EOF

# Apply with custom variables
terraform apply -var-file="terraform.tfvars"
```

### Bash Scripts

Customize deployment by setting environment variables before running:

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization variables
export FUNCTION_MEMORY="512MB"
export INSTANCE_TYPE="e2-medium"
export MIN_INSTANCES="2"
export MAX_INSTANCES="10"
export TEST_DURATION="300"
export CONCURRENT_USERS="20"
export REQUESTS_PER_SECOND="10"

# Deploy with custom configuration
./scripts/deploy.sh
```

## Post-Deployment

### Accessing Resources

After successful deployment, you can access:

1. **Load Balancer**: The external IP address will be provided in the outputs
2. **Cloud Functions**: Available in the Google Cloud Console under Cloud Functions
3. **Monitoring Dashboard**: Access through Google Cloud Console > Monitoring
4. **Test Results**: Stored in the created Cloud Storage bucket
5. **Scheduler Jobs**: Visible in Google Cloud Console > Cloud Scheduler

### Running Manual Tests

Execute a manual performance test using the deployed infrastructure:

```bash
# Get the function URL (replace with your actual function name)
FUNCTION_URL=$(gcloud functions describe performance-test-function \
    --region=us-central1 --format="value(httpsTrigger.url)")

# Get the load balancer IP
LB_IP=$(gcloud compute forwarding-rules describe http-forwarding-rule \
    --global --format="value(IPAddress)")

# Execute a test
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
      "target_url": "http://'${LB_IP}'",
      "duration_seconds": 120,
      "concurrent_users": 15,
      "requests_per_second": 8,
      "project_id": "'${PROJECT_ID}'",
      "bucket_name": "'${PROJECT_ID}'-test-results"
    }'
```

### Monitoring and Alerts

1. **Dashboard**: Navigate to Cloud Monitoring > Dashboards to view the performance testing dashboard
2. **Alerts**: Check Cloud Monitoring > Alerting for configured alert policies
3. **Logs**: Review Cloud Logging for function execution logs and load balancer access logs
4. **Metrics**: Monitor custom metrics under Cloud Monitoring > Metrics Explorer

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete performance-testing-deployment \
    --location=us-central1

# Confirm deletion
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID"

# Confirm when prompted
# Review the destruction plan before confirming
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
# Script will remove resources in reverse order of creation
```

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your service account has the required IAM roles:
   - Cloud Functions Admin
   - Compute Admin
   - Storage Admin
   - Monitoring Admin
   - Service Account Admin

2. **API Not Enabled**: Enable required APIs:
   ```bash
   gcloud services enable cloudfunctions.googleapis.com \
       cloudscheduler.googleapis.com \
       compute.googleapis.com \
       monitoring.googleapis.com \
       storage.googleapis.com
   ```

3. **Function Deployment Timeout**: Increase deployment timeout:
   ```bash
   gcloud config set functions/timeout 600
   ```

4. **Load Balancer Health Check Failures**: Verify firewall rules allow health check traffic:
   ```bash
   gcloud compute firewall-rules list --filter="name:allow-health-check"
   ```

### Verification Commands

```bash
# Check function deployment status
gcloud functions list --filter="name:performance-test"

# Verify load balancer configuration
gcloud compute forwarding-rules list --global

# Check instance group health
gcloud compute instance-groups managed list

# Verify scheduler jobs
gcloud scheduler jobs list

# Check storage bucket
gsutil ls gs://YOUR-PROJECT-ID-test-results/
```

## Cost Considerations

This infrastructure includes the following cost components:

- **Cloud Functions**: Pay-per-invocation pricing
- **Compute Engine**: Instance charges for managed instance group
- **Cloud Load Balancing**: Forwarding rule and data processing charges
- **Cloud Storage**: Storage and operation charges for test results
- **Cloud Monitoring**: Custom metrics and dashboard usage
- **Cloud Scheduler**: Job execution charges (minimal)

Estimated monthly cost for moderate usage: $20-50 USD

### Cost Optimization Tips

1. Use preemptible instances in the managed instance group for non-production testing
2. Configure lifecycle policies on the Cloud Storage bucket to automatically delete old test results
3. Adjust test frequency and duration based on actual needs
4. Monitor usage through Cloud Billing dashboard

## Security Considerations

This implementation follows security best practices:

- **Least Privilege**: Service accounts have minimal required permissions
- **Network Security**: Firewall rules restrict access to necessary ports only
- **Data Protection**: Test results are stored in private Cloud Storage bucket
- **Access Control**: Functions use service account authentication
- **Monitoring**: All activities are logged for audit purposes

## Support and Documentation

- [Google Cloud Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Cloud Load Balancing Documentation](https://cloud.google.com/load-balancing/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Monitoring Documentation](https://cloud.google.com/monitoring/docs)

For issues with this infrastructure code, refer to the original recipe documentation or the Google Cloud documentation for the specific services involved.

## Advanced Usage

### Custom Performance Test Configurations

Modify the Cloud Function payload to customize test parameters:

```json
{
  "target_url": "http://your-load-balancer-ip",
  "duration_seconds": 600,
  "concurrent_users": 50,
  "requests_per_second": 25,
  "test_type": "stress_test",
  "ramp_up_time": 60,
  "custom_headers": {
    "User-Agent": "Performance-Test-Bot",
    "Accept": "application/json"
  }
}
```

### Integration with CI/CD

Integrate performance testing into your CI/CD pipeline:

```bash
# Example GitLab CI/CD job
performance_test:
  stage: test
  script:
    - gcloud auth activate-service-account --key-file=$SERVICE_ACCOUNT_KEY
    - ./scripts/run-performance-test.sh
    - ./scripts/validate-performance-results.sh
  only:
    - main
```

### Multi-Region Deployment

For global performance testing, deploy this infrastructure across multiple regions and coordinate tests using Cloud Workflows or Cloud Composer.