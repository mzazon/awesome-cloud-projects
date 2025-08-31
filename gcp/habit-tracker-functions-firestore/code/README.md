# Infrastructure as Code for Simple Habit Tracker with Cloud Functions and Firestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Habit Tracker with Cloud Functions and Firestore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code tool
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This recipe deploys a serverless habit tracking REST API using:
- **Cloud Functions**: HTTP-triggered Python function providing CRUD operations
- **Firestore**: NoSQL database in Native mode for storing habit records
- **IAM**: Service account and permissions for secure function-to-database communication

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Required APIs enabled:
  - Cloud Functions API (`cloudfunctions.googleapis.com`)
  - Firestore API (`firestore.googleapis.com`)
  - Cloud Resource Manager API (`cloudresourcemanager.googleapis.com`)
- Appropriate permissions for:
  - Creating and managing Cloud Functions
  - Creating and managing Firestore databases
  - Managing IAM service accounts and roles

### Cost Estimates
- Development usage: $0.01-$0.05 per month (typically covered by free tier)
- Cloud Functions: 2M invocations/month free
- Firestore: 1GB storage + 50K reads/20K writes per day free

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's managed Terraform service that provides state management and drift detection.

```bash
# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create habit-tracker-deployment \
    --location=${REGION} \
    --source-type=git \
    --source-repo=. \
    --input-values=project_id=${PROJECT_ID},region=${REGION}

# Monitor deployment progress
gcloud infra-manager deployments describe habit-tracker-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs including Function URL
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy all resources
./scripts/deploy.sh

# The script will output the Cloud Function URL for testing
```

## Testing Your Deployment

After successful deployment, test the habit tracker API:

```bash
# Get the Function URL (replace with your actual URL)
export FUNCTION_URL="https://your-region-your-project.cloudfunctions.net/habit-tracker-function"

# Test CREATE operation
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Daily Exercise",
      "description": "30 minutes of physical activity",
      "completed": false
    }'

# Test GET operation (retrieve all habits)
curl -X GET "${FUNCTION_URL}"

# Test UPDATE operation (replace HABIT_ID with actual ID from CREATE response)
curl -X PUT "${FUNCTION_URL}?id=HABIT_ID" \
    -H "Content-Type: application/json" \
    -d '{"completed": true}'

# Test DELETE operation
curl -X DELETE "${FUNCTION_URL}?id=HABIT_ID"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete habit-tracker-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Clean up local state files
rm -rf .terraform terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm all resources are removed
gcloud functions list --regions=${REGION}
gcloud firestore databases list
```

## Customization

### Variables and Parameters

Each implementation supports the following customizable parameters:

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `function_name` | Cloud Function name | `habit-tracker-function` | No |
| `function_memory` | Function memory allocation | `256MB` | No |
| `function_timeout` | Function timeout | `60s` | No |
| `database_location` | Firestore database location | Same as region | No |

### Infrastructure Manager Customization

Edit `infrastructure-manager/main.yaml` to modify:
- Function runtime version
- Memory and timeout settings
- IAM permissions
- Database configuration

### Terraform Customization

Edit `terraform/variables.tf` to add or modify variables:
```hcl
variable "function_memory" {
  description = "Memory allocation for Cloud Function"
  type        = number
  default     = 256
}
```

### Bash Script Customization

Edit environment variables in `scripts/deploy.sh`:
```bash
# Customize deployment settings
export FUNCTION_MEMORY="512MB"
export FUNCTION_TIMEOUT="120s"
export PYTHON_RUNTIME="python312"
```

## Monitoring and Maintenance

### Function Monitoring

```bash
# View function logs
gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}

# Monitor function metrics
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=${FUNCTION_NAME}"
```

### Firestore Monitoring

```bash
# Check database status
gcloud firestore databases list

# View database operations (requires Cloud Logging)
gcloud logging read "resource.type=firestore_database"
```

### Performance Optimization

- **Cold Starts**: Consider using Cloud Functions min instances for consistent performance
- **Memory Tuning**: Monitor function memory usage and adjust allocation accordingly
- **Concurrency**: Configure max concurrent executions based on expected load
- **Firestore Indexes**: Add composite indexes for complex queries as usage grows

## Security Considerations

### Current Security Features

- **IAM Service Account**: Function runs with minimal required permissions
- **CORS Configuration**: Configured for web client compatibility
- **Input Validation**: Comprehensive request validation in function code
- **HTTPS Only**: All API endpoints use HTTPS encryption

### Production Security Enhancements

For production deployments, consider implementing:

1. **Authentication**: Integrate Firebase Auth or Cloud Identity
```bash
# Enable Firebase Auth API
gcloud services enable firebase.googleapis.com
```

2. **API Gateway**: Add Cloud Endpoints for advanced API management
```bash
# Deploy API configuration
gcloud endpoints services deploy openapi-spec.yaml
```

3. **Rate Limiting**: Implement request quotas
4. **Audit Logging**: Enable Cloud Audit Logs for compliance
5. **VPC Security**: Deploy functions in VPC for network isolation

## Troubleshooting

### Common Issues

**Function Deployment Fails**
```bash
# Check API enablement
gcloud services list --enabled | grep -E "(cloudfunctions|firestore)"

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}
```

**Firestore Permission Errors**
```bash
# Check service account permissions
gcloud projects describe ${PROJECT_ID}

# Verify Firestore database exists
gcloud firestore databases list
```

**CORS Errors in Web Applications**
- Verify CORS headers in function code
- Check browser developer tools for specific CORS issues
- Ensure preflight OPTIONS requests are handled

### Debug Mode

Enable debug logging in bash scripts:
```bash
export DEBUG=true
./scripts/deploy.sh
```

## Integration Examples

### Web Application Integration

```javascript
// Example JavaScript integration
const API_URL = 'https://your-function-url';

async function createHabit(habitData) {
  const response = await fetch(API_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(habitData)
  });
  return response.json();
}
```

### Mobile Application Integration

```dart
// Example Flutter integration
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<Map<String, dynamic>> createHabit(Map<String, dynamic> habit) async {
  final response = await http.post(
    Uri.parse('https://your-function-url'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(habit),
  );
  return json.decode(response.body);
}
```

## Support and Resources

### Documentation Links
- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Firestore Documentation](https://cloud.google.com/firestore/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help
- For infrastructure issues: Check Google Cloud Status page
- For code issues: Review Cloud Functions logs
- For deployment issues: Verify prerequisites and permissions
- For performance issues: Monitor Cloud Functions metrics

### Community Resources
- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow - google-cloud-platform](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [Google Cloud Architecture Center](https://cloud.google.com/architecture)

## License

This infrastructure code is provided as-is for educational and development purposes. Ensure compliance with your organization's policies and Google Cloud's terms of service when deploying to production environments.