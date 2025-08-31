# Infrastructure as Code for Real-time Privilege Escalation Monitoring with PAM and Pub/Sub

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-time Privilege Escalation Monitoring with PAM and Pub/Sub".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Terraform >= 1.0 (for Terraform implementation)
- Appropriate GCP permissions for resource creation:
  - Cloud Logging Admin
  - Pub/Sub Admin
  - Cloud Functions Admin
  - Storage Admin
  - IAM Admin
  - Monitoring Admin
  - Privileged Access Manager Admin
- Billing enabled on your GCP project

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/privilege-monitoring \
    --service-account="${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://source.developers.google.com/p/${PROJECT_ID}/r/infrastructure" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main" \
    --inputs-file="inputs.yaml"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts and provide required configuration
```

## Configuration

### Infrastructure Manager

Edit the `inputs.yaml` file to customize your deployment:

```yaml
project_id: "your-project-id"
region: "us-central1"
zone: "us-central1-a"
environment: "production"
alert_threshold: 2
retention_days: 7
```

### Terraform

Edit the `terraform.tfvars` file to customize your deployment:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
environment = "production"
alert_threshold = 2
retention_days = 7
function_memory = "256MB"
function_timeout = 60
```

### Bash Scripts

The deployment script will prompt for required configuration values or you can set environment variables:

```bash
export GCP_PROJECT="your-project-id"
export GCP_REGION="us-central1"
export GCP_ZONE="us-central1-a"
export ENVIRONMENT="production"
export ALERT_THRESHOLD="2"
```

## Architecture Components

The IaC implementations deploy the following Google Cloud resources:

### Core Infrastructure
- **Pub/Sub Topic**: Receives audit log messages for real-time processing
- **Pub/Sub Subscription**: Delivers messages to Cloud Function with proper retry logic
- **Cloud Function**: Processes privilege escalation events and generates alerts
- **Cloud Storage Bucket**: Archives security alerts for compliance and forensic analysis

### Logging and Monitoring
- **Log Sink**: Routes IAM and PAM audit logs to Pub/Sub topic
- **Cloud Monitoring Alert Policy**: Triggers alerts based on privilege escalation patterns
- **Custom Metrics**: Tracks privilege escalation events for trend analysis

### Security and Access
- **IAM Roles and Bindings**: Secure access between components following least privilege
- **Service Accounts**: Dedicated accounts for each component with minimal permissions
- **Audit Log Configuration**: Comprehensive logging for all privilege-related activities

### Storage and Lifecycle
- **Cloud Storage Lifecycle Policy**: Cost-optimized tiering (Standard → Coldline → Archive)
- **Object Versioning**: Maintains audit trail integrity for compliance
- **Retention Policies**: Configurable retention for regulatory requirements

## Deployment Details

### Resource Naming Convention

All resources follow a consistent naming pattern:
- Format: `{resource-type}-{purpose}-{environment}-{random-suffix}`
- Example: `pubsub-privilege-alerts-prod-a1b2c3`

### Security Features

- **Least Privilege IAM**: Each component has minimal required permissions
- **Encryption**: All data encrypted at rest and in transit
- **Network Security**: Private communication between components
- **Audit Logging**: Comprehensive logging for all administrative actions

### Cost Optimization

- **Storage Lifecycle**: Automatic tiering to reduce long-term storage costs
- **Function Scaling**: Serverless scaling based on actual usage
- **Pub/Sub Configuration**: Optimized message retention and acknowledgment
- **Monitoring Efficiency**: Custom metrics to minimize monitoring costs

## Validation and Testing

After deployment, verify the infrastructure:

```bash
# Check Pub/Sub resources
gcloud pubsub topics list --filter="name:privilege"
gcloud pubsub subscriptions list --filter="name:privilege"

# Verify Cloud Function deployment
gcloud functions list --filter="name:privilege"

# Test log sink configuration
gcloud logging sinks list --filter="name:privilege"

# Check storage bucket
gsutil ls -b gs://privilege-audit-logs-*

# Generate test event
gcloud iam roles create testPrivilegeRole$(date +%s) \
    --title="Test Role" \
    --permissions="storage.objects.get"
```

## Monitoring and Alerting

### Cloud Monitoring Integration

The deployment includes:
- Custom metrics for privilege escalation events
- Alert policies for suspicious activity patterns
- Dashboard templates for security operations

### Log Analysis

Access processed alerts through:
- Cloud Storage for historical analysis
- Cloud Logging for real-time investigation
- Cloud Monitoring for trend analysis

### Notification Channels

To receive alerts, configure notification channels:

```bash
# Create email notification channel
gcloud alpha monitoring channels create \
    --display-name="Security Team" \
    --type="email" \
    --channel-labels="email_address=security@yourcompany.com"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/privilege-monitoring
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove resources:

```bash
# Delete Cloud Function
gcloud functions delete privilege-alert-processor-* --region=us-central1

# Delete Pub/Sub resources
gcloud pubsub subscriptions delete privilege-monitor-sub-*
gcloud pubsub topics delete privilege-escalation-alerts-*

# Delete log sink
gcloud logging sinks delete privilege-escalation-sink-*

# Delete storage bucket
gsutil -m rm -r gs://privilege-audit-logs-*

# Delete custom roles
gcloud iam roles list --project=$(gcloud config get-value project) \
    --filter="name:testPrivilegeRole*" \
    --format="value(name)" | xargs -I {} gcloud iam roles delete {}
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Ensure your account has required IAM permissions
   - Check service account permissions for Infrastructure Manager/Terraform

2. **Function Deployment Failures**
   - Verify APIs are enabled (Cloud Functions, Cloud Build)
   - Check function source code and dependencies

3. **Log Sink Not Working**
   - Verify log sink service account has Pub/Sub Publisher role
   - Check log filter syntax and scope

4. **Storage Access Issues**
   - Confirm Cloud Function service account has Storage Object Creator role
   - Verify bucket naming and regional constraints

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled

# Verify IAM permissions
gcloud projects get-iam-policy $(gcloud config get-value project)

# Test function locally (if source available)
functions-framework --target=process_privilege_alert --debug

# Check log sink permissions
gcloud logging sinks describe privilege-escalation-sink-*
```

## Customization

### Extending Log Filtering

Modify the log sink filter to include additional services:

```bash
# Add Compute Engine audit logs
protoPayload.serviceName="compute.googleapis.com" OR

# Add GKE audit logs  
protoPayload.serviceName="container.googleapis.com" OR

# Add specific method patterns
protoPayload.methodName=~"CreateInstance" OR
protoPayload.methodName=~"DeleteInstance"
```

### Enhancing Alert Processing

Extend the Cloud Function to:
- Integrate with external SIEM systems
- Send alerts to Slack or Teams
- Implement custom risk scoring
- Add geolocation analysis
- Include threat intelligence correlation

### Adding Compliance Features

For regulatory compliance:
- Enable Cloud Asset Inventory for resource tracking
- Add Data Loss Prevention (DLP) scanning
- Implement Cloud Security Command Center integration
- Add automated compliance reporting

## Performance Considerations

### Scaling Limits

- **Pub/Sub**: 10,000 topics per project, 10,000 subscriptions per topic
- **Cloud Functions**: 3,000 concurrent executions per region (default)
- **Cloud Storage**: No practical limits for audit log volumes
- **Log Sinks**: 1,000 sinks per project

### Optimization Tips

- Use regional deployments for lower latency
- Implement message deduplication for high-volume environments  
- Consider Cloud Run for high-throughput processing
- Use Cloud Storage lifecycle policies for cost optimization

## Security Considerations

### Best Practices Implemented

- Least privilege IAM roles for all components
- Encryption at rest and in transit
- Audit logging for all administrative actions
- Network isolation using VPC when applicable
- Regular security scanning and vulnerability assessment

### Additional Security Measures

Consider implementing:
- VPC Service Controls for data exfiltration protection
- Customer-managed encryption keys (CMEK)
- Binary Authorization for container security
- Cloud Asset Inventory for comprehensive resource tracking

## Support and Documentation

### Google Cloud Documentation

- [Privileged Access Manager](https://cloud.google.com/iam/docs/pam-overview)
- [Cloud Audit Logs](https://cloud.google.com/logging/docs/audit)
- [Cloud Functions Security](https://cloud.google.com/functions/docs/securing)
- [Pub/Sub Security](https://cloud.google.com/pubsub/docs/security)

### Recipe Documentation

Refer to the original recipe markdown file for detailed implementation guidance and architectural decisions.

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review Google Cloud documentation
3. Consult the original recipe for context
4. Contact your cloud operations team

## Version Information

- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12
- **Infrastructure Manager**: Compatible with latest Google Cloud APIs
- **Terraform**: Compatible with Google Cloud Provider >= 4.0
- **Generated**: Using recipe-generator-version 1.3