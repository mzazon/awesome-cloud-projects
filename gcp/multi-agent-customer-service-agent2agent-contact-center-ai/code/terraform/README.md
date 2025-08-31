# Multi-Agent Customer Service Infrastructure

This Terraform configuration deploys a complete multi-agent customer service system using Google Cloud Contact Center AI Platform, Vertex AI, Cloud Functions, and Firestore for intelligent agent collaboration following Agent2Agent (A2A) protocol principles.

## Architecture Overview

The infrastructure creates:

- **Agent Router Function**: Intelligent routing system that analyzes customer inquiries and directs them to appropriate specialized agents
- **Message Broker Function**: A2A protocol implementation for seamless inter-agent communication and handoffs
- **Specialized Agent Functions**: Domain-specific agents for billing, technical support, and sales inquiries
- **Firestore Database**: Centralized knowledge base and conversation storage
- **Vertex AI Dataset**: Infrastructure for agent training and model artifacts
- **BigQuery Analytics**: Data warehouse for conversation logs and performance analytics
- **Cloud Storage**: Model artifacts and training data storage

## Prerequisites

### Required Tools

- [Terraform](https://terraform.io/) >= 1.5.0
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) >= 450.0.0
- Appropriate Google Cloud IAM permissions for resource creation

### Required Permissions

Your service account or user account needs the following IAM roles:

```
roles/editor                           # For resource creation
roles/serviceusage.serviceUsageAdmin   # For enabling APIs
roles/iam.serviceAccountAdmin          # For service account management
roles/cloudfunctions.admin             # For Cloud Functions deployment
roles/firestore.databaseAdmin          # For Firestore management
roles/bigquery.admin                   # For BigQuery dataset management
roles/storage.admin                    # For Cloud Storage management
```

### Project Requirements

- Google Cloud project with billing enabled
- APIs that will be automatically enabled:
  - AI Platform API
  - Cloud Functions API
  - Firestore API
  - BigQuery API
  - Dialogflow API
  - Contact Center AI Platform API

## Quick Start

### 1. Clone and Setup

```bash
# Navigate to the Terraform directory
cd gcp/multi-agent-customer-service-agent2agent-contact-center-ai/code/terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customization
name_prefix   = "mycompany-agents"
environment   = "prod"
ccai_display_name = "MyCompany Customer Service"

# Analytics configuration
analytics_admin_email = "analytics@yourcompany.com"
organization_domain   = "yourcompany.com"

# Security settings
allow_public_access = false  # Set to true for testing only

# Resource configuration
function_memory_mb = 512
data_retention_days = 90
```

### 3. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment

```bash
# Check function status
gcloud functions list --project=your-project-id

# Test the agent router
curl -X POST $(terraform output -raw agent_router_url) \
  -H "Content-Type: application/json" \
  -d '{"message":"I need help with my bill","session_id":"test-001"}'
```

## Configuration Options

### Core Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `name_prefix` | Resource name prefix | Auto-generated | No |
| `environment` | Environment (dev/staging/prod) | `dev` | No |

### Function Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `function_memory_mb` | Memory allocation for functions | `256` |
| `function_timeout_seconds` | Function timeout | `60` |
| `broker_memory_mb` | Message broker memory | `512` |
| `python_runtime` | Python runtime version | `python311` |

### Security Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `allow_public_access` | Allow public function access | `true` |
| `service_account_email` | Custom service account | Auto-created |
| `authorized_networks` | Authorized CIDR blocks | `[]` |

### Analytics Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `analytics_admin_email` | Analytics admin email | `""` |
| `organization_domain` | Organization domain | `""` |
| `data_retention_days` | Log retention period | `30` |

### Agent Specialization

```hcl
agent_specializations = {
  billing = {
    capabilities = ["payments", "invoices", "refunds", "subscriptions"]
    expertise_level = "expert"
    memory_mb = 256
    timeout_seconds = 60
  }
  technical = {
    capabilities = ["troubleshooting", "installations", "configurations"]
    expertise_level = "expert"
    memory_mb = 256
    timeout_seconds = 60
  }
  sales = {
    capabilities = ["product_info", "pricing", "demos", "upgrades"]
    expertise_level = "expert"
    memory_mb = 256
    timeout_seconds = 60
  }
}
```

## Usage Examples

### Testing Agent Router

```bash
# Test billing inquiry routing
curl -X POST $(terraform output -raw agent_router_url) \
  -H "Content-Type: application/json" \
  -d '{
    "message": "I need help with my monthly invoice and payment",
    "session_id": "test-billing-001"
  }'

# Test technical inquiry routing
curl -X POST $(terraform output -raw agent_router_url) \
  -H "Content-Type: application/json" \
  -d '{
    "message": "My software is not working and showing errors",
    "session_id": "test-technical-001"
  }'

# Test sales inquiry routing
curl -X POST $(terraform output -raw agent_router_url) \
  -H "Content-Type: application/json" \
  -d '{
    "message": "I want to see a demo of your new features",
    "session_id": "test-sales-001"
  }'
```

### Testing Agent2Agent Communication

```bash
# Test inter-agent handoff
curl -X POST $(terraform output -raw message_broker_url) \
  -H "Content-Type: application/json" \
  -d '{
    "source_agent": "billing",
    "target_agent": "technical",
    "message": "Customer needs technical help after billing issue resolved",
    "session_id": "test-handoff-001",
    "handoff_reason": "technical_escalation"
  }'
```

### Testing Specialized Agents

```bash
# Test billing agent directly
curl -X POST $(terraform output -raw billing_agent_url) \
  -H "Content-Type: application/json" \
  -d '{
    "message": "I want a refund for my last order",
    "session_id": "test-billing-direct-001"
  }'

# Test technical agent directly
curl -X POST $(terraform output -raw technical_agent_url) \
  -H "Content-Type: application/json" \
  -d '{
    "message": "I need help installing the software",
    "session_id": "test-technical-direct-001"
  }'
```

## Monitoring and Operations

### Viewing Logs

```bash
# View router function logs
gcloud functions logs read $(terraform output -raw name_prefix)-router \
  --region=$(terraform output -raw region) \
  --project=$(terraform output -raw project_id)

# View all function logs
gcloud logging read 'resource.type="cloud_function"' \
  --project=$(terraform output -raw project_id) \
  --limit=50
```

### Monitoring Conversations

```bash
# List knowledge base entries
gcloud firestore documents list knowledge \
  --project=$(terraform output -raw project_id)

# View recent routing decisions
gcloud firestore documents list routing_logs \
  --project=$(terraform output -raw project_id) \
  --limit=10

# Check agent interactions
gcloud firestore documents list agent_interactions \
  --project=$(terraform output -raw project_id) \
  --limit=10
```

### BigQuery Analytics

```bash
# Query conversation analytics
bq query --use_legacy_sql=false \
  "SELECT agent_type, COUNT(*) as interactions 
   FROM \`$(terraform output -raw project_id).$(terraform output -raw analytics_dataset_id).conversation_logs\`
   GROUP BY agent_type"

# Analyze routing confidence
bq query --use_legacy_sql=false \
  "SELECT AVG(confidence_score) as avg_confidence, agent_type 
   FROM \`$(terraform output -raw project_id).$(terraform output -raw analytics_dataset_id).conversation_logs\`
   GROUP BY agent_type"
```

## Customization

### Adding New Agent Types

To add a new agent type (e.g., "support"):

1. Update the `local.agent_types` list in `main.tf`
2. Add knowledge base data in `local.knowledge_base_data`
3. Create agent response templates in the function code
4. Update routing keywords in variables

### Modifying Agent Responses

Agent responses are defined in the `specialized_agent.py` template. Modify the `AGENT_RESPONSES` dictionary to customize responses for each agent type.

### Integrating with External Systems

Use the provided webhook endpoints to integrate with:
- CRM systems
- Helpdesk platforms
- Chat interfaces
- Voice systems

## Security Considerations

### Production Security Settings

```hcl
# Production-ready security configuration
allow_public_access = false
authorized_networks = ["10.0.0.0/8", "172.16.0.0/12"]
enable_detailed_monitoring = true
```

### IAM Best Practices

- Use least-privilege service accounts
- Enable audit logging
- Implement proper secret management
- Regular security reviews

### Data Protection

- All data encrypted at rest and in transit
- Configurable data retention policies
- GDPR/compliance-ready architecture
- Customer data anonymization support

## Cost Optimization

### Estimated Costs

| Usage Level | Monthly Cost (USD) | Description |
|-------------|-------------------|-------------|
| Light | $5-15 | < 1,000 requests/month |
| Moderate | $15-50 | 1,000-10,000 requests/month |
| Heavy | $50-200+ | > 10,000 requests/month |

### Cost Optimization Features

- Automatic storage lifecycle policies
- Function memory optimization
- BigQuery partitioning and clustering
- Optional preemptible instances

## Troubleshooting

### Common Issues

**Function deployment fails:**
```bash
# Check API enablement
gcloud services list --enabled --project=your-project-id

# Verify IAM permissions
gcloud projects get-iam-policy your-project-id
```

**Firestore access denied:**
```bash
# Check Firestore database exists
gcloud firestore databases list --project=your-project-id

# Verify service account permissions
gcloud projects get-iam-policy your-project-id \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:*"
```

**Function errors:**
```bash
# View detailed error logs
gcloud functions logs read FUNCTION_NAME \
  --region=REGION \
  --project=PROJECT_ID \
  --limit=100
```

### Debug Mode

Enable debug logging by setting:

```bash
export TF_LOG=DEBUG
export TF_LOG_PROVIDER=DEBUG
```

## Backup and Recovery

### Data Backup

```bash
# Backup Firestore data
gcloud firestore export gs://$(terraform output -raw model_storage_bucket)/backups/$(date +%Y%m%d-%H%M%S) \
  --project=$(terraform output -raw project_id)

# Backup BigQuery data
bq extract --destination_format CSV \
  $(terraform output -raw project_id):$(terraform output -raw analytics_dataset_id).conversation_logs \
  gs://$(terraform output -raw model_storage_bucket)/bigquery-backup/conversation_logs_$(date +%Y%m%d).csv
```

### Infrastructure Recovery

```bash
# Export Terraform state
terraform show -json > infrastructure-backup.json

# Restore from backup
terraform import google_project_service.required_apis your-project-id
```

## Cleanup

To destroy all resources:

```bash
# Remove all infrastructure
terraform destroy

# Verify cleanup
gcloud functions list --project=your-project-id
gcloud firestore databases list --project=your-project-id
```

**Note:** Some resources like Firestore databases require manual deletion through the Google Cloud Console.

## Support

For issues with this infrastructure:

1. Check the [troubleshooting section](#troubleshooting)
2. Review Google Cloud documentation
3. Check Terraform provider documentation
4. Enable debug logging for detailed error information

## Contributing

To contribute improvements:

1. Test changes in a development environment
2. Update documentation
3. Ensure security best practices
4. Add appropriate variable validation
5. Update cost estimates if needed