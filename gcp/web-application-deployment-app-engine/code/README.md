# Infrastructure as Code for Web Application Deployment with App Engine

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Web Application Deployment with App Engine".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (or use Cloud Shell)
- Google Cloud project with billing enabled
- App Engine API and Cloud Build API access
- Python 3.9+ for local development and testing
- Appropriate IAM permissions:
  - App Engine Admin
  - Cloud Build Editor
  - Project Editor (or custom role with required permissions)

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native infrastructure as code service that uses Terraform configurations with additional Google Cloud integrations.

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Create a deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/webapp-deployment \
    --service-account=SERVICE_ACCOUNT_EMAIL \
    --gcs-source=gs://BUCKET_NAME/main.yaml \
    --input-values=project_id=PROJECT_ID,region=REGION

# Monitor deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/webapp-deployment
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide a step-by-step deployment approach similar to the original recipe:

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the application
./scripts/deploy.sh

# The script will prompt for required variables:
# - PROJECT_ID (or set PROJECT_ID environment variable)
# - REGION (defaults to us-central1)
```

## Configuration Variables

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | App Engine region | `us-central1` | No |
| `service_name` | App Engine service name | `default` | No |
| `runtime` | Python runtime version | `python312` | No |
| `max_instances` | Maximum auto-scaling instances | `10` | No |
| `target_cpu_utilization` | CPU utilization target for scaling | `0.6` | No |

### Terraform Variables

The same variables apply to Terraform. Set them via:

```bash
# Using command line
terraform apply -var="project_id=my-project" -var="region=us-west1"

# Using terraform.tfvars file
echo 'project_id = "my-project"' > terraform.tfvars
echo 'region = "us-west1"' >> terraform.tfvars
terraform apply
```

### Bash Script Variables

Set environment variables before running the script:

```bash
export PROJECT_ID="my-webapp-project"
export REGION="us-central1"
export SERVICE_NAME="default"
./scripts/deploy.sh
```

## Application Code

All implementations deploy a sample Flask web application with the following features:

- **Home Route** (`/`): Main application page with dynamic content
- **Health Check** (`/health`): JSON endpoint for monitoring
- **Static Assets**: CSS and JavaScript files
- **Automatic Scaling**: Scales from 0 to configurable maximum instances
- **SSL/HTTPS**: Automatically provisioned and managed
- **Monitoring**: Integrated with Google Cloud Operations

### Application Structure

```
webapp/
├── main.py              # Flask application entry point
├── app.yaml            # App Engine configuration
├── requirements.txt    # Python dependencies
├── templates/
│   └── index.html     # HTML template
└── static/
    ├── style.css      # Stylesheet
    └── script.js      # JavaScript functionality
```

## Deployment Process

### Infrastructure Manager Process

1. **API Enablement**: Enables App Engine and Cloud Build APIs
2. **App Engine Initialization**: Creates App Engine application in specified region
3. **Source Code Setup**: Deploys application code with proper configuration
4. **Service Configuration**: Sets up automatic scaling and traffic routing
5. **Monitoring Setup**: Configures logging and monitoring integration

### Terraform Process

1. **Provider Configuration**: Sets up Google Cloud provider with required APIs
2. **Project Services**: Enables necessary Google Cloud APIs
3. **App Engine Application**: Initializes App Engine in the specified region
4. **Application Deployment**: Deploys the Flask application with proper configuration
5. **Output Generation**: Provides application URL and monitoring links

### Bash Script Process

The bash script follows the original recipe steps:

1. **Environment Setup**: Configures project and enables APIs
2. **App Engine Initialization**: Creates App Engine application
3. **Application Creation**: Generates Flask application code and configuration
4. **Local Testing**: Optionally tests application locally
5. **Cloud Deployment**: Deploys to App Engine with monitoring setup

## Monitoring and Observability

All deployments include comprehensive monitoring capabilities:

### Built-in Monitoring

- **Request Metrics**: Latency, throughput, and error rates
- **Instance Metrics**: CPU utilization, memory usage, and scaling events
- **Application Logs**: Structured logging with Cloud Logging integration
- **Health Checks**: Automatic health monitoring and alerting

### Accessing Monitoring Data

```bash
# View application logs
gcloud logs read "resource.type=gae_app" --limit=50

# Check application status
gcloud app versions list

# View instances
gcloud app instances list

# Access Cloud Console monitoring
echo "https://console.cloud.google.com/appengine?project=${PROJECT_ID}"
```

## Security Considerations

### Default Security Features

- **Automatic HTTPS**: SSL certificates automatically provisioned and managed
- **IAM Integration**: Service account with minimal required permissions
- **Network Security**: Automatic DDoS protection and request filtering
- **Dependency Management**: Secure dependency installation and updates

### Additional Security Hardening

For production deployments, consider:

1. **Custom Service Account**: Create dedicated service account with minimal permissions
2. **VPC Integration**: Configure VPC connector for private resource access
3. **Identity and Access Management**: Implement proper authentication and authorization
4. **Security Headers**: Add security headers in application code
5. **Dependency Scanning**: Regular security scanning of Python dependencies

## Cost Optimization

### Free Tier Benefits

App Engine provides generous free quotas:
- 28 instance hours per day
- 1 GB outbound data transfer per day
- 5 GB cloud storage

### Cost Management

```bash
# Monitor current usage
gcloud app instances list --format="table(service,version,id,vmStatus,qps,cpu,memory)"

# Set spending limits (configure in Cloud Console)
echo "Configure budget alerts: https://console.cloud.google.com/billing/budgets"

# Optimize scaling settings
# Adjust max_instances and target_cpu_utilization in configuration
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/webapp-deployment

# Verify cleanup
gcloud infra-manager deployments list
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup

```bash
# Stop all versions
gcloud app versions stop $(gcloud app versions list --service=default --format="value(id)")

# Delete non-serving versions
gcloud app versions delete $(gcloud app versions list --service=default --format="value(id)" | tail -n +2)

# Note: App Engine applications cannot be deleted, only disabled
# To completely remove the project:
# gcloud projects delete PROJECT_ID
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   gcloud services enable appengine.googleapis.com cloudbuild.googleapis.com
   ```

2. **App Engine Already Exists**
   - App Engine can only be created once per project
   - Use existing App Engine application or create new project

3. **Insufficient Permissions**
   ```bash
   # Verify current permissions
   gcloud auth list
   gcloud projects get-iam-policy PROJECT_ID
   ```

4. **Deployment Timeout**
   ```bash
   # Check build logs
   gcloud builds list --limit=5
   gcloud builds log BUILD_ID
   ```

5. **Application Not Responding**
   ```bash
   # Check application logs
   gcloud logs read "resource.type=gae_app" --limit=20
   
   # Verify app configuration
   gcloud app describe
   ```

### Debug Commands

```bash
# View detailed deployment status
gcloud app operations list

# Check service configuration
gcloud app services describe default

# Monitor real-time logs
gcloud logs tail "resource.type=gae_app"

# Test application health
curl -s "https://PROJECT_ID.appspot.com/health"
```

## Customization

### Application Customization

1. **Modify Application Code**: Update `main.py`, templates, and static files
2. **Update Dependencies**: Modify `requirements.txt` for additional Python packages
3. **Configure Scaling**: Adjust `automatic_scaling` settings in `app.yaml`
4. **Add Environment Variables**: Include custom environment variables in configuration

### Infrastructure Customization

1. **Multiple Services**: Deploy multiple App Engine services for microservices architecture
2. **Custom Domains**: Configure custom domain names with SSL certificates
3. **Database Integration**: Add Cloud SQL, Firestore, or other databases
4. **CDN Integration**: Configure Cloud CDN for static asset optimization
5. **Authentication**: Integrate Identity and Access Management or Firebase Authentication

### Example Customizations

```yaml
# Enhanced app.yaml configuration
runtime: python312

automatic_scaling:
  min_instances: 1
  max_instances: 20
  target_cpu_utilization: 0.5
  target_throughput_utilization: 0.7

vpc_access_connector:
  name: "projects/PROJECT_ID/locations/REGION/connectors/CONNECTOR_NAME"

env_variables:
  DATABASE_URL: "postgresql://..."
  REDIS_URL: "redis://..."
  FLASK_ENV: "production"
```

## Performance Optimization

### Application Performance

1. **Static Asset Optimization**: Use Cloud CDN for static file delivery
2. **Database Connection Pooling**: Implement connection pooling for database access
3. **Caching Strategy**: Use Redis or Memorystore for application caching
4. **Async Processing**: Implement Cloud Tasks for background job processing

### Scaling Configuration

```yaml
# Optimized scaling configuration
automatic_scaling:
  min_instances: 0          # Cost optimization
  max_instances: 50         # Handle traffic spikes
  target_cpu_utilization: 0.6
  target_throughput_utilization: 0.8
  max_concurrent_requests: 10
  max_idle_instances: 2
  min_pending_latency: 30ms
  max_pending_latency: 100ms
```

## Advanced Features

### Blue-Green Deployments

```bash
# Deploy new version without serving traffic
gcloud app deploy --no-promote --version=v2

# Test new version
curl "https://v2-dot-default-dot-PROJECT_ID.appspot.com/"

# Migrate traffic gradually
gcloud app services set-traffic default --splits=v1=50,v2=50
gcloud app services set-traffic default --splits=v2=100
```

### A/B Testing

```bash
# Split traffic between versions
gcloud app services set-traffic default --splits=v1=80,v2=20 --split-by=random
```

### Integration with CI/CD

```yaml
# Example Cloud Build configuration
steps:
- name: 'gcr.io/cloud-builders/gcloud'
  args: ['app', 'deploy']
```

## Support and Documentation

### Official Documentation

- [App Engine Documentation](https://cloud.google.com/appengine/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Community Resources

- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow - google-app-engine](https://stackoverflow.com/questions/tagged/google-app-engine)
- [Google Cloud Architecture Center](https://cloud.google.com/architecture)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation
4. Seek help in community forums

For production support, consider Google Cloud Support plans for enterprise-grade assistance and SLA guarantees.