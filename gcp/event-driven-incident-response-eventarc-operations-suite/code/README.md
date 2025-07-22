# Infrastructure as Code for Event-Driven Incident Response with Eventarc and Cloud Operations Suite

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Event-Driven Incident Response with Eventarc and Cloud Operations Suite".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code using YAML
- **Terraform**: Multi-cloud infrastructure as code using HCL
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 400.0.0 or later)
- Google Cloud project with the following APIs enabled:
  - Eventarc API
  - Cloud Functions API
  - Cloud Run API
  - Cloud Monitoring API
  - Cloud Logging API
  - Cloud Pub/Sub API
  - Cloud Build API
- Appropriate permissions:
  - Project Editor role or custom role with necessary permissions for:
    - Eventarc Admin
    - Cloud Functions Admin
    - Cloud Run Admin
    - Monitoring Admin
    - Logging Admin
    - Pub/Sub Admin
    - Service Account Admin
    - IAM Admin
- Docker installed locally (for Cloud Run service development)
- Basic understanding of event-driven architectures and incident response procedures

## Architecture Overview

This solution creates an automated incident response system with the following components:

- **Service Account**: Dedicated service account with minimal required permissions
- **Pub/Sub Topics**: Event routing infrastructure for incident alerts
- **Cloud Functions**: Serverless functions for incident triage and notifications
- **Cloud Run Services**: Containerized services for complex remediation and escalation workflows
- **Eventarc Triggers**: Event routing configuration connecting monitoring alerts to response services
- **Cloud Monitoring Alert Policies**: Sample monitoring policies for testing the incident response workflow

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native infrastructure as code solution, providing seamless integration with Google Cloud services.

```bash
# Clone the repository and navigate to the code directory
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"

# Create a deployment using Infrastructure Manager
gcloud infra-manager deployments create incident-response-deployment \
    --location=us-central1 \
    --source=. \
    --input-values=project_id=${PROJECT_ID}

# Monitor the deployment progress
gcloud infra-manager deployments describe incident-response-deployment \
    --location=us-central1

# List all created resources
gcloud infra-manager resources list \
    --deployment=incident-response-deployment \
    --location=us-central1
```

### Using Terraform

Terraform provides a consistent workflow for managing infrastructure across multiple cloud providers.

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your configuration
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
EOF

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply

# View the outputs
terraform output
```

### Using Bash Scripts

For quick deployment and testing, use the provided bash scripts.

```bash
# Navigate to the scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy the infrastructure
./deploy.sh

# The script will:
# 1. Enable required APIs
# 2. Create service accounts and IAM policies
# 3. Deploy Cloud Functions and Cloud Run services
# 4. Configure Eventarc triggers
# 5. Create sample monitoring alert policies
```

## Configuration Options

### Infrastructure Manager Variables

The Infrastructure Manager deployment accepts the following input values:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Primary region for resources | `us-central1` | No |
| `zone` | Primary zone for resources | `us-central1-a` | No |
| `random_suffix` | Random suffix for unique naming | Auto-generated | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud project ID | string | - | Yes |
| `region` | Primary region for resources | string | `us-central1` | No |
| `zone` | Primary zone for resources | string | `us-central1-a` | No |
| `environment` | Environment name | string | `dev` | No |
| `labels` | Resource labels | map(string) | `{}` | No |

### Script Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `PROJECT_ID` | Google Cloud project ID | Yes |
| `REGION` | Primary region for resources | No (defaults to us-central1) |
| `ZONE` | Primary zone for resources | No (defaults to us-central1-a) |

## Testing the Deployment

After deployment, test the incident response workflow:

### 1. Simulate a Monitoring Alert

```bash
# Get the incident topic name
INCIDENT_TOPIC=$(gcloud pubsub topics list --filter="name~incident-alerts" --format="value(name)" | head -1)

# Publish a test incident message
gcloud pubsub topics publish ${INCIDENT_TOPIC} \
    --message='{"incident": {"incident_id": "test-001", "condition_name": "high_cpu_utilization", "resource_name": "test-vm"}, "timestamp": "2025-01-20T10:00:00Z"}'
```

### 2. Verify Function Execution

```bash
# Check triage function logs
gcloud functions logs read incident-triage --limit=10

# Check notification function logs
gcloud functions logs read incident-notify --limit=10
```

### 3. Verify Cloud Run Services

```bash
# Check remediation service logs
gcloud logs read "resource.type=cloud_run_revision AND resource.labels.service_name~remediation" --limit=10

# Check escalation service logs
gcloud logs read "resource.type=cloud_run_revision AND resource.labels.service_name~escalation" --limit=10
```

### 4. Monitor Eventarc Triggers

```bash
# List all Eventarc triggers
gcloud eventarc triggers list --location=${REGION}

# Check trigger logs
gcloud logging read "resource.type=eventarc_trigger" --limit=10
```

## Cost Optimization

To optimize costs for this deployment:

1. **Function Memory**: Adjust Cloud Functions memory allocation based on actual usage
2. **Cloud Run Scaling**: Configure minimum instances to 0 for infrequent usage
3. **Monitoring Retention**: Set appropriate log retention periods
4. **Alert Policies**: Fine-tune alert thresholds to reduce false positives

Expected monthly costs (moderate usage):
- Cloud Functions: $10-20
- Cloud Run: $15-30
- Pub/Sub: $5-10
- Eventarc: $5-10
- Monitoring: $10-20
- **Total**: $50-100/month

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID} \
       --flatten="bindings[].members" \
       --format="table(bindings.role)" \
       --filter="bindings.members~incident-response-sa"
   ```

2. **Function Deployment Failures**
   ```bash
   # Check Cloud Build logs
   gcloud builds list --filter="status=FAILURE" --limit=5
   
   # View detailed build logs
   gcloud builds log [BUILD_ID]
   ```

3. **Eventarc Trigger Issues**
   ```bash
   # Check trigger status
   gcloud eventarc triggers describe [TRIGGER_NAME] --location=${REGION}
   
   # Verify event routing
   gcloud logging read "resource.type=eventarc_trigger AND severity>=ERROR" --limit=10
   ```

4. **Cloud Run Service Issues**
   ```bash
   # Check service status
   gcloud run services list --region=${REGION}
   
   # View service logs
   gcloud run services logs read [SERVICE_NAME] --region=${REGION}
   ```

### Debugging Steps

1. **Verify API Enablement**
   ```bash
   gcloud services list --enabled --filter="name~(eventarc|functions|run|monitoring|logging|pubsub)"
   ```

2. **Check Resource Creation**
   ```bash
   # List all resources by label
   gcloud asset search-all-resources --query="labels.project=${PROJECT_ID}"
   ```

3. **Monitor Resource Health**
   ```bash
   # Check Cloud Functions health
   gcloud functions describe [FUNCTION_NAME] --region=${REGION}
   
   # Check Cloud Run health
   gcloud run services describe [SERVICE_NAME] --region=${REGION}
   ```

## Customization

### Adding New Incident Types

1. **Update Triage Function**: Modify the `determine_severity()` and `determine_response_action()` functions
2. **Add Response Logic**: Extend remediation and escalation services with new incident handling
3. **Create Alert Policies**: Add new monitoring alert policies for additional incident types

### Integrating External Systems

1. **Notification Channels**: Update notification functions to integrate with Slack, PagerDuty, or email systems
2. **Ticketing Systems**: Modify escalation service to create tickets in Jira, ServiceNow, or other ITSM tools
3. **Custom Metrics**: Add custom metrics to Cloud Monitoring for tracking incident response effectiveness

### Security Enhancements

1. **Network Security**: Configure VPC connectors for private network access
2. **Secret Management**: Use Secret Manager for API keys and credentials
3. **Audit Logging**: Enable Cloud Audit Logs for compliance and security monitoring

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete incident-response-deployment \
    --location=us-central1 \
    --delete-policy=DELETE

# Verify deletion
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Verify destruction
terraform show
```

### Using Bash Scripts

```bash
cd scripts/

# Run the cleanup script
./destroy.sh

# The script will:
# 1. Delete Eventarc triggers
# 2. Delete Cloud Functions
# 3. Delete Cloud Run services
# 4. Delete monitoring policies
# 5. Delete Pub/Sub topics
# 6. Delete service accounts
```

## Additional Resources

- [Google Cloud Eventarc Documentation](https://cloud.google.com/eventarc/docs)
- [Cloud Operations Suite Best Practices](https://cloud.google.com/monitoring/docs/best-practices)
- [Incident Response Best Practices](https://cloud.google.com/architecture/framework/reliability/incident-response)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest)

## Support

For issues with this infrastructure code:

1. Check the [troubleshooting section](#troubleshooting) above
2. Review the original recipe documentation
3. Consult Google Cloud documentation for specific service issues
4. Use `gcloud feedback` to report Google Cloud CLI issues

## Contributing

To improve this infrastructure code:

1. Follow Google Cloud best practices
2. Test changes in a development environment
3. Update documentation for any new features
4. Ensure compatibility with all three deployment methods