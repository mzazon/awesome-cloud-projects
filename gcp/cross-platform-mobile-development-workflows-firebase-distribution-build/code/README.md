# Infrastructure as Code for Cross-Platform Mobile Development Workflows with Firebase App Distribution and Cloud Build

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cross-Platform Mobile Development Workflows with Firebase App Distribution and Cloud Build".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Firebase CLI (`firebase`) installed and authenticated
- Terraform 1.3+ installed (for Terraform implementation)
- Appropriate Google Cloud permissions for:
  - Cloud Build API
  - Cloud Source Repositories API
  - Firebase API
  - Firebase Test Lab API
  - Artifact Registry API
- Firebase project creation permissions
- Estimated cost: $15-30 USD for testing resources during deployment

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="mobile-cicd-$(date +%s | tail -c 7)"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/mobile-cicd-pipeline \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/mobile-cicd-pipeline
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars with your configuration
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region = "us-central1"
app_name = "mobile-app-demo"
repo_name = "mobile-source-repo"
EOF

# Plan the deployment
terraform plan -var-file="terraform.tfvars"

# Apply the infrastructure
terraform apply -var-file="terraform.tfvars"
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FIREBASE_PROJECT_ID="${PROJECT_ID}"

# Deploy the infrastructure
./deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables

- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `app_name`: Mobile application name
- `repo_name`: Source repository name
- `android_package_name`: Android package identifier
- `enable_test_lab`: Enable Firebase Test Lab testing (default: true)
- `tester_groups`: List of tester groups to create

### Terraform Variables

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: us-central1)
- `app_name`: Mobile application name (default: mobile-app)
- `repo_name`: Source repository name (default: mobile-source)
- `android_package_name`: Android package identifier
- `build_timeout`: Cloud Build timeout in seconds (default: 1800)
- `machine_type`: Cloud Build machine type (default: E2_HIGHCPU_8)
- `enable_apis`: Automatically enable required APIs (default: true)

### Bash Script Environment Variables

- `PROJECT_ID`: Google Cloud project ID (required)
- `REGION`: Deployment region (default: us-central1)
- `FIREBASE_PROJECT_ID`: Firebase project ID (default: same as PROJECT_ID)
- `APP_NAME`: Mobile application name
- `REPO_NAME`: Source repository name

## What Gets Deployed

This infrastructure creates:

1. **Google Cloud APIs**: Enables required services (Cloud Build, Source Repositories, Firebase, Test Lab)
2. **Firebase Project**: Configured Firebase project with App Distribution
3. **Cloud Source Repository**: Git repository for mobile application code
4. **Cloud Build Triggers**: Automated CI/CD triggers for main and feature branches
5. **Firebase Test Lab Configuration**: Multi-device testing matrix
6. **Firebase App Distribution Setup**: Tester groups and distribution configuration
7. **IAM Roles and Permissions**: Service accounts and permissions for automation
8. **Sample Mobile Application**: Basic Android application structure

## Post-Deployment Steps

1. **Clone Source Repository**:
   ```bash
   gcloud source repos clone ${REPO_NAME} --project=${PROJECT_ID}
   cd ${REPO_NAME}
   ```

2. **Add Testers to Groups**:
   ```bash
   # Add testers to QA group
   firebase appdistribution:testers:add qa-team@example.com \
       --group qa-team --project=${PROJECT_ID}
   
   # Add stakeholders
   firebase appdistribution:testers:add stakeholder@example.com \
       --group stakeholders --project=${PROJECT_ID}
   ```

3. **Commit Sample Code**:
   ```bash
   # The deployment creates sample Android application code
   git add .
   git commit -m "Initial mobile CI/CD setup"
   git push origin main
   ```

4. **Monitor First Build**:
   ```bash
   # Check build status
   gcloud builds list --limit=5
   
   # View build logs
   gcloud builds log [BUILD_ID]
   ```

## Validation

### Check Infrastructure Deployment

```bash
# Verify Cloud Build triggers
gcloud builds triggers list

# Check source repository
gcloud source repos list

# Validate Firebase project
firebase projects:list

# Check API enablement
gcloud services list --enabled
```

### Test CI/CD Pipeline

```bash
# View recent builds
gcloud builds list --limit=3

# Check Firebase Test Lab results
gcloud firebase test android list --limit=3

# Verify App Distribution releases
firebase appdistribution:releases:list --app=${ANDROID_APP_ID}
```

## Troubleshooting

### Common Issues

1. **API Not Enabled Error**:
   ```bash
   # Enable required APIs manually
   gcloud services enable cloudbuild.googleapis.com
   gcloud services enable sourcerepo.googleapis.com
   gcloud services enable firebase.googleapis.com
   ```

2. **Permission Denied**:
   ```bash
   # Check current user permissions
   gcloud auth list
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Firebase Project Creation Failed**:
   ```bash
   # Create Firebase project manually
   firebase projects:create ${PROJECT_ID}
   firebase use ${PROJECT_ID}
   ```

4. **Build Trigger Not Firing**:
   ```bash
   # Check trigger configuration
   gcloud builds triggers describe [TRIGGER_ID]
   
   # Manually run trigger
   gcloud builds triggers run [TRIGGER_ID] --branch=main
   ```

### Debugging Commands

```bash
# View detailed build information
gcloud builds describe [BUILD_ID]

# Check Firebase Test Lab quota
gcloud firebase test android models list

# Monitor Cloud Build logs in real-time
gcloud builds log [BUILD_ID] --stream
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/mobile-cicd-pipeline

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var-file="terraform.tfvars"
```

### Using Bash Scripts

```bash
cd scripts/
./destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete build triggers
gcloud builds triggers list --format="value(id)" | xargs -I {} gcloud builds triggers delete {}

# Delete source repository
gcloud source repos delete ${REPO_NAME}

# Delete Firebase project (if created specifically for this recipe)
firebase projects:delete ${PROJECT_ID}

# Delete Google Cloud project (if created specifically for this recipe)
gcloud projects delete ${PROJECT_ID}
```

## Cost Optimization

- **Cloud Build**: Builds are charged per minute. Optimize build times by caching dependencies
- **Firebase Test Lab**: Charged per device-minute. Limit test matrix to essential device configurations
- **Cloud Source Repositories**: Free tier includes 5 users and 50 GB storage
- **Firebase App Distribution**: Free with usage limits on distributions and testers

## Security Considerations

- Service accounts follow least privilege principle
- Firebase App Distribution requires testers to be explicitly added
- Cloud Build uses secure build environments
- Source repository access is controlled through IAM
- Test devices are isolated and temporary

## Customization

### Adding iOS Support

Modify the Terraform configuration to include iOS app registration:

```hcl
resource "google_firebase_apple_app" "ios_app" {
  project      = var.project_id
  display_name = "${var.app_name} iOS"
  bundle_id    = var.ios_bundle_id
}
```

### Custom Test Matrix

Edit the test matrix configuration in `test-matrix.yml`:

```yaml
androidDeviceList:
  androidDevices:
  - androidModelId: Pixel5
    androidVersionId: "31"
    locale: en
    orientation: portrait
```

### Additional Tester Groups

Add more tester groups in the Terraform configuration:

```hcl
resource "google_firebase_app_distribution_group" "beta_users" {
  project      = var.project_id
  group_id     = "beta-users"
  display_name = "Beta Users"
}
```

## Integration with CI/CD

This infrastructure can be extended to integrate with external CI/CD systems:

1. **GitHub Actions**: Use workload identity federation for authentication
2. **GitLab CI**: Configure service account keys for Cloud Build integration
3. **Jenkins**: Set up Cloud Build plugin for automated deployments

## Monitoring and Alerting

Set up monitoring for the mobile CI/CD pipeline:

```bash
# Create alerting policy for build failures
gcloud alpha monitoring policies create --policy-from-file=alerting-policy.yaml

# Set up notification channels
gcloud alpha monitoring channels create --channel-content-from-file=notification-channel.yaml
```

## Support

- For Google Cloud Build issues: [Cloud Build Documentation](https://cloud.google.com/build/docs)
- For Firebase App Distribution: [Firebase App Distribution Documentation](https://firebase.google.com/docs/app-distribution)
- For Firebase Test Lab: [Test Lab Documentation](https://firebase.google.com/docs/test-lab)
- For Infrastructure Manager: [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- For Terraform Google Cloud Provider: [Terraform GCP Documentation](https://registry.terraform.io/providers/hashicorp/google/latest)

## Contributing

When making changes to the infrastructure:

1. Test changes in a development environment first
2. Update variable descriptions and README documentation
3. Validate Terraform plans before applying
4. Test the complete CI/CD workflow after changes
5. Update cost estimates if resource usage changes