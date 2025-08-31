# Smart Email Template Generation with Gemini and Firestore - Terraform

This directory contains Terraform Infrastructure as Code (IaC) for deploying an AI-powered email template generator using Google Cloud services including Vertex AI Gemini, Firestore, and Cloud Functions.

## Architecture Overview

The solution creates a serverless email template generation system that:

- Uses **Vertex AI Gemini** for intelligent content creation
- Stores user preferences and templates in **Firestore**
- Provides a **Cloud Function** API for template generation
- Includes monitoring and alerting capabilities
- Supports sample data initialization

## Prerequisites

1. **Google Cloud Project** with billing enabled
2. **Terraform** >= 1.5.0 installed
3. **Google Cloud CLI** installed and configured
4. Appropriate permissions for:
   - Cloud Functions administration
   - Firestore database administration  
   - Vertex AI usage
   - IAM administration
   - Cloud Storage administration

## Required Google Cloud APIs

The following APIs will be automatically enabled:

- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Firestore API (`firestore.googleapis.com`)
- Vertex AI API (`aiplatform.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)
- Cloud Resource Manager API (`cloudresourcemanager.googleapis.com`)
- Service Usage API (`serviceusage.googleapis.com`)

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd gcp/smart-email-template-generation-gemini-firestore/code/terraform/
```

### 2. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your values
nano terraform.tfvars
```

**Required variables to update:**
- `project_id`: Your Google Cloud Project ID
- `notification_email`: Your email for monitoring alerts

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Test the Deployment

After deployment, use the output values to test the function:

```bash
# Get the function URL from outputs
FUNCTION_URL=$(terraform output -raw function_url)

# Test with a sample request
curl -X POST "$FUNCTION_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "campaign_type": "newsletter",
    "subject_theme": "quarterly updates",
    "custom_context": "announcing new features"
  }' | jq '.'
```

## Configuration

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | ✅ |
| `region` | Deployment region | `us-central1` | ❌ |
| `function_memory` | Function memory allocation | `512Mi` | ❌ |
| `function_timeout` | Function timeout in seconds | `120` | ❌ |
| `gemini_model` | Gemini model version | `gemini-1.5-flash` | ❌ |
| `notification_email` | Email for alerts | `""` | ❌ |

### Environment Configuration

The solution supports multiple environments through the `environment` variable:

- `development` - For development and testing
- `staging` - For pre-production validation  
- `production` - For production workloads

## Features

### Core Functionality

- **AI-Powered Generation**: Uses Vertex AI Gemini for intelligent email content
- **Flexible Configuration**: Supports multiple campaign types and user preferences
- **Data Persistence**: Stores templates and preferences in Firestore
- **Error Handling**: Comprehensive error handling with fallback templates
- **CORS Support**: Web application integration ready

### Monitoring & Observability

- **Cloud Monitoring**: Automated alerts for function errors
- **Logging**: Structured logging for debugging and troubleshooting
- **Health Checks**: Built-in health check endpoints
- **Performance Monitoring**: Optional detailed performance tracking

### Security Features

- **IAM Integration**: Least privilege service account access
- **Resource Isolation**: Dedicated service accounts and resources
- **Audit Logging**: Optional audit logging for compliance
- **Encryption**: Data encrypted at rest and in transit

## API Usage

### Generate Email Template

**Endpoint:** `POST {function_url}`

**Request Body:**
```json
{
  "campaign_type": "newsletter",
  "subject_theme": "product updates",
  "custom_context": "optional context"
}
```

**Response:**
```json
{
  "success": true,
  "template_id": "abc123",
  "template": {
    "subject": "Exciting Updates from Your Company",
    "body": "Hello [First Name],\\n\\n..."
  },
  "campaign_type": "newsletter"
}
```

### Campaign Types

- `newsletter` - Weekly company updates
- `product_launch` - New feature announcements  
- `welcome` - New subscriber onboarding
- `promotional` - Special offers and deals
- `follow_up` - Re-engagement campaigns
- `event_invitation` - Event and webinar invites

### Health Check

**Endpoint:** `GET {function_url}`

Returns service status and configuration information.

## Firestore Collections

The solution creates and uses these Firestore collections:

### userPreferences
Stores brand and company information:
```json
{
  "company": "TechStart Solutions",
  "industry": "Software", 
  "tone": "professional yet friendly",
  "brandVoice": "innovative, trustworthy",
  "targetAudience": "B2B decision makers"
}
```

### campaignTypes
Defines email campaign configurations:
```json
{
  "purpose": "weekly company updates",
  "cta": "Read More",
  "length": "medium",
  "best_practices": ["tip1", "tip2"]
}
```

### generatedTemplates
Stores generated email templates:
```json
{
  "campaign_type": "newsletter",
  "subject_line": "Updates from Company",
  "email_body": "Email content...",
  "generated_at": "timestamp",
  "model_used": "gemini-1.5-flash"
}
```

## Cost Estimation

### Monthly Cost Breakdown (USD)

| Service | Free Tier | Paid Usage |
|---------|-----------|------------|
| Cloud Functions | 2M invocations, 400K GB-seconds | $0.40/1M invocations |
| Firestore | 50K reads, 20K writes/day | $0.06/100K operations |
| Vertex AI Gemini | Varies | ~$0.075/1K input tokens |
| Cloud Storage | 5GB | $0.02/GB/month |
| Cloud Build | 120 build-minutes/day | $0.003/build-minute |

**Estimated monthly cost for moderate usage:** $5-20 USD

## Troubleshooting

### Common Issues

1. **Function Timeout**
   ```bash
   # Increase timeout in terraform.tfvars
   function_timeout = 300
   ```

2. **Quota Exceeded**
   ```bash
   # Check Vertex AI quotas
   gcloud ai quotas list --region=us-central1
   ```

3. **Permission Denied**
   ```bash
   # Verify API enablement
   gcloud services list --enabled --filter="name:aiplatform"
   ```

4. **Firestore Access Issues**
   ```bash
   # Check database status
   gcloud firestore databases list
   ```

### Debugging Commands

```bash
# View function logs
gcloud functions logs read $(terraform output -raw function_name) \
  --gen2 --region=$(terraform output -raw deployment_region)

# Check function status
gcloud functions describe $(terraform output -raw function_name) \
  --gen2 --region=$(terraform output -raw deployment_region)

# Test Firestore connectivity
gcloud firestore databases describe $(terraform output -raw firestore_database_name)
```

## Customization

### Custom Gemini Model

To use a different Gemini model:

```hcl
# In terraform.tfvars
gemini_model = "gemini-1.5-pro"
```

### Custom Function Configuration

```hcl
# In terraform.tfvars
function_memory = "1Gi"
function_timeout = 300
function_max_instances = 50
```

### Additional User Profiles

The solution supports multiple user preference profiles. Add custom profiles in the data initialization function.

## Security Considerations

### Production Deployment

For production use:

1. **Disable unauthenticated access:**
   ```hcl
   allow_unauthenticated_invocations = false
   ```

2. **Enable deletion protection:**
   ```hcl
   enable_deletion_protection = true
   ```

3. **Configure custom domain:**
   ```hcl
   custom_domain = "api.yourcompany.com"
   ```

4. **Use VPC connector:**
   ```hcl
   vpc_connector = "projects/your-project/locations/us-central1/connectors/your-connector"
   ```

### Compliance Features

- Resource tagging for governance
- Audit logging for compliance
- Data encryption at rest and in transit
- IAM least privilege access

## Monitoring and Alerts

### Alert Policies

The solution creates alerts for:
- High function error rates
- Function timeout issues  
- Firestore connection failures

### Custom Monitoring

Add custom monitoring by:

1. Creating additional alert policies
2. Setting up custom dashboards
3. Configuring notification channels

## Backup and Recovery

### Data Backup

Firestore data is automatically backed up, but consider:

1. **Export important collections:**
   ```bash
   gcloud firestore export gs://your-backup-bucket \
     --collection-ids=userPreferences,campaignTypes
   ```

2. **Version control templates:**
   Store critical templates in version control

### Disaster Recovery

The solution is designed for high availability:
- Multi-region Firestore deployment
- Serverless functions with automatic scaling
- State stored in managed services

## Cleanup

To remove all resources:

```bash
# Destroy infrastructure
terraform destroy

# Confirm deletion
# Type 'yes' when prompted
```

**Note:** Firestore databases with deletion protection enabled must be manually deleted from the Google Cloud Console.

## Support

### Getting Help

1. **Check logs:**
   ```bash
   terraform output troubleshooting_commands
   ```

2. **Review common issues:**
   ```bash
   terraform output common_issues
   ```

3. **Validate deployment:**
   ```bash
   terraform output validation_commands
   ```

### Contributing

To contribute improvements:

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request

## License

This code is provided as part of the Google Cloud Recipe collection. See the main repository for license information.

---

For additional questions or support, refer to the [Google Cloud Documentation](https://cloud.google.com/docs) or the original recipe documentation.