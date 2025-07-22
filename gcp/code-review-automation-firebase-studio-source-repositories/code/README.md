# Infrastructure as Code for Code Review Automation with Firebase Studio and Cloud Source Repositories

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Code Review Automation with Firebase Studio and Cloud Source Repositories".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Source Repositories
  - Cloud Functions
  - Vertex AI
  - Firebase Studio
  - Cloud Build
  - Eventarc
- Node.js 20+ (for Cloud Functions runtime)
- Git configured for repository operations

### Required API Enablement

The following APIs must be enabled in your Google Cloud project:
- Cloud Source Repositories API
- Cloud Functions API
- Vertex AI API
- Cloud Build API
- Firebase API
- Eventarc API

### Estimated Costs

- Cloud Functions: $0.40-$2.00 per million invocations
- Vertex AI API calls: $0.002-$0.05 per request (varies by model)
- Cloud Source Repositories: Free for first 5 users, then $1/user/month
- Cloud Build: $0.003 per build-minute (first 120 minutes/day free)
- Firebase Studio: Pricing varies based on usage (currently in preview)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for managing infrastructure using configuration files.

```bash
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"
export DEPLOYMENT_NAME="code-review-automation"
export REGION="us-central1"

# Create the deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="."

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Set required variables
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide a simplified deployment experience with interactive prompts and validation.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the interactive prompts to configure:
# - Project ID
# - Region selection
# - Repository name
# - Function configuration
```

## Architecture Components

This infrastructure deployment creates:

1. **Cloud Source Repository**: Git repository with webhook integration
2. **Cloud Functions**: Serverless function for processing repository events
3. **Vertex AI Configuration**: AI model setup for code analysis
4. **IAM Roles and Policies**: Secure access controls
5. **Eventarc Triggers**: Event-driven automation
6. **Cloud Build Configuration**: CI/CD pipeline integration

## Configuration Options

### Infrastructure Manager Variables

Edit the `main.yaml` file to customize:
- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `repository_name`: Name for the source repository
- `function_name`: Cloud Function name
- `ai_model`: Vertex AI model configuration

### Terraform Variables

Customize deployment by setting these variables in `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
repository_name = "intelligent-review-system"
function_name = "code-review-trigger"
vertex_ai_model = "gemini-2.0-flash-thinking"
enable_monitoring = true
```

### Bash Script Configuration

The deployment script will prompt for:
- Google Cloud project ID
- Target region
- Repository name
- Function configuration
- Webhook settings

## Post-Deployment Setup

### Firebase Studio Configuration

After infrastructure deployment:

1. Access Firebase Studio at https://studio.firebase.google.com
2. Create a new workspace or import your project
3. Configure the AI code review agent using the agent template
4. Set up analysis patterns and review criteria
5. Test the agent with sample code

### Repository Integration

1. Clone the created repository:
   ```bash
   gcloud source repos clone <repository-name>
   ```

2. Configure webhook integration:
   ```bash
   # The function URL will be displayed in deployment outputs
   # Configure repository triggers in Cloud Console
   ```

3. Test the system by pushing code changes

### Monitoring and Logging

Access system monitoring through:
- Cloud Functions logs: `gcloud functions logs read <function-name>`
- Cloud Monitoring dashboards
- Cloud Logging for detailed event tracking

## Validation

### Test the Deployment

1. **Verify Cloud Function**:
   ```bash
   gcloud functions describe <function-name> --region=<region>
   ```

2. **Test AI Analysis**:
   ```bash
   # Send test payload to function
   curl -X POST <function-url> \
     -H "Content-Type: application/json" \
     -d '{"eventType": "push", "changedFiles": [{"path": "test.js", "content": "console.log(\"test\");"}]}'
   ```

3. **Verify Repository**:
   ```bash
   gcloud source repos list
   ```

### Expected Outputs

Successful deployment should provide:
- Repository clone URL
- Cloud Function trigger URL
- Firebase Studio workspace URL
- IAM service account details

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}

# Confirm deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
# Script will validate cleanup completion
```

### Manual Cleanup Verification

After running automated cleanup, verify these resources are deleted:
- Cloud Source Repositories
- Cloud Functions
- IAM service accounts and roles
- Eventarc triggers
- Cloud Build triggers

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   # Enable required APIs
   gcloud services enable sourcerepo.googleapis.com cloudfunctions.googleapis.com aiplatform.googleapis.com
   ```

2. **Insufficient Permissions**:
   - Ensure your account has Project Editor or specific IAM roles
   - Verify service account permissions for Infrastructure Manager

3. **Function Deployment Fails**:
   - Check Cloud Build logs
   - Verify Node.js runtime compatibility
   - Review function source code syntax

4. **Firebase Studio Access**:
   - Verify Firebase API is enabled
   - Check project permissions in Firebase Console
   - Ensure preview access to Firebase Studio

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled

# View function logs
gcloud functions logs read <function-name> --region=<region> --limit=50

# Check IAM permissions
gcloud projects get-iam-policy <project-id>

# Verify repository status
gcloud source repos describe <repository-name>
```

## Advanced Configuration

### Custom AI Models

To use different Vertex AI models:

1. Update model configuration in Terraform variables
2. Modify function code to use specific model endpoints
3. Adjust analysis prompts for model capabilities

### Multi-Repository Support

Extend the solution for multiple repositories:

1. Create additional repository resources
2. Configure shared Cloud Function
3. Implement repository-specific analysis rules

### Enterprise Integration

For enterprise deployment:

1. Configure VPC networking
2. Set up private Google Access
3. Implement organization policies
4. Configure Cloud KMS for encryption

## Security Considerations

- All resources use least-privilege IAM roles
- Function authentication is configured
- Repository access is restricted
- Vertex AI API calls use service account authentication
- Webhook endpoints are secured

## Performance Optimization

- Function cold start mitigation through min instances
- Vertex AI model caching for repeated analysis
- Repository event batching for efficiency
- Monitoring and alerting for performance tracking

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Verify configuration against best practices
4. Use debug commands to diagnose issues

## Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Validate against Google Cloud best practices
3. Update documentation for any configuration changes
4. Follow infrastructure-as-code principles