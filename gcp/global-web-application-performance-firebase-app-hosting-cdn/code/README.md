# Infrastructure as Code for Accelerating Global Web Application Performance with Firebase App Hosting and Cloud CDN

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Accelerating Global Web Application Performance with Firebase App Hosting and Cloud CDN".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud account with billing enabled
- gcloud CLI v2 installed and configured (or use Google Cloud Shell)
- Node.js 18+ and npm installed for web application development
- GitHub account with repository access for continuous deployment
- Appropriate permissions for Firebase, Cloud CDN, Cloud Monitoring, and Cloud Functions
- Terraform v1.0+ (for Terraform implementation)
- Estimated cost: $10-50/month depending on traffic volume and geographic distribution

### Required Google Cloud APIs

The following APIs must be enabled in your project:
- Firebase API (`firebase.googleapis.com`)
- Firebase Hosting API (`firebasehosting.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)
- Cloud Run API (`run.googleapis.com`)
- Compute Engine API (`compute.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)

### Required IAM Permissions

Your account needs the following roles:
- Firebase Admin
- Cloud CDN Admin
- Compute Load Balancer Admin
- Storage Admin
- Cloud Functions Developer
- Monitoring Editor

## Quick Start

### Using Infrastructure Manager

Google Cloud's Infrastructure Manager is the recommended approach for native Google Cloud deployments with full integration.

```bash
# Set up environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="web-perf-deployment"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create the deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

Terraform provides cross-cloud compatibility and advanced state management features for complex deployments.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide direct control and can be easily customized for specific deployment requirements.

```bash
# Set execute permissions
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export GITHUB_REPO="your-username/web-app-repo"

# Run deployment script
./scripts/deploy.sh

# Verify deployment
./scripts/validate.sh
```

## Configuration Options

### Infrastructure Manager Configuration

The Infrastructure Manager implementation supports the following input values:

- `project_id`: Google Cloud Project ID (required)
- `region`: Deployment region (default: us-central1)
- `github_repo`: GitHub repository for Firebase App Hosting (required)
- `enable_monitoring`: Enable Cloud Monitoring (default: true)
- `cdn_cache_mode`: CDN cache mode (default: CACHE_ALL_STATIC)
- `function_memory`: Cloud Function memory allocation (default: 256MB)

### Terraform Variables

Customize your deployment by setting these variables in `terraform.tfvars`:

```hcl
project_id    = "your-project-id"
region        = "us-central1"
github_repo   = "your-username/web-app-repo"
bucket_name   = "web-assets-unique-suffix"
function_name = "perf-optimizer-unique-suffix"

# Optional configurations
enable_monitoring = true
cdn_cache_mode   = "CACHE_ALL_STATIC"
function_memory  = "256MB"
function_timeout = "60s"

# CDN configuration
default_ttl = 3600
max_ttl     = 86400
cache_key_policy = {
  include_host         = true
  include_protocol     = true
  include_query_string = false
}

# Monitoring configuration
alert_threshold_ms = 1000
notification_channels = []
```

### Environment Variables for Scripts

The bash scripts use these environment variables:

```bash
# Required
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export GITHUB_REPO="your-username/web-app-repo"

# Optional with defaults
export BUCKET_NAME="web-assets-$(openssl rand -hex 3)"
export FUNCTION_NAME="perf-optimizer-$(openssl rand -hex 3)"
export CDN_CACHE_MODE="CACHE_ALL_STATIC"
export FUNCTION_MEMORY="256MB"
```

## Deployment Architecture

The infrastructure creates the following components:

### Core Infrastructure
- **Firebase App Hosting**: Serverless web hosting with Cloud Run backend
- **Cloud CDN**: Global content delivery network with edge caching
- **Cloud Storage**: Bucket for static assets with CDN integration
- **Global Load Balancer**: HTTP(S) load balancer with global IP

### Monitoring and Optimization
- **Cloud Monitoring**: Performance dashboards and alerting
- **Cloud Functions**: Automated performance optimization
- **Alerting Policies**: Proactive performance monitoring

### Integration Components
- **Cloud Build**: CI/CD pipeline for GitHub integration
- **IAM Service Accounts**: Secure service-to-service authentication
- **Firestore**: Database for dynamic content (if needed)

## Validation and Testing

After deployment, verify your infrastructure using these commands:

### Verify Firebase App Hosting
```bash
# Check Firebase project status
firebase projects:list

# Verify App Hosting backend
firebase apphosting:backends:list --project=${PROJECT_ID}

# Test hosting deployment
curl -I https://your-firebase-domain.web.app
```

### Test CDN Performance
```bash
# Get global IP address
GLOBAL_IP=$(gcloud compute addresses describe web-app-ip --global --format="get(address)")

# Test CDN response times
curl -w "Total time: %{time_total}s\n" -o /dev/null -s https://${GLOBAL_IP}

# Check cache headers
curl -I https://${GLOBAL_IP} | grep -i cache
```

### Verify Monitoring
```bash
# Check Cloud Function logs
gcloud functions logs read perf-optimizer --region=${REGION} --limit=10

# List monitoring policies
gcloud alpha monitoring policies list --format="table(displayName,enabled)"

# View monitoring dashboards
echo "Access Cloud Monitoring: https://console.cloud.google.com/monitoring/dashboards"
```

## Cleanup

### Using Infrastructure Manager
```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --delete-policy="DELETE"

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Clean up state files (optional)
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
gcloud compute addresses list --global
gcloud storage buckets list
gcloud functions list --region=${REGION}
```

### Complete Project Cleanup
```bash
# Delete the entire project (use with caution)
gcloud projects delete ${PROJECT_ID}
```

## Troubleshooting

### Common Issues

**Firebase App Hosting Connection Failed**
- Verify GitHub repository permissions and Firebase project configuration
- Ensure Cloud Build API is enabled
- Check service account permissions for Cloud Build

**CDN Cache Not Working**
- Verify backend bucket configuration
- Check Cloud Storage bucket permissions
- Ensure proper cache headers in application

**Cloud Function Deployment Fails**
- Check function memory and timeout settings
- Verify required APIs are enabled
- Review Cloud Function logs for detailed errors

**Load Balancer SSL Certificate Issues**
- Allow time for managed SSL certificate provisioning (15-60 minutes)
- Verify domain ownership and DNS configuration
- Check certificate status in Cloud Console

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="name:firebase OR name:compute OR name:functions"

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Check Cloud Build status
gcloud builds list --limit=10

# Monitor resource creation
gcloud logging read "resource.type=gce_instance OR resource.type=cloud_function" --limit=20
```

### Performance Optimization

**CDN Hit Rate Optimization**
- Adjust cache TTL settings based on content types
- Review cache key policies for optimal caching
- Monitor cache hit rates in Cloud Monitoring

**Firebase App Hosting Performance**
- Optimize application bundle sizes
- Implement proper lazy loading
- Use Next.js optimizations for static generation

**Global Performance Tuning**
- Configure regional backends for dynamic content
- Implement database read replicas in key regions
- Use Cloud CDN's intelligent tiering features

## Support and Documentation

### Official Documentation
- [Firebase App Hosting](https://firebase.google.com/docs/app-hosting)
- [Cloud CDN](https://cloud.google.com/cdn/docs)
- [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Best Practices
- [Web Performance Optimization](https://cloud.google.com/architecture/web-performance-optimization)
- [CDN Best Practices](https://cloud.google.com/cdn/docs/best-practices)
- [Firebase Security Rules](https://firebase.google.com/docs/rules)
- [Cloud Monitoring Best Practices](https://cloud.google.com/monitoring/best-practices)

### Cost Management
- [Cloud CDN Pricing](https://cloud.google.com/cdn/pricing)
- [Firebase Pricing](https://firebase.google.com/pricing)
- [Cost Optimization Guide](https://cloud.google.com/architecture/framework/cost-optimization)

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.

## License

This infrastructure code is provided under the same license as the parent repository.