# Infrastructure as Code for Automated Event Creation with Apps Script and Calendar API

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Event Creation with Apps Script and Calendar API".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud project with billing enabled
- Appropriate permissions for resource creation:
  - `roles/cloudbuild.builds.editor`
  - `roles/iam.serviceAccountAdmin` 
  - `roles/serviceusage.serviceUsageAdmin`
  - `roles/storage.admin`
- For Infrastructure Manager: Infrastructure Manager API enabled
- For Terraform: Terraform >= 1.0 installed locally
- Basic familiarity with Google Apps Script and Calendar API

> **Note**: This recipe primarily involves Google Apps Script configuration rather than traditional GCP infrastructure resources. The IaC implementations focus on supporting infrastructure like service accounts, API enablement, and project configuration.

## Quick Start

### Using Infrastructure Manager (GCP)

Infrastructure Manager is Google Cloud's native infrastructure as code service that uses Terraform-compatible configuration.

```bash
# Enable required APIs
gcloud services enable cloudresourcemanager.googleapis.com \
    config.googleapis.com \
    serviceusage.googleapis.com

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/event-automation \
    --service-account="projects/PROJECT_ID/serviceAccounts/SERVICE_ACCOUNT_EMAIL" \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/inputs.yaml"

# Check deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/event-automation
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" \
               -var="region=us-central1"

# Apply configuration
terraform apply -var="project_id=YOUR_PROJECT_ID" \
                -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide a simplified deployment experience with guided setup.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# Follow prompts to configure:
# - Google Cloud project ID
# - Preferred region
# - Service account configuration
# - API enablement
```

## Post-Deployment Configuration

After deploying the supporting infrastructure, complete the Apps Script setup:

1. **Create Google Sheet**:
   - Navigate to sheets.google.com
   - Create a new spreadsheet named "Event Schedule"
   - Add headers: Title, Date, Start Time, End Time, Description, Location, Attendees
   - Add sample event data

2. **Create Apps Script Project**:
   - Navigate to script.google.com
   - Create new project named "Event Automation Script"
   - Copy the automation code from the recipe
   - Update the sheet ID in the `readEventData()` function

3. **Configure Service Account** (if using):
   - The deployed service account can be used for enhanced security
   - Configure OAuth scopes for Calendar and Sheets APIs
   - Update Apps Script to use service account authentication

4. **Set Up Triggers**:
   - Run the `createDailyTrigger()` function to establish automation
   - Configure trigger timing based on your needs

## Architecture Overview

The supporting infrastructure includes:

- **Service Account**: For Apps Script authentication (optional)
- **API Enablement**: Calendar API, Sheets API, Apps Script API
- **IAM Roles**: Appropriate permissions for calendar and sheet access
- **Project Configuration**: Basic project setup and organization

The main automation logic runs in Google Apps Script (serverless) and doesn't require traditional compute infrastructure.

## Customization

### Variables and Parameters

Each implementation supports customization through variables:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `service_account_name`: Name for the automation service account
- `apis_to_enable`: List of APIs to enable for the project

### Infrastructure Manager Inputs

Edit `infrastructure-manager/inputs.yaml`:

```yaml
project_id:
  description: "Google Cloud project ID"
  type: string
  default: "your-project-id"

region:
  description: "Deployment region"
  type: string
  default: "us-central1"

service_account_name:
  description: "Service account for automation"
  type: string
  default: "event-automation-sa"
```

### Terraform Variables

Edit `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
service_account_name = "event-automation-sa"
apis_to_enable = [
  "calendar-json.googleapis.com",
  "sheets.googleapis.com",
  "script.googleapis.com"
]
```

## Monitoring and Logging

### Apps Script Monitoring

- View execution logs at script.google.com
- Monitor trigger execution in Apps Script dashboard
- Set up email notifications for automation failures

### GCP Monitoring

```bash
# View Cloud Logging for API usage
gcloud logging read "resource.type=api" --limit=50

# Monitor service account usage
gcloud logging read "resource.type=service_account" --limit=50
```

### Setting Up Alerts

```bash
# Create notification channel for email alerts
gcloud alpha monitoring channels create \
    --display-name="Apps Script Alerts" \
    --type=email \
    --channel-labels=email_address=admin@example.com

# Create alerting policy for API errors
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring/api-error-policy.yaml
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/event-automation

# Confirm deletion
gcloud infra-manager deployments list --location=REGION
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID" \
                  -var="region=us-central1"

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
# Script will remove:
# - Service accounts
# - IAM bindings
# - API configurations (optional)
```

### Manual Cleanup

For Apps Script resources:

1. **Remove Triggers**:
   - Run `removeAllTriggers()` function in Apps Script
   - Or manually delete from Apps Script trigger dashboard

2. **Archive Resources**:
   - Archive or delete the Google Sheet
   - Delete the Apps Script project if no longer needed
   - Remove calendar events created during testing

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   # Enable required APIs manually
   gcloud services enable calendar-json.googleapis.com
   gcloud services enable sheets.googleapis.com
   gcloud services enable script.googleapis.com
   ```

2. **Permission Denied**:
   ```bash
   # Check current user permissions
   gcloud auth list
   gcloud projects get-iam-policy PROJECT_ID
   
   # Add required roles
   gcloud projects add-iam-policy-binding PROJECT_ID \
       --member="user:YOUR_EMAIL" \
       --role="roles/serviceusage.serviceUsageAdmin"
   ```

3. **Apps Script Authorization**:
   - Ensure OAuth consent screen is configured
   - Grant necessary scopes for Calendar and Sheets APIs
   - Check Apps Script execution permissions

### Debugging

```bash
# View deployment logs
gcloud infra-manager deployments describe \
    projects/PROJECT_ID/locations/REGION/deployments/event-automation \
    --format="value(latestRevision.logs)"

# Check service account status
gcloud iam service-accounts describe \
    SERVICE_ACCOUNT_EMAIL \
    --project=PROJECT_ID
```

## Security Considerations

### Service Account Security

- Use least privilege principle for service account roles
- Regularly rotate service account keys if using JSON keys
- Monitor service account usage through Cloud Logging

### Apps Script Security

- Review and approve OAuth scopes carefully
- Use trigger-based execution rather than public web apps
- Implement proper error handling to avoid information disclosure

### Data Privacy

- Ensure calendar data handling complies with privacy requirements
- Use appropriate sharing settings for Google Sheets
- Consider data retention policies for automation logs

## Cost Optimization

- Apps Script execution is free within generous quotas
- APIs used (Calendar, Sheets) are typically free for normal usage
- Supporting GCP resources (service accounts, logging) have minimal cost
- Monitor API usage to stay within free tier limits

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Google Cloud Documentation**: 
   - [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
   - [Apps Script Documentation](https://developers.google.com/apps-script)
   - [Calendar API Documentation](https://developers.google.com/calendar)
3. **Community Support**: 
   - Stack Overflow with tags `google-apps-script`, `google-calendar-api`
   - Google Cloud Community forums

## Version Information

- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12
- **Infrastructure Manager**: Compatible with latest API version
- **Terraform**: Requires >= 1.0, tested with Google Provider >= 4.0
- **Google Cloud CLI**: Requires latest stable version

## Next Steps

After successful deployment:

1. Test the Apps Script automation with sample data
2. Configure production triggers and scheduling
3. Set up monitoring and alerting for production use
4. Consider implementing the challenge enhancements from the recipe
5. Review and optimize automation for your specific use case