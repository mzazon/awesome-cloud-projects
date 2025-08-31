# Personal Productivity Assistant with Gemini and Functions - Terraform Infrastructure

This directory contains complete Terraform Infrastructure as Code (IaC) for deploying the Personal Productivity Assistant using Google Cloud Platform services. The solution leverages Gemini 2.5 Flash for AI-powered email processing, Cloud Functions for serverless execution, and various Google Cloud services for a comprehensive productivity automation system.

## 🏗️ Architecture Overview

The infrastructure deploys the following components:

- **Cloud Functions**: Serverless email processing using Gemini 2.5 Flash
- **Vertex AI**: AI platform for advanced email analysis and response generation
- **Firestore**: NoSQL database for storing email analysis results and action items
- **Pub/Sub**: Asynchronous messaging for scalable email processing workflows
- **Cloud Scheduler**: Automated scheduling for periodic email processing
- **Cloud Storage**: Secure storage for function source code and temporary files
- **Cloud Monitoring**: Comprehensive monitoring, alerting, and dashboards
- **IAM**: Least-privilege security configuration for all components

## 📋 Prerequisites

### Required Tools
- [Terraform](https://www.terraform.io/downloads) >= 1.6.0
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) >= 450.0.0
- [Git](https://git-scm.com/downloads) for version control

### Google Cloud Requirements
- Google Cloud account with billing enabled
- Project with appropriate permissions (Owner or Editor role recommended)
- Vertex AI API access enabled
- Gmail API access configured (for full functionality)

### Required APIs
The following APIs will be automatically enabled during deployment:
- Cloud Functions API
- Vertex AI API
- Firestore API
- Pub/Sub API
- Cloud Scheduler API
- Gmail API
- Cloud Build API
- Cloud Resource Manager API
- IAM API
- Cloud Logging API
- Cloud Monitoring API

## 🚀 Quick Start

### 1. Clone and Setup

```bash
# Clone the repository (if not already done)
git clone <repository-url>
cd gcp/personal-productivity-assistant-gemini-functions/code/terraform

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required Variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional Configuration
environment                  = "development"
schedule_cron               = "*/15 8-18 * * 1-5"  # Every 15 min, 8 AM-6 PM, Mon-Fri
schedule_timezone           = "America/New_York"
allow_unauthenticated_access = false
enable_monitoring           = true
enable_security_policy      = false

# Resource Configuration
email_processor_memory      = 1024  # MB
email_processor_timeout     = 300   # seconds
max_function_instances      = 100
min_function_instances      = 0

# AI Configuration
gemini_model_name          = "gemini-2.5-flash-002"
gemini_temperature         = 0.3
gemini_top_p              = 0.8
gemini_max_output_tokens  = 2048

# Additional labels for resource organization
additional_labels = {
  team        = "productivity"
  cost-center = "engineering"
  owner       = "your-email@company.com"
}
```

### 3. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# Confirm the deployment when prompted
# Type 'yes' to proceed
```

### 4. Configure OAuth for Gmail API

After deployment, configure OAuth credentials:

1. Go to the [Google Cloud Console API Credentials page](https://console.cloud.google.com/apis/credentials)
2. Click "Create Credentials" > "OAuth client ID"
3. Choose "Desktop application"
4. Download the credentials JSON file
5. Store securely for use with the Gmail integration helper

## 📊 Monitoring and Observability

### Cloud Monitoring Dashboard

The deployment includes a comprehensive monitoring dashboard with:

- **Function Performance**: Invocation rates, execution duration, error rates
- **AI Usage**: Vertex AI API calls and response times
- **Data Operations**: Firestore read/write operations
- **Message Processing**: Pub/Sub message flow and acknowledgments
- **System Health**: Overall system status and resource utilization
- **Cost Tracking**: Estimated monthly costs by service

Access the dashboard: `https://console.cloud.google.com/monitoring/dashboards`

### Alert Policies

Automated alerts are configured for:
- Function error rates > 10%
- Vertex AI API failures
- Pub/Sub message processing delays
- Resource quota approaching limits

### Logging

Structured logging is available through Cloud Logging:

```bash
# View function logs
gcloud functions logs read email-processor --region=us-central1 --limit=50

# View scheduler logs
gcloud logging read 'resource.type="cloud_scheduler_job" AND resource.labels.job_id="email-processing-schedule"' --limit=50

# View all productivity assistant logs
gcloud logging read 'labels.project="personal-productivity-assistant"' --limit=100
```

## 🧪 Testing and Validation

### 1. Function Health Check

```bash
# Get function URL from Terraform output
FUNCTION_URL=$(terraform output -raw email_processor_function_url)

# Test the function with sample data
curl -X POST $FUNCTION_URL \
  -H "Content-Type: application/json" \
  -d '{
    "email_id": "test-123",
    "subject": "Test Email Processing",
    "sender": "test@example.com",
    "body": "Please review the quarterly report and schedule a meeting for next week to discuss the findings. This is urgent."
  }'
```

Expected response includes:
- Action items extracted from the email
- AI-generated summary
- Suggested reply with appropriate tone
- Urgency score (1-10)

### 2. Verify Data Storage

```bash
# Check Firestore collections
gcloud firestore collections list

# Query recent email analysis
gcloud firestore documents list --collection-id=email_analysis --limit=5
```

### 3. Test Scheduled Processing

```bash
# Manually trigger the scheduled job
gcloud scheduler jobs run email-processing-schedule --location=us-central1

# Check execution logs
gcloud functions logs read scheduled-email-processor --region=us-central1 --limit=10
```

### 4. Monitor System Health

```bash
# Check all services status
gcloud services list --enabled --filter="name:aiplatform OR name:cloudfunctions OR name:firestore"

# Monitor Pub/Sub topic
gcloud pubsub topics describe email-processing-topic
```

## 🔧 Configuration Options

### Environment-Specific Deployments

Use Terraform workspaces for multiple environments:

```bash
# Create development workspace
terraform workspace new development
terraform apply -var-file="environments/development.tfvars"

# Create production workspace
terraform workspace new production
terraform apply -var-file="environments/production.tfvars"
```

### Scaling Configuration

Adjust function scaling based on your needs:

```hcl
# High-volume configuration
max_function_instances = 200
min_function_instances = 5
email_processor_memory = 2048

# Low-volume configuration
max_function_instances = 50
min_function_instances = 0
email_processor_memory = 512
```

### Security Hardening

For production deployments:

```hcl
allow_unauthenticated_access = false
enable_security_policy      = true
rate_limit_requests_per_minute = 30
enable_point_in_time_recovery = true
```

## 💰 Cost Management

### Estimated Monthly Costs (USD)

| Service | Light Usage | Moderate Usage | Heavy Usage |
|---------|-------------|----------------|-------------|
| Cloud Functions | $2-5 | $5-15 | $15-40 |
| Vertex AI (Gemini) | $5-10 | $10-30 | $30-100 |
| Firestore | $1-2 | $2-5 | $5-15 |
| Pub/Sub | $0.50-1 | $1-3 | $3-8 |
| Storage | $0.50-1 | $1-2 | $2-5 |
| Monitoring | $0-1 | $1-2 | $2-5 |
| **Total** | **$9-20** | **$20-57** | **$57-173** |

### Cost Optimization Tips

1. **Function Optimization**:
   - Use appropriate memory allocation (1GB recommended for AI workloads)
   - Set reasonable timeout values
   - Implement proper error handling to avoid retries

2. **AI Usage Optimization**:
   - Monitor token usage in Vertex AI
   - Optimize prompt engineering for efficiency
   - Use appropriate model temperature settings

3. **Storage Optimization**:
   - Enable lifecycle policies for old data
   - Use Firestore efficiently with proper indexing
   - Regular cleanup of temporary files

4. **Monitoring**:
   - Set up budget alerts
   - Use Cloud Monitoring to track costs
   - Regular review of resource utilization

## 🔒 Security Best Practices

### IAM and Access Control
- Service accounts follow least-privilege principle
- Function-specific IAM roles
- No hardcoded credentials in code
- OAuth 2.0 for Gmail API access

### Data Protection
- Firestore point-in-time recovery enabled
- Encryption at rest and in transit
- Secure handling of email content
- Data retention policies implemented

### Network Security
- HTTPS-only function triggers
- Optional Cloud Armor security policies
- VPC integration available for enhanced isolation
- Rate limiting for API protection

### Monitoring and Auditing
- Cloud Audit Logs enabled
- Function execution logging
- Security event monitoring
- Regular security reviews

## 🛠️ Troubleshooting

### Common Issues

#### 1. Function Deployment Fails
```bash
# Check Cloud Build logs
gcloud builds list --limit=5

# Verify required APIs are enabled
gcloud services list --enabled | grep -E "(cloudfunctions|aiplatform|firestore)"

# Check IAM permissions
gcloud projects get-iam-policy $PROJECT_ID
```

#### 2. Vertex AI Access Issues
```bash
# Verify Vertex AI API is enabled
gcloud services enable aiplatform.googleapis.com

# Check service account permissions
gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members" --filter="bindings.members:*@*.iam.gserviceaccount.com"
```

#### 3. Function Timeout Issues
```bash
# Check function logs for timeout errors
gcloud functions logs read email-processor --region=us-central1 | grep -i timeout

# Increase timeout in terraform.tfvars
email_processor_timeout = 540  # Maximum allowed
```

#### 4. Pub/Sub Message Processing Issues
```bash
# Check subscription status
gcloud pubsub subscriptions describe email-processing-sub

# Monitor message flow
gcloud pubsub topics publish email-processing-topic --message='{"test": "message"}'
```

### Debug Mode

Enable debug logging for troubleshooting:

```hcl
# In terraform.tfvars
enable_debug_logging = true
```

### Support Resources

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Firestore Documentation](https://cloud.google.com/firestore/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## 🧹 Cleanup

### Destroy Infrastructure

```bash
# Destroy all resources (careful!)
terraform destroy

# Confirm destruction when prompted
# Type 'yes' to proceed
```

### Selective Cleanup

To remove specific resources:

```bash
# Remove monitoring components only
terraform destroy -target=google_monitoring_dashboard.productivity_dashboard
terraform destroy -target=google_monitoring_alert_policy.function_error_rate

# Remove functions only
terraform destroy -target=google_cloudfunctions_function.email_processor
terraform destroy -target=google_cloudfunctions_function.scheduled_processor
```

### Post-Cleanup Verification

```bash
# Verify resources are deleted
gcloud functions list --regions=us-central1
gcloud firestore databases list
gcloud pubsub topics list
```

**Warning**: Destroying Firestore will permanently delete all stored email analysis data. Ensure you have backups if needed.

## 🤝 Contributing

### Development Workflow

1. Create a feature branch
2. Make changes to Terraform configuration
3. Test with `terraform plan`
4. Update documentation as needed
5. Submit pull request

### Code Style

- Use consistent formatting (`terraform fmt`)
- Add comments for complex configurations
- Follow naming conventions
- Include variable descriptions and validation

### Testing

- Test in development environment first
- Validate with different configurations
- Ensure cleanup works properly
- Document any breaking changes

## 📄 License

This infrastructure code is part of the Personal Productivity Assistant recipe and follows the same licensing terms as the main project.

## 📞 Support

For infrastructure-specific issues:
1. Check the troubleshooting section above
2. Review Terraform and Google Cloud documentation
3. Check GitHub issues for similar problems
4. Contact the development team

For application-level issues, refer to the main recipe documentation.

---

**Note**: This infrastructure code is designed to be production-ready but should be customized based on your specific requirements, security policies, and compliance needs.