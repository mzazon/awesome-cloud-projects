# Infrastructure as Code for Personal Task Manager with Cloud Functions and Google Tasks

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Personal Task Manager with Cloud Functions and Google Tasks".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture

This solution deploys a serverless REST API using Google Cloud Functions that integrates with Google Tasks API to provide centralized task management capabilities. The infrastructure includes:

- Google Cloud Function (Python 3.12 runtime)
- Service Account with Google Tasks API access
- Required Google Cloud APIs (Cloud Functions, Tasks, Cloud Build)
- IAM roles and permissions

## Prerequisites

### General Requirements
- Google Cloud Platform account with billing enabled
- Google Cloud CLI (gcloud) installed and configured
- Appropriate permissions for resource creation:
  - Project Editor or Owner role
  - Service Account Admin role
  - Cloud Functions Admin role
  - API Admin role

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Google Cloud CLI with Infrastructure Manager components
- Project with Infrastructure Manager API enabled

#### Terraform
- Terraform v1.0+ installed
- Google Cloud provider configured

#### Bash Scripts
- bash shell environment
- curl for API testing
- jq for JSON processing (optional, for testing)

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/task-manager \
    --config-file=main.yaml \
    --input-values="project_id=PROJECT_ID,region=us-central1"

# Monitor deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/task-manager
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=PROJECT_ID" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=PROJECT_ID" -var="region=us-central1"

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

# Test the deployed function (optional)
# The script will output the function URL for testing
```

## Configuration Options

### Infrastructure Manager Variables

Edit the `main.yaml` file or provide input values:

- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `function_name`: Cloud Function name (default: task-manager)
- `service_account_name`: Service account name (default: task-manager-sa)

### Terraform Variables

Configure in `terraform.tfvars` or via command line:

```hcl
project_id = "your-project-id"
region = "us-central1"
function_name = "task-manager"
service_account_name = "task-manager-sa"
function_memory = "256Mi"
function_timeout = "60s"
```

### Bash Script Configuration

Set environment variables before running:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FUNCTION_NAME="task-manager"
```

## API Usage

Once deployed, the function provides these endpoints:

### List Tasks
```bash
curl -X GET "https://REGION-PROJECT_ID.cloudfunctions.net/FUNCTION_NAME/tasks"
```

### Create Task
```bash
curl -X POST "https://REGION-PROJECT_ID.cloudfunctions.net/FUNCTION_NAME/tasks" \
     -H "Content-Type: application/json" \
     -d '{"title": "New Task", "notes": "Task description"}'
```

### Delete Task
```bash
curl -X DELETE "https://REGION-PROJECT_ID.cloudfunctions.net/FUNCTION_NAME/tasks/TASK_ID"
```

## Security Considerations

- The Cloud Function is deployed with `--allow-unauthenticated` for demonstration purposes
- Service account follows principle of least privilege with minimal required permissions
- CORS is enabled for web client compatibility
- For production use, consider implementing:
  - API key authentication
  - Rate limiting
  - Input validation
  - Request logging

## Monitoring and Troubleshooting

### View Function Logs
```bash
gcloud functions logs read FUNCTION_NAME --region=REGION --limit=50
```

### Check Function Status
```bash
gcloud functions describe FUNCTION_NAME --region=REGION
```

### Monitor API Usage
- Use Google Cloud Console to view Cloud Functions metrics
- Monitor Tasks API quotas and usage
- Set up alerting for function errors or high latency

## Cost Optimization

- Cloud Functions free tier includes 2 million invocations per month
- Google Tasks API has generous free quotas for personal use
- Consider setting up budget alerts for cost monitoring
- Use Cloud Monitoring to track function performance and optimize memory allocation

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/task-manager
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Ensure service account has proper Google Tasks API access
   - Verify Cloud Functions API is enabled
   - Check IAM roles and permissions

2. **Function Deployment Failures**
   - Verify Python dependencies in requirements.txt
   - Check function source code syntax
   - Ensure service account credentials file is included

3. **API Integration Issues**
   - Verify Google Tasks API is enabled
   - Check service account key configuration
   - Review function logs for authentication errors

4. **CORS Issues**
   - Verify CORS headers are properly configured
   - Check browser developer tools for CORS errors
   - Ensure preflight OPTIONS requests are handled

### Getting Help

- Check Cloud Functions documentation: https://cloud.google.com/functions/docs
- Review Google Tasks API documentation: https://developers.google.com/tasks
- Use `gcloud functions logs read` for detailed error information
- Monitor function performance in Google Cloud Console

## Extension Ideas

Consider these enhancements for production use:

1. **Multi-list Support**: Add endpoints for managing multiple task lists
2. **User Authentication**: Implement OAuth 2.0 for multi-user support
3. **Task Scheduling**: Integrate with Google Calendar API for due dates
4. **Webhook Notifications**: Use Cloud Pub/Sub for task notifications
5. **Advanced Search**: Add filtering and search capabilities
6. **Mobile Integration**: Create companion mobile app using the API

## Support

For issues with this infrastructure code, refer to:
- Original recipe documentation
- Google Cloud Functions documentation
- Google Tasks API documentation
- Provider-specific troubleshooting guides

---

**Note**: This infrastructure code is generated based on the recipe "Personal Task Manager with Cloud Functions and Google Tasks". Customize the variables and configurations according to your specific requirements and security policies.