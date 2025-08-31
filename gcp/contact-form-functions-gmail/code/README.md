# Infrastructure as Code for Website Contact Form with Cloud Functions and Gmail API

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Website Contact Form with Cloud Functions and Gmail API".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Gmail account for sending contact form emails
- OAuth 2.0 credentials for Gmail API access
- Appropriate IAM permissions for:
  - Cloud Functions deployment
  - Cloud Build API access
  - Gmail API access
  - Service account management

### Required APIs

The following APIs must be enabled in your Google Cloud project:

```bash
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable gmail.googleapis.com
gcloud services enable config.googleapis.com  # For Infrastructure Manager
```

### Gmail API Setup

Before deploying, you must set up Gmail API credentials:

1. Go to Google Cloud Console > APIs & Credentials > Credentials
2. Create OAuth 2.0 Client ID for "Desktop application"
3. Download the credentials JSON file
4. Generate authentication token using the provided Python script
5. Store the token.pickle file for function deployment

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native infrastructure as code solution that uses standard Terraform syntax with enhanced Google Cloud integration.

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FUNCTION_NAME="contact-form-handler"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments create contact-form-deployment \
    --location=${REGION} \
    --source-blueprint=main.yaml \
    --input-values="project_id=${PROJECT_ID},region=${REGION},function_name=${FUNCTION_NAME}"

# Monitor deployment status
gcloud infra-manager deployments describe contact-form-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"

# Apply infrastructure
terraform apply \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"

# Get function URL from outputs
terraform output function_url
```

### Using Bash Scripts

The bash scripts provide an automated deployment experience similar to the original recipe steps.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure and function
./scripts/deploy.sh

# The script will:
# 1. Enable required APIs
# 2. Create Cloud Function with proper configuration
# 3. Deploy function code with Gmail API integration
# 4. Generate sample HTML contact form
# 5. Display function URL and testing instructions
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `function_name` | Cloud Function name | `contact-form-handler` | No |
| `memory_mb` | Function memory allocation | `512` | No |
| `timeout_seconds` | Function timeout | `60` | No |
| `recipient_email` | Email address to receive form submissions | - | Yes |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `function_name` | Cloud Function name | `contact-form-handler` | No |
| `memory_mb` | Function memory allocation | `512` | No |
| `timeout_seconds` | Function timeout | `60` | No |
| `runtime` | Python runtime version | `python312` | No |

### Bash Script Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud project ID | - | Yes |
| `REGION` | Deployment region | `us-central1` | No |
| `FUNCTION_NAME` | Cloud Function name | `contact-form-handler` | No |

## Deployment Details

### Function Configuration

The Cloud Function is deployed with the following specifications:

- **Runtime**: Python 3.12
- **Memory**: 512 MB
- **Timeout**: 60 seconds
- **Trigger**: HTTP (unauthenticated for public web access)
- **Generation**: 2nd generation for improved performance
- **Source**: Inline code with Gmail API integration

### Security Features

- CORS headers configured for cross-origin requests
- Input validation for all form fields
- Email address format validation
- Error handling for API failures
- OAuth 2.0 authentication for Gmail API

### Network Configuration

- Public HTTP trigger for website integration
- Automatic HTTPS endpoint provisioning
- Built-in DDoS protection
- Regional deployment for optimal performance

## Testing the Deployment

### 1. Verify Function Deployment

```bash
# Check function status
gcloud functions describe ${FUNCTION_NAME} \
    --gen2 \
    --region=${REGION} \
    --format="table(name,state,updateTime)"

# Get function URL
FUNCTION_URL=$(gcloud functions describe ${FUNCTION_NAME} \
    --gen2 \
    --region=${REGION} \
    --format="value(serviceConfig.uri)")

echo "Function URL: ${FUNCTION_URL}"
```

### 2. Test API Endpoint

```bash
# Test with curl
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Test User",
        "email": "test@example.com",
        "subject": "Test Contact Form",
        "message": "This is a test message from the contact form."
    }'
```

Expected response: `{"success": true, "message": "Email sent successfully"}`

### 3. Test HTML Form

If using bash scripts, a sample HTML form is generated automatically:

```bash
# Open the generated HTML form
open contact-form.html  # macOS
xdg-open contact-form.html  # Linux
# Or manually open in your browser
```

### 4. Verify Email Delivery

Check your Gmail inbox for the test email with subject "Contact Form: Test Contact Form".

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete contact-form-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"

# Clean up Terraform state
rm -rf .terraform*
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete the Cloud Function
# 2. Clean up local files
# 3. Optionally delete the project (with confirmation)
```

## Troubleshooting

### Common Issues

1. **Gmail API Authentication Errors**
   - Ensure OAuth 2.0 credentials are properly configured
   - Verify token.pickle file is present in function directory
   - Check Gmail API is enabled in your project

2. **Function Deployment Failures**
   - Verify Cloud Functions API is enabled
   - Check Cloud Build API is enabled
   - Ensure proper IAM permissions

3. **CORS Errors**
   - Function includes proper CORS headers
   - Verify browser isn't blocking cross-origin requests
   - Check function URL is accessible

4. **Email Delivery Issues**
   - Verify Gmail credentials have send permissions
   - Check spam folder for test emails
   - Ensure recipient email is correctly configured

### Debugging

Enable detailed logging:

```bash
# View function logs
gcloud functions logs read ${FUNCTION_NAME} \
    --gen2 \
    --region=${REGION} \
    --limit=50

# Monitor real-time logs
gcloud functions logs tail ${FUNCTION_NAME} \
    --gen2 \
    --region=${REGION}
```

## Customization

### Modifying Email Templates

Edit the function code in `main.py` to customize email formatting:

```python
# Update email body formatting
email_body = f"""
Custom email template:
Name: {name}
Email: {email}
Subject: {subject}
Message: {message}
"""
```

### Adding Rate Limiting

Implement rate limiting by modifying the function to use Cloud Firestore for tracking:

```python
# Add rate limiting logic
from google.cloud import firestore
db = firestore.Client()
# Implement rate limiting checks
```

### Custom Domain Configuration

Configure a custom domain for your function:

```bash
# Map custom domain
gcloud functions add-invoker-policy-binding ${FUNCTION_NAME} \
    --region=${REGION} \
    --member="allUsers"
```

## Cost Optimization

### Function Optimization

- Memory allocation: Start with 512MB, adjust based on usage
- Timeout: Set to minimum required (60s is conservative)
- Concurrency: Use default settings unless high traffic expected

### Free Tier Usage

Cloud Functions provides generous free tier:
- 2 million invocations per month
- 400,000 GB-seconds of compute time
- 200,000 GHz-seconds of CPU time

Most contact forms will operate within free tier limits.

## Security Best Practices

### Function Security

- Use OAuth 2.0 for Gmail API authentication
- Validate all input data server-side
- Implement rate limiting for production use
- Use HTTPS for all communication
- Enable Cloud Armor for DDoS protection

### Data Protection

- Never log sensitive user data
- Implement data retention policies
- Use Cloud KMS for additional encryption if needed
- Regular security audits and updates

## Production Considerations

### Monitoring

Set up monitoring and alerting:

```bash
# Create uptime check
gcloud monitoring uptime create contact-form-check \
    --display-name="Contact Form Function" \
    --hostname=${FUNCTION_URL}
```

### Backup and Recovery

- Function source code is stored in Cloud Storage automatically
- OAuth credentials should be backed up securely
- Document recovery procedures

### High Availability

- Deploy in multiple regions for redundancy
- Use Cloud Load Balancer for failover
- Implement health checks

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Google Cloud Functions documentation
3. Consult Gmail API documentation
4. Review the original recipe documentation
5. Check Google Cloud Status page for service issues

## Additional Resources

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Gmail API Documentation](https://developers.google.com/gmail/api)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Google Cloud CLI Reference](https://cloud.google.com/sdk/gcloud/reference)