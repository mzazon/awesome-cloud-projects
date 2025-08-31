# Infrastructure as Code for Automated Threat Response with Unified Security and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Threat Response with Unified Security and Functions".

## Overview

This solution creates an intelligent, automated security response system using Security Command Center's AI-powered threat detection integrated with Cloud Functions for immediate remediation actions. The infrastructure implements event-driven architecture with Pub/Sub for real-time processing, comprehensive logging, and automated response capabilities.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure deploys the following components:

- **Security Command Center Integration**: AI-powered threat detection and analysis
- **Pub/Sub Topics & Subscriptions**: Event-driven messaging for security findings
- **Cloud Functions**: 
  - Security triage function for intelligent threat analysis
  - Automated remediation function for critical threats
  - Notification function for alerts and human review
- **Cloud Logging**: Centralized logging with security findings export
- **Cloud Monitoring**: Custom metrics and alerting for security operations
- **IAM Roles & Permissions**: Least-privilege security model

## Prerequisites

### Required Tools
- Google Cloud CLI (`gcloud`) installed and configured
- Terraform >= 1.5.0 (for Terraform implementation)
- Infrastructure Manager API enabled (for Infrastructure Manager implementation)
- Bash shell environment (Linux/macOS/WSL)

### Required Permissions
Your account needs the following IAM roles:
- Cloud Functions Admin (`roles/cloudfunctions.admin`)
- Pub/Sub Admin (`roles/pubsub.admin`)
- Logging Admin (`roles/logging.admin`)
- Monitoring Admin (`roles/monitoring.admin`)
- Security Center Admin (`roles/securitycenter.admin`)
- Service Account Admin (`roles/iam.serviceAccountAdmin`)

### Security Command Center Requirements
- Security Command Center Premium or Enterprise subscription
- Contact Google Cloud sales if not already available in your organization

### Cost Considerations
- Estimated monthly cost: $20-40 for functions, logging, and Pub/Sub resources
- Security Command Center Premium/Enterprise subscription fees apply separately
- Costs may vary based on security event volume and function execution frequency

## Quick Start

### Environment Setup

```bash
# Set your project ID
export PROJECT_ID="your-security-project-id"
export REGION="us-central1"

# Configure gcloud
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}

# Enable required APIs
gcloud services enable cloudfunctions.googleapis.com \
                       pubsub.googleapis.com \
                       logging.googleapis.com \
                       monitoring.googleapis.com \
                       securitycenter.googleapis.com \
                       cloudbuild.googleapis.com
```

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments create automated-threat-response \
    --location=${REGION} \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe automated-threat-response \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"

# Apply the configuration
terraform apply \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Run deployment script
./deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `random_suffix` | Suffix for resource names | Auto-generated | No |
| `enable_monitoring` | Enable custom monitoring metrics | `true` | No |
| `function_timeout` | Cloud Function timeout (seconds) | `300` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `random_suffix` | Suffix for resource names | Auto-generated | No |
| `triage_function_memory` | Memory for triage function | `512` | No |
| `remediation_function_memory` | Memory for remediation function | `1024` | No |
| `notification_function_memory` | Memory for notification function | `256` | No |

### Customization Examples

```bash
# Deploy with custom memory settings
terraform apply \
    -var="project_id=${PROJECT_ID}" \
    -var="region=europe-west1" \
    -var="triage_function_memory=1024" \
    -var="remediation_function_memory=2048"

# Deploy with Infrastructure Manager and custom timeout
gcloud infra-manager deployments create automated-threat-response \
    --location=${REGION} \
    --local-source="." \
    --inputs="project_id=${PROJECT_ID},region=${REGION},function_timeout=600"
```

## Validation & Testing

### Verify Deployment

```bash
# Check Cloud Functions status
gcloud functions list --filter="name:security" \
    --format="table(name,status,trigger.eventTrigger.eventType)"

# Verify Pub/Sub infrastructure
gcloud pubsub topics list --format="table(name)"
gcloud pubsub subscriptions list --format="table(name,topic)"

# Check log sink configuration
gcloud logging sinks list --format="table(name,destination,filter)"
```

### Test Security Pipeline

```bash
# Create test security finding
cat > test-finding.json << 'EOF'
{
  "name": "organizations/123456789/sources/1234567890/findings/test-finding-001",
  "severity": "HIGH",
  "category": "PRIVILEGE_ESCALATION",
  "resourceName": "//compute.googleapis.com/projects/test-project/zones/us-central1-a/instances/test-instance",
  "description": "Test privilege escalation finding for automated response validation",
  "sourceProperties": {
    "suspiciousMembers": ["user:test@example.com"],
    "timestamp": "2025-07-12T10:00:00Z"
  }
}
EOF

# Get topic name from deployment
TOPIC_NAME=$(gcloud pubsub topics list --filter="name:threat-response-topic" --format="value(name)" | head -1)

# Publish test message
gcloud pubsub topics publish ${TOPIC_NAME##*/} \
    --message="$(cat test-finding.json)"

# Check function logs
gcloud functions logs read security-triage --limit=10
```

### Monitor Function Performance

```bash
# Check function metrics
gcloud monitoring time-series list \
    --filter='metric.type="custom.googleapis.com/security/findings_processed"' \
    --interval-end-time="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --interval-start-time="$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)"

# View function execution logs
gcloud functions logs read automated-remediation --limit=5
gcloud functions logs read security-notification --limit=5
```

## Outputs

After successful deployment, the following resources will be available:

### Infrastructure Manager Outputs
- `pubsub_topic_names`: Names of created Pub/Sub topics
- `function_names`: Names of deployed Cloud Functions
- `log_sink_name`: Name of the security findings log sink
- `monitoring_workspace`: Cloud Monitoring workspace for security metrics

### Terraform Outputs
- `security_triage_function_name`: Name of the security triage function
- `remediation_function_name`: Name of the automated remediation function
- `notification_function_name`: Name of the security notification function
- `threat_response_topic`: Main Pub/Sub topic for security findings
- `remediation_topic`: Pub/Sub topic for remediation actions
- `notification_topic`: Pub/Sub topic for notifications
- `log_sink_destination`: Destination of the security findings log sink

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete automated-threat-response \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"

# Remove Terraform state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Confirm resource removal
gcloud functions list --filter="name:security"
gcloud pubsub topics list --filter="name:threat"
```

### Manual Cleanup Verification

```bash
# Verify all resources are removed
echo "Checking for remaining resources..."

# Check Cloud Functions
REMAINING_FUNCTIONS=$(gcloud functions list --filter="name:security" --format="value(name)" | wc -l)
echo "Remaining functions: ${REMAINING_FUNCTIONS}"

# Check Pub/Sub topics
REMAINING_TOPICS=$(gcloud pubsub topics list --filter="name:threat" --format="value(name)" | wc -l)
echo "Remaining topics: ${REMAINING_TOPICS}"

# Check log sinks
REMAINING_SINKS=$(gcloud logging sinks list --filter="name:security-findings" --format="value(name)" | wc -l)
echo "Remaining sinks: ${REMAINING_SINKS}"

if [ ${REMAINING_FUNCTIONS} -eq 0 ] && [ ${REMAINING_TOPICS} -eq 0 ] && [ ${REMAINING_SINKS} -eq 0 ]; then
    echo "✅ All resources successfully cleaned up"
else
    echo "⚠️  Some resources may still exist - manual verification recommended"
fi
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   ```bash
   # Verify your account has required permissions
   gcloud auth list
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

2. **Security Command Center Access**
   ```bash
   # Check if Security Command Center is enabled
   gcloud services list --enabled --filter="name:securitycenter.googleapis.com"
   ```

3. **Function Deployment Failures**
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5 --format="table(id,status,logUrl)"
   
   # Verify function source code
   gcloud functions describe security-triage --format="yaml"
   ```

4. **Pub/Sub Message Processing**
   ```bash
   # Check subscription backlog
   gcloud pubsub subscriptions describe threat-response-sub --format="value(numUndeliveredMessages)"
   
   # View subscription configuration
   gcloud pubsub subscriptions describe threat-response-sub
   ```

### Debug Mode

Enable detailed logging for troubleshooting:

```bash
# Set debug environment variable
export CLOUDSDK_CORE_VERBOSITY=debug

# Re-run deployment command with debug output
gcloud functions deploy security-triage --verbosity=debug
```

### Getting Help

- Review the original recipe documentation for implementation details
- Check Google Cloud documentation for Security Command Center and Cloud Functions
- Contact Google Cloud support for Security Command Center Premium/Enterprise issues
- Report infrastructure code issues to the recipe maintainers

## Security Considerations

### IAM Best Practices
- All functions use dedicated service accounts with least-privilege permissions
- Cross-function communication uses service account impersonation
- Log sink uses dedicated service account for Pub/Sub publishing

### Network Security
- Functions deployed with private networking where applicable
- Pub/Sub topics use IAM-based access controls
- Security Command Center integration uses secure API channels

### Monitoring & Auditing
- All security actions are logged for audit purposes
- Custom metrics track function performance and threat processing
- Comprehensive logging enables forensic analysis

### Data Protection
- Security findings are processed in-memory without persistent storage
- Sensitive data is masked in function logs
- Pub/Sub messages use encryption in transit

## Additional Resources

- [Security Command Center Documentation](https://cloud.google.com/security-command-center/docs)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [Pub/Sub Security Guide](https://cloud.google.com/pubsub/docs/access-control)
- [Infrastructure Manager User Guide](https://cloud.google.com/infrastructure-manager/docs)
- [Google Cloud Security Architecture](https://cloud.google.com/architecture/security-foundations)

---

**Note**: This infrastructure code implements the complete automated threat response solution. Ensure you have appropriate Security Command Center subscriptions and permissions before deployment.