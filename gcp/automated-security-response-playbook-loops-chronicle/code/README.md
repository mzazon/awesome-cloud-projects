# Infrastructure as Code for Automated Security Response with Playbook Loops and Chronicle

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Security Response with Playbook Loops and Chronicle".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Security Command Center Enterprise or Premium tier enabled
- Chronicle SOAR platform access and permissions
- Appropriate IAM roles:
  - Security Center Admin
  - Cloud Functions Developer
  - Pub/Sub Admin
  - IAM Admin
  - Service Account Admin
- Estimated cost: $50-100/month for moderate security event volume

## Architecture Overview

This implementation deploys:

- **Security Command Center Integration**: Notification channels for real-time threat detection
- **Cloud Functions**: Threat enrichment and automated response functions
- **Pub/Sub Topics**: Reliable messaging for security event processing
- **IAM Service Account**: Secure automation with least privilege permissions
- **Logging Configuration**: Comprehensive audit trails and monitoring

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Create deployment
gcloud infra-manager deployments create security-automation \
    --location=us-central1 \
    --service-account=terraform@PROJECT_ID.iam.gserviceaccount.com \
    --gcs-source=gs://BUCKET_NAME/infrastructure-manager/main.yaml

# Monitor deployment status
gcloud infra-manager deployments describe security-automation \
    --location=us-central1

# View deployment outputs
gcloud infra-manager deployments describe security-automation \
    --location=us-central1 \
    --format="value(terraformOutputs)"
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" \
               -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" \
                -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable and deploy
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# View deployment status
gcloud functions list --format="table(name,status,trigger.eventTrigger.eventType)"
gcloud pubsub topics list --format="table(name)"
```

## Configuration Options

### Infrastructure Manager Variables

Key configuration options available in `infrastructure-manager/main.yaml`:

- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `random_suffix`: Unique suffix for resource names
- `security_topic_name`: Pub/Sub topic for security events
- `response_topic_name`: Pub/Sub topic for response actions
- `service_account_name`: Service account for automation functions

### Terraform Variables

Customize your deployment by modifying `terraform/variables.tf` or providing values:

```bash
# Using variable file
terraform apply -var-file="custom.tfvars"

# Using command line
terraform apply \
  -var="project_id=my-security-project" \
  -var="region=us-east1" \
  -var="function_memory=1024" \
  -var="enable_audit_logs=true"
```

Available variables:
- `project_id`: GCP project ID (required)
- `region`: Deployment region
- `zone`: Deployment zone
- `function_memory`: Memory allocation for Cloud Functions (default: 512MB)
- `function_timeout`: Timeout for Cloud Functions (default: 300s)
- `enable_audit_logs`: Enable detailed audit logging
- `scc_notification_filter`: Security Command Center notification filter

### Bash Script Configuration

Set environment variables before running deployment scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export FUNCTION_MEMORY="512MB"
export FUNCTION_TIMEOUT="300s"
export RANDOM_SUFFIX="$(openssl rand -hex 3)"
```

## Post-Deployment Configuration

### Chronicle SOAR Playbook Setup

After infrastructure deployment, configure Chronicle SOAR:

1. **Access Chronicle SOAR Console**:
   ```bash
   echo "Navigate to: https://chronicle.security"
   echo "Project integration topic: projects/${PROJECT_ID}/topics/${SECURITY_TOPIC}"
   ```

2. **Create Security Response Playbook**:
   - Import the playbook configuration from `chronicle-playbook-config.json`
   - Configure Playbook Loops for entity processing
   - Set up Pub/Sub integration with deployed topics

3. **Configure Threat Intelligence Sources**:
   - Add VirusTotal, URLVoid, and AbuseIPDB integrations
   - Configure reputation score thresholds
   - Set up conditional response actions

### Security Command Center Configuration

Enable and configure Security Command Center notifications:

```bash
# Verify SCC notification configuration
gcloud scc notifications list \
    --organization=$(gcloud organizations list --format="value(name)")

# Test notification channel
gcloud pubsub topics publish ${SECURITY_TOPIC} \
    --message='{"test": "security_event"}'
```

## Testing and Validation

### Function Testing

Test deployed Cloud Functions:

```bash
# Generate test security events
python3 scripts/generate-test-events.py

# Monitor function logs
gcloud functions logs read threat-enrichment-${RANDOM_SUFFIX} --limit=10
gcloud functions logs read automated-response-${RANDOM_SUFFIX} --limit=10

# Check Pub/Sub message flow
gcloud pubsub topics list-subscriptions ${SECURITY_TOPIC}
```

### Security Response Validation

Verify automated response capabilities:

```bash
# Check IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:security-automation-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# Monitor security logs
gcloud logging read 'resource.type="cloud_function" AND 
    resource.labels.function_name~"security"' --limit=5
```

### Performance Monitoring

Monitor system performance and security metrics:

```bash
# View function performance metrics
gcloud functions describe threat-enrichment-${RANDOM_SUFFIX} \
    --format="value(name,status,updateTime)"

# Check Pub/Sub throughput
gcloud pubsub topics describe ${SECURITY_TOPIC} \
    --format="value(name,messageStoragePolicy)"
```

## Troubleshooting

### Common Issues

1. **Function Deployment Failures**:
   ```bash
   # Check function deployment logs
   gcloud functions logs read FUNCTION_NAME --limit=20
   
   # Verify IAM permissions
   gcloud projects get-iam-policy PROJECT_ID
   ```

2. **Pub/Sub Message Delivery Issues**:
   ```bash
   # Check subscription status
   gcloud pubsub subscriptions describe SUBSCRIPTION_NAME
   
   # View undelivered messages
   gcloud pubsub subscriptions pull SUBSCRIPTION_NAME --auto-ack
   ```

3. **Security Command Center Integration**:
   ```bash
   # Verify SCC API enablement
   gcloud services list --enabled --filter="name:securitycenter.googleapis.com"
   
   # Check organization-level access
   gcloud organizations list
   ```

### Debugging

Enable debug logging for detailed troubleshooting:

```bash
# Set debug environment variables
export GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
export CLOUDSDK_CORE_VERBOSITY=debug

# Re-run deployment with verbose output
./scripts/deploy.sh
```

## Cleanup

### Using Infrastructure Manager (GCP)

```bash
# Delete deployment
gcloud infra-manager deployments delete security-automation \
    --location=us-central1 \
    --quiet

# Verify resource cleanup
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=YOUR_PROJECT_ID" \
                  -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
chmod +x scripts/destroy.sh
./scripts/destroy.sh

# Manual verification
gcloud functions list
gcloud pubsub topics list
gcloud iam service-accounts list
```

### Manual Cleanup Verification

Ensure complete resource removal:

```bash
# Check remaining resources
echo "Verifying cleanup completion..."

# Functions
REMAINING_FUNCTIONS=$(gcloud functions list --filter="name~security" --format="value(name)" | wc -l)
echo "Remaining functions: ${REMAINING_FUNCTIONS}"

# Pub/Sub topics
REMAINING_TOPICS=$(gcloud pubsub topics list --filter="name~security" --format="value(name)" | wc -l)
echo "Remaining topics: ${REMAINING_TOPICS}"

# Service accounts
REMAINING_SA=$(gcloud iam service-accounts list --filter="email~security-automation" --format="value(email)" | wc -l)
echo "Remaining service accounts: ${REMAINING_SA}"

if [ "$REMAINING_FUNCTIONS" -eq 0 ] && [ "$REMAINING_TOPICS" -eq 0 ] && [ "$REMAINING_SA" -eq 0 ]; then
    echo "✅ All resources successfully cleaned up"
else
    echo "⚠️  Some resources may require manual cleanup"
fi
```

## Security Considerations

### IAM Best Practices

- Service accounts use least privilege permissions
- Functions run with dedicated service account
- Cross-service communication secured with IAM roles
- Audit logging enabled for all security operations

### Data Protection

- Pub/Sub messages encrypted in transit and at rest
- Function environment variables secured
- Security findings processed with data classification
- Audit trails maintained for compliance

### Network Security

- Functions deployed in VPC for network isolation
- Private Google Access enabled for secure API communication
- Cloud Armor integration for DDoS protection
- Traffic encryption enforced

## Monitoring and Observability

### Metrics and Alerting

Set up monitoring for security automation:

```bash
# Create alerting policies
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring/function-errors.yaml

# Configure notification channels
gcloud alpha monitoring channels create \
    --channel-content-from-file=monitoring/email-channel.yaml
```

### Dashboard Configuration

Access pre-configured dashboards:

- **Security Operations Dashboard**: Monitor threat detection and response metrics
- **Function Performance Dashboard**: Track automation function execution and errors
- **Pub/Sub Metrics Dashboard**: Monitor message flow and delivery rates

### Log Analysis

Query security automation logs:

```bash
# Function execution logs
gcloud logging read 'resource.type="cloud_function" AND
    labels."function-name"~"security"' \
    --format="table(timestamp,severity,textPayload)"

# Security Command Center integration logs
gcloud logging read 'protoPayload.serviceName="securitycenter.googleapis.com"' \
    --format="table(timestamp,severity,protoPayload.methodName)"
```

## Customization

### Function Code Modifications

Extend automation capabilities:

1. **Enhanced Threat Intelligence**:
   - Modify `threat-enrichment` function to integrate additional TI sources
   - Add custom reputation scoring algorithms
   - Implement threat actor attribution logic

2. **Custom Response Actions**:
   - Extend `automated-response` function with new action types
   - Add integration with ITSM systems (ServiceNow, Jira)
   - Implement custom notification channels

### Playbook Loop Enhancements

Customize Chronicle SOAR workflows:

1. **Multi-Entity Processing**:
   - Configure loops for bulk IOC processing
   - Add entity correlation logic
   - Implement timeline analysis

2. **Conditional Response Logic**:
   - Add business context to response decisions
   - Implement asset criticality scoring
   - Configure escalation thresholds

## Support and Resources

### Documentation Links

- [Chronicle SOAR Documentation](https://cloud.google.com/chronicle/docs/soar)
- [Security Command Center Guide](https://cloud.google.com/security-command-center/docs)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [Pub/Sub Security Guide](https://cloud.google.com/pubsub/docs/security)

### Community Resources

- [Google Cloud Security Community](https://cloud.google.com/security/community)
- [Chronicle SOAR User Forums](https://community.chronicle.security)
- [Cloud Security Best Practices](https://cloud.google.com/security/best-practices)

### Professional Services

For enterprise implementations, consider:
- Google Cloud Professional Services
- Certified Google Cloud Security Partners
- Chronicle SOAR implementation specialists

## License

This infrastructure code is provided under the same license as the parent repository. Please refer to the main LICENSE file for details.

## Contributing

Contributions to improve this infrastructure code are welcome. Please:

1. Test changes in a non-production environment
2. Follow Google Cloud best practices
3. Update documentation for any modifications
4. Submit pull requests with detailed descriptions

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.