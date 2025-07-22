# Infrastructure as Code for Team Collaboration Insights with Workspace Events API and Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Team Collaboration Insights with Workspace Events API and Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code using YAML configuration
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud Platform account with billing enabled
- Google Workspace domain with admin access for Events API configuration
- gcloud CLI installed and configured (or Cloud Shell)
- Domain-wide delegation configured for Workspace Events API access
- Appropriate permissions for resource creation:
  - Cloud Functions Admin
  - Firestore Service Agent
  - Pub/Sub Admin
  - Workspace Events API Admin
  - Service Account Admin
  - Project IAM Admin

> **Note**: This solution requires Google Workspace Business Standard or higher to access the Events API. Free personal Google accounts are not supported.

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Enable required APIs
gcloud services enable config.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable firestore.googleapis.com
gcloud services enable pubsub.googleapis.com
gcloud services enable workspaceevents.googleapis.com

# Deploy infrastructure
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/workspace-analytics \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/workspace-events-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://source.developers.google.com/p/${PROJECT_ID}/r/workspace-analytics-repo" \
    --git-source-directory="infrastructure-manager" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"
```

### Using Terraform

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply infrastructure
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh
```

## Architecture Overview

The infrastructure creates:

- **Cloud Pub/Sub Topic**: Receives Google Workspace events
- **Cloud Functions**: Processes events and generates analytics
- **Cloud Firestore**: Stores collaboration data and metrics
- **Service Accounts**: Secure access for Workspace Events API
- **IAM Policies**: Least privilege access controls
- **Workspace Events Subscriptions**: Monitor Chat, Drive, and Meet events

## Configuration Options

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP Project ID | - | Yes |
| `region` | GCP Region for resources | `us-central1` | No |
| `zone` | GCP Zone for resources | `us-central1-a` | No |
| `function_memory` | Memory allocation for Cloud Functions | `256` | No |
| `function_timeout` | Timeout for Cloud Functions (seconds) | `60` | No |
| `firestore_location` | Firestore database location | `us-central1` | No |

### Infrastructure Manager Variables

Configure in `main.yaml`:

```yaml
variables:
  project_id:
    description: "GCP Project ID"
    type: string
  region:
    description: "GCP Region"
    type: string
    default: "us-central1"
  workspace_domain:
    description: "Google Workspace domain"
    type: string
```

## Post-Deployment Configuration

### 1. Configure Workspace Events API

After infrastructure deployment, configure Workspace Events subscriptions:

```bash
# Get the Pub/Sub topic ARN
PUBSUB_TOPIC="projects/${PROJECT_ID}/topics/workspace-events-topic"

# Create Chat events subscription
curl -X POST \
  "https://workspaceevents.googleapis.com/v1/subscriptions" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "projects/'${PROJECT_ID}'/subscriptions/chat-collaboration-events",
    "targetResource": "//chat.googleapis.com/spaces/-",
    "eventTypes": [
      "google.workspace.chat.message.v1.created",
      "google.workspace.chat.space.v1.updated",
      "google.workspace.chat.membership.v1.created"
    ],
    "notificationEndpoint": {
      "pubsubTopic": "'${PUBSUB_TOPIC}'"
    },
    "payloadOptions": {
      "includeResource": true
    }
  }'
```

### 2. Test Analytics Dashboard

```bash
# Get dashboard function URL
DASHBOARD_URL=$(gcloud functions describe collaboration-analytics \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

# Test analytics endpoint
curl "${DASHBOARD_URL}?days=7&team_id=all"
```

### 3. Verify Event Processing

```bash
# Check Cloud Functions logs
gcloud functions logs read process-workspace-events \
    --region=${REGION} \
    --limit=10

# Monitor Pub/Sub subscription
gcloud pubsub subscriptions pull workspace-events-subscription \
    --auto-ack \
    --limit=5
```

## Security Considerations

### Service Account Permissions

The solution creates service accounts with minimal required permissions:

- **Workspace Events Service Account**: Pub/Sub publisher role
- **Cloud Functions Service Account**: Firestore data writer role
- **Analytics Service Account**: Firestore data reader role

### Firestore Security Rules

The deployment includes security rules that:

- Allow authenticated read access to collaboration events
- Restrict write access to Cloud Functions only
- Enable admin access for service accounts
- Protect sensitive team collaboration data

### Network Security

- Cloud Functions are deployed with HTTPS-only access
- Pub/Sub topics use IAM-based access control
- Firestore uses encrypted connections and data at rest

## Monitoring and Observability

### Cloud Monitoring Metrics

Monitor these key metrics:

- Cloud Functions execution count and duration
- Pub/Sub message throughput and latency
- Firestore read/write operations
- Error rates across all services

### Logging

Enable structured logging for:

- Workspace Events API subscription status
- Cloud Functions event processing
- Firestore security rule violations
- Analytics dashboard access patterns

### Alerts

Recommended alerts:

- High error rates in event processing
- Pub/Sub subscription backlog
- Unusual collaboration activity patterns
- Service account permission failures

## Cost Optimization

### Resource Sizing

- Cloud Functions: Start with 256MB memory, scale based on usage
- Firestore: Use single-region for cost savings if global access not required
- Pub/Sub: Configure message retention based on processing SLA

### Usage Monitoring

- Track Cloud Functions invocations to optimize memory allocation
- Monitor Firestore read/write operations for query optimization
- Analyze Pub/Sub message patterns for subscription tuning

## Troubleshooting

### Common Issues

1. **Workspace Events API Permissions**
   ```bash
   # Verify domain-wide delegation
   gcloud workspace-events subscriptions list
   ```

2. **Cloud Functions Deployment Failures**
   ```bash
   # Check function logs
   gcloud functions logs read process-workspace-events --limit=50
   ```

3. **Firestore Permission Errors**
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

4. **Pub/Sub Message Delivery Issues**
   ```bash
   # Check subscription status
   gcloud pubsub subscriptions describe workspace-events-subscription
   ```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# Set debug environment variable for Cloud Functions
gcloud functions deploy process-workspace-events \
    --set-env-vars "DEBUG=true"
```

## Cleanup

### Using Infrastructure Manager (GCP)

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/workspace-analytics
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup

If automated cleanup fails, manually remove:

1. Workspace Events subscriptions
2. Cloud Functions
3. Pub/Sub topics and subscriptions
4. Firestore database
5. Service accounts and IAM bindings

```bash
# Remove Workspace Events subscriptions
curl -X GET \
  "https://workspaceevents.googleapis.com/v1/subscriptions" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" | \
  jq -r '.subscriptions[].name' | \
  xargs -I {} curl -X DELETE \
    "https://workspaceevents.googleapis.com/v1/{}" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)"

# Clean up remaining resources
gcloud functions delete process-workspace-events --region=${REGION} --quiet
gcloud functions delete collaboration-analytics --region=${REGION} --quiet
gcloud pubsub subscriptions delete workspace-events-subscription
gcloud pubsub topics delete workspace-events-topic
gcloud firestore databases delete --database="(default)" --quiet
```

## Customization

### Adding New Event Types

To monitor additional Workspace events:

1. Update Workspace Events subscriptions
2. Modify Cloud Functions event processing logic
3. Update Firestore data models
4. Enhance analytics calculations

### Custom Analytics Metrics

Extend the analytics dashboard by:

1. Adding new metric calculations in Cloud Functions
2. Creating additional Firestore collections
3. Implementing custom dashboard endpoints
4. Integrating with external BI tools

### Multi-tenant Support

For multiple Workspace domains:

1. Create separate Pub/Sub topics per domain
2. Implement tenant isolation in Firestore
3. Deploy separate Cloud Functions per tenant
4. Configure domain-specific IAM policies

## Performance Optimization

### Cloud Functions

- Optimize memory allocation based on processing requirements
- Implement connection pooling for Firestore
- Use batch writes for high-volume events
- Configure appropriate timeout values

### Firestore

- Design efficient document structures
- Create composite indexes for complex queries
- Implement data lifecycle policies
- Use subcollections for hierarchical data

### Pub/Sub

- Configure appropriate acknowledgment deadlines
- Implement flow control for high-volume scenarios
- Use pull vs push subscriptions based on requirements
- Monitor message ordering requirements

## Integration Examples

### Business Intelligence Tools

Connect to external BI platforms:

```python
# Example: Export data to BigQuery for advanced analytics
from google.cloud import bigquery

def export_to_bigquery():
    client = bigquery.Client()
    dataset_id = "workspace_analytics"
    table_id = "collaboration_events"
    
    # Export Firestore data to BigQuery
    # Implementation details...
```

### Slack Integration

Send collaboration insights to Slack:

```python
# Example: Slack webhook integration
import requests

def send_slack_notification(analytics_data):
    webhook_url = "https://hooks.slack.com/services/..."
    message = f"Daily collaboration score: {analytics_data['collaboration_score']}"
    requests.post(webhook_url, json={"text": message})
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../team-collaboration-insights-workspace-events-functions.md)
2. Review [Google Cloud Functions documentation](https://cloud.google.com/functions/docs)
3. Consult [Workspace Events API documentation](https://developers.google.com/workspace/events)
4. Reference [Cloud Firestore documentation](https://cloud.google.com/firestore/docs)
5. Visit [Terraform Google Cloud Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate against the original recipe requirements
3. Update documentation for any new features
4. Follow Google Cloud best practices
5. Include appropriate security measures