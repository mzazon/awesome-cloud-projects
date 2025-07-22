# Infrastructure as Code for Business Productivity Workflows with Google Workspace APIs and Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Business Productivity Workflows with Google Workspace APIs and Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Google Workspace domain with admin access for API configuration
- Appropriate IAM permissions for:
  - Cloud Functions Admin
  - Cloud Scheduler Admin
  - Cloud SQL Admin
  - Service Account Admin
  - IAM Admin
  - Storage Admin
- Estimated cost: $15-25/month for Cloud SQL, Cloud Functions, and storage

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/productivity-automation \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/workspace-automation@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure deploys:

- **Cloud SQL PostgreSQL Instance**: Stores productivity metrics and analytics data
- **Cloud Functions**: Four serverless functions for email processing, meeting automation, document organization, and metrics calculation
- **Cloud Scheduler Jobs**: Automated workflow triggers for business hour processing
- **Service Account**: Workspace API integration with proper IAM roles
- **Cloud Storage**: Document storage and function source code
- **Monitoring & Logging**: Comprehensive observability for all components

## Configuration Variables

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `database_tier` | Cloud SQL instance tier | `db-f1-micro` | No |
| `storage_size` | Database storage size in GB | `20` | No |
| `function_memory` | Cloud Function memory allocation | `512` | No |
| `function_timeout` | Cloud Function timeout in seconds | `300` | No |

### Environment Variables (Bash Scripts)

```bash
export PROJECT_ID="your-project-id"          # Required: GCP Project ID
export REGION="us-central1"                  # Optional: Deployment region
export ZONE="us-central1-a"                  # Optional: Deployment zone
export DATABASE_NAME="productivity_db"       # Optional: Database name
export INSTANCE_NAME="productivity-instance" # Optional: SQL instance name
```

## Google Workspace API Setup

Before deploying, configure Google Workspace APIs:

1. **Enable Google Workspace APIs** in Google Cloud Console:
   - Gmail API
   - Google Calendar API
   - Google Drive API

2. **Configure OAuth Consent Screen**:
   - Set up OAuth consent screen for your domain
   - Add required scopes for Gmail, Calendar, and Drive access

3. **Set up Domain-wide Delegation**:
   - Enable domain-wide delegation for the service account
   - Add OAuth scopes in Google Workspace Admin Console

4. **Required OAuth Scopes**:
   ```
   https://www.googleapis.com/auth/gmail.readonly
   https://www.googleapis.com/auth/calendar
   https://www.googleapis.com/auth/drive
   ```

## Post-Deployment Configuration

After infrastructure deployment:

1. **Upload Function Source Code**:
   ```bash
   # Functions are automatically deployed with source code
   # Verify deployment status
   gcloud functions list --region=${REGION}
   ```

2. **Verify Database Connection**:
   ```bash
   # Connect to Cloud SQL instance
   gcloud sql connect productivity-instance --user=postgres --database=productivity_db
   ```

3. **Test Cloud Functions**:
   ```bash
   # Test email processing function
   curl -X GET "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/productivity-email-processor"
   
   # Test productivity metrics function
   curl -X GET "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/productivity-metrics"
   ```

4. **Verify Scheduler Jobs**:
   ```bash
   # List scheduler jobs
   gcloud scheduler jobs list
   
   # Test manual execution
   gcloud scheduler jobs run productivity-metrics-job
   ```

## Monitoring and Logging

- **Cloud Logging**: Function execution logs and error tracking
- **Cloud Monitoring**: Performance metrics and alerting
- **Cloud Trace**: Request tracing for performance optimization
- **Error Reporting**: Automated error detection and reporting

Access monitoring data:
```bash
# View function logs
gcloud logging read "resource.type=cloud_function" --limit=50

# View scheduler job logs
gcloud logging read "resource.type=cloud_scheduler_job" --limit=20
```

## Security Considerations

- Service account follows principle of least privilege
- All communication encrypted in transit and at rest
- Cloud SQL instance uses private IP when possible
- Function source code stored securely in Cloud Storage
- IAM roles scoped to minimum required permissions

## Troubleshooting

### Common Issues

1. **Function Deployment Failures**:
   ```bash
   # Check function deployment status
   gcloud functions describe function-name --region=${REGION}
   
   # View deployment logs
   gcloud logging read "resource.type=cloud_function resource.labels.function_name=function-name"
   ```

2. **Database Connection Issues**:
   ```bash
   # Verify Cloud SQL instance status
   gcloud sql instances describe productivity-instance
   
   # Check network connectivity
   gcloud sql connect productivity-instance --user=postgres
   ```

3. **Scheduler Job Failures**:
   ```bash
   # Check job execution history
   gcloud scheduler jobs describe job-name
   
   # View execution logs
   gcloud logging read "resource.type=cloud_scheduler_job"
   ```

### Performance Optimization

- Monitor function execution times and optimize memory allocation
- Use Cloud SQL connection pooling for better performance
- Implement function-level caching for frequently accessed data
- Consider upgrading Cloud SQL tier for high-volume deployments

## Cleanup

### Using Infrastructure Manager

```bash
cd infrastructure-manager/

# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/productivity-automation
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete remaining resources
gcloud scheduler jobs delete email-processing-job --quiet
gcloud scheduler jobs delete meeting-automation-job --quiet
gcloud scheduler jobs delete document-organization-job --quiet
gcloud scheduler jobs delete productivity-metrics-job --quiet

gcloud functions delete productivity-email-processor --region=${REGION} --quiet
gcloud functions delete productivity-meeting-automation --region=${REGION} --quiet
gcloud functions delete productivity-document-organization --region=${REGION} --quiet
gcloud functions delete productivity-metrics --region=${REGION} --quiet

gcloud sql instances delete productivity-instance --quiet

gcloud iam service-accounts delete workspace-automation@${PROJECT_ID}.iam.gserviceaccount.com --quiet
```

## Cost Optimization

- Use Cloud SQL f1-micro tier for development/testing
- Configure function timeout and memory to minimize costs
- Implement Cloud Scheduler timezone optimization
- Monitor usage with Cloud Billing reports
- Consider preemptible instances for non-critical workloads

## Customization

### Extending Functionality

1. **Add New Workspace APIs**: Modify function code to integrate additional Google Workspace services
2. **Custom Analytics**: Extend database schema for organization-specific metrics
3. **External Integrations**: Add connectors for third-party productivity tools
4. **Advanced Scheduling**: Implement dynamic scheduling based on business patterns

### Environment-Specific Configurations

- **Development**: Use smaller Cloud SQL tiers and reduced function memory
- **Staging**: Mirror production configuration with limited data retention
- **Production**: Enable high availability, automated backups, and monitoring alerts

## Support

- For infrastructure issues, refer to Google Cloud documentation
- For Google Workspace API issues, consult the [Google Workspace Developer documentation](https://developers.google.com/workspace)
- For recipe-specific questions, refer to the original recipe documentation
- For Terraform provider issues, check the [Google Cloud Terraform provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest)

## Version Information

- **Terraform Provider Version**: `~> 4.0`
- **Google Cloud Provider Version**: `~> 4.84`
- **Infrastructure Manager**: Latest stable version
- **Function Runtime**: Python 3.11
- **Cloud SQL**: PostgreSQL 15

This infrastructure code follows Google Cloud best practices and is designed for production deployment with appropriate security, monitoring, and cost optimization considerations.