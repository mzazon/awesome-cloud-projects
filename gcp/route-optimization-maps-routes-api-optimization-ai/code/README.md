# Infrastructure as Code for Route Optimization with Google Maps Routes API and Cloud Optimization AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Route Optimization with Google Maps Routes API and Cloud Optimization AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an intelligent logistics platform that combines:

- **Google Maps Routes API**: Real-time traffic-aware routing
- **Cloud Run**: Serverless route optimization service
- **Cloud SQL**: PostgreSQL database for route analytics
- **Pub/Sub**: Event-driven optimization triggers
- **Cloud Functions**: Asynchronous event processing
- **Cloud Monitoring**: Performance tracking and alerting

## Prerequisites

### General Requirements

- Google Cloud Platform account with billing enabled
- Google Cloud CLI (`gcloud`) installed and configured
- Appropriate IAM permissions for:
  - Compute Engine Admin
  - Cloud Run Admin
  - Cloud SQL Admin
  - Pub/Sub Admin
  - Service Account Admin
  - Project IAM Admin
- Google Maps Platform API key with Routes API enabled
- Estimated cost: $50-100/month for development workloads

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Google Cloud CLI with Infrastructure Manager API enabled
- `gcloud components install infrastructure-manager`

#### Terraform
- Terraform >= 1.0 installed
- Google Cloud provider >= 4.0

#### Bash Scripts
- Bash shell environment
- `curl` and `jq` utilities for testing
- Docker (for local container builds)

## Environment Setup

Before deploying with any method, set up your environment:

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Authenticate with Google Cloud
gcloud auth login
gcloud config set project ${PROJECT_ID}

# Enable required APIs
gcloud services enable run.googleapis.com \
    sql-component.googleapis.com \
    sqladmin.googleapis.com \
    pubsub.googleapis.com \
    cloudbuild.googleapis.com \
    cloudfunctions.googleapis.com \
    monitoring.googleapis.com

# Set your Google Maps API key
export MAPS_API_KEY="your-maps-api-key"
```

## Quick Start

### Using Infrastructure Manager

```bash
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/route-optimization \
    --service-account projects/${PROJECT_ID}/serviceAccounts/infrastructure-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars" \
    --labels="environment=dev,recipe=route-optimization"

# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/route-optimization
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=${PROJECT_ID}" \
               -var="region=${REGION}" \
               -var="maps_api_key=${MAPS_API_KEY}"

# Apply infrastructure
terraform apply -var="project_id=${PROJECT_ID}" \
                -var="region=${REGION}" \
                -var="maps_api_key=${MAPS_API_KEY}"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy infrastructure
./deploy.sh

# The script will prompt for required environment variables if not set
```

## Configuration Options

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `maps_api_key` | Google Maps API key | - | Yes |
| `sql_instance_tier` | Cloud SQL instance tier | `db-f1-micro` | No |
| `sql_storage_size` | SQL storage size in GB | `20` | No |
| `cloud_run_memory` | Cloud Run memory allocation | `1Gi` | No |
| `cloud_run_cpu` | Cloud Run CPU allocation | `1` | No |
| `environment` | Environment tag | `dev` | No |

### Customization Examples

#### Production Configuration

For production deployments, update variables:

```bash
# Terraform
terraform apply \
    -var="sql_instance_tier=db-n1-standard-2" \
    -var="sql_storage_size=100" \
    -var="cloud_run_memory=2Gi" \
    -var="cloud_run_cpu=2" \
    -var="environment=prod"
```

#### Multi-Region Setup

Deploy to different regions by changing the region variable:

```bash
terraform apply -var="region=europe-west1"
```

## Testing the Deployment

After successful deployment, test the route optimization service:

```bash
# Get the Cloud Run service URL
export SERVICE_URL=$(gcloud run services describe route-optimizer \
    --region=${REGION} \
    --format='value(status.url)')

# Test health endpoint
curl -X GET "${SERVICE_URL}/health"

# Test route optimization
curl -X POST "${SERVICE_URL}/optimize-route" \
     -H "Content-Type: application/json" \
     -d '{
       "origin": {"lat": 37.7749, "lng": -122.4194},
       "destination": {"lat": 37.7849, "lng": -122.4094},
       "waypoints": [{"lat": 37.7799, "lng": -122.4144}]
     }'

# Check analytics
curl -X GET "${SERVICE_URL}/analytics"
```

## Monitoring and Observability

The deployment includes comprehensive monitoring:

### Cloud Monitoring Dashboards

- **Route Optimization Performance**: API response times, success rates
- **Database Health**: Connection pools, query performance
- **Pub/Sub Metrics**: Message processing rates, dead letter queues

### Logging

View application logs:

```bash
# Cloud Run logs
gcloud logs read "resource.type=cloud_run_revision" --limit=50

# Cloud Function logs
gcloud logs read "resource.type=cloud_function" --limit=50

# Cloud SQL logs
gcloud logs read "resource.type=cloudsql_database" --limit=50
```

### Alerting

Pre-configured alerts for:
- High error rates (>5% for 5 minutes)
- Database connection failures
- Pub/Sub message processing delays
- High API latency (>2 seconds)

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/route-optimization
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" \
                  -var="region=${REGION}" \
                  -var="maps_api_key=${MAPS_API_KEY}"
```

### Using Bash Scripts

```bash
cd scripts/
./destroy.sh
```

### Manual Cleanup Verification

Verify all resources are deleted:

```bash
# Check Cloud Run services
gcloud run services list --region=${REGION}

# Check Cloud SQL instances
gcloud sql instances list

# Check Pub/Sub topics
gcloud pubsub topics list

# Check Cloud Functions
gcloud functions list --region=${REGION}
```

## Cost Optimization

### Development Environment

For cost-effective development:

- Use `db-f1-micro` SQL instances
- Set Cloud Run minimum instances to 0
- Enable request-based billing
- Use shared-core machine types

### Production Environment

For production optimization:

- Use committed use discounts for predictable workloads
- Implement connection pooling for Cloud SQL
- Configure Cloud Run concurrency settings
- Monitor and optimize Maps API usage

### Cost Monitoring

```bash
# Check current costs
gcloud billing budgets list --billing-account=YOUR_BILLING_ACCOUNT

# Set up budget alerts
gcloud billing budgets create \
    --billing-account=YOUR_BILLING_ACCOUNT \
    --display-name="Route Optimization Budget" \
    --budget-amount=100USD
```

## Security Best Practices

The infrastructure implements security best practices:

### Identity and Access Management (IAM)

- Least privilege service accounts
- Fine-grained resource permissions
- Workload Identity for secure authentication

### Network Security

- Private Google Access for internal communications
- VPC firewall rules for controlled access
- Cloud Armor protection for external endpoints

### Data Protection

- Encryption at rest for Cloud SQL
- Encryption in transit for all communications
- Secret Manager for API key management

### Security Monitoring

```bash
# Enable Security Command Center
gcloud scc notifications create route-optimization-security \
    --organization=YOUR_ORG_ID \
    --pubsub-topic=projects/${PROJECT_ID}/topics/security-notifications
```

## Troubleshooting

### Common Issues

#### Cloud SQL Connection Failures

```bash
# Check Cloud SQL instance status
gcloud sql instances describe INSTANCE_NAME

# Test connectivity
gcloud sql connect INSTANCE_NAME --user=postgres
```

#### Cloud Run Deployment Failures

```bash
# Check Cloud Run logs
gcloud logs read "resource.type=cloud_run_revision" \
    --filter="severity>=ERROR" --limit=50

# Check container build logs
gcloud builds list --limit=10
```

#### Pub/Sub Message Processing Delays

```bash
# Check subscription metrics
gcloud pubsub subscriptions describe SUBSCRIPTION_NAME

# Check dead letter queue
gcloud pubsub topics list-subscriptions TOPIC_NAME
```

### Performance Optimization

#### Database Performance

```bash
# Monitor SQL performance
gcloud sql operations list --instance=INSTANCE_NAME --limit=10

# Check connection pools
gcloud sql instances describe INSTANCE_NAME \
    --format="value(settings.ipConfiguration.requireSsl)"
```

#### API Response Times

```bash
# Monitor Cloud Run metrics
gcloud monitoring metrics list \
    --filter="metric.type:run.googleapis.com/request_latencies"
```

## Integration Examples

### External Fleet Management Systems

```bash
# Webhook integration endpoint
curl -X POST "${SERVICE_URL}/webhook/fleet-update" \
     -H "Content-Type: application/json" \
     -d '{"vehicle_id": "truck_001", "location": {"lat": 37.7749, "lng": -122.4194}}'
```

### Real-Time Dashboard Integration

```javascript
// WebSocket connection for real-time updates
const ws = new WebSocket('wss://your-websocket-endpoint');
ws.onmessage = function(event) {
    const routeUpdate = JSON.parse(event.data);
    updateDashboard(routeUpdate);
};
```

## Development

### Local Development Setup

```bash
# Clone the repository
git clone your-repo-url
cd route-optimization

# Set up local environment
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Set environment variables
export PROJECT_ID=your-dev-project
export MAPS_API_KEY=your-api-key

# Run locally
python src/main.py
```

### Testing

```bash
# Run unit tests
python -m pytest tests/

# Run integration tests
python -m pytest tests/integration/

# Load testing
artillery run load-test-config.yml
```

## Support and Documentation

### Additional Resources

- [Google Maps Routes API Documentation](https://developers.google.com/maps/documentation/routes)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Cloud SQL Best Practices](https://cloud.google.com/sql/docs/postgres/best-practices)
- [Pub/Sub Architecture Patterns](https://cloud.google.com/pubsub/docs/publisher)

### Community Support

- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow - Google Cloud Platform](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [Google Cloud Slack Community](https://googlecloud-community.slack.com)

### Professional Support

For production deployments, consider:
- Google Cloud Professional Services
- Google Cloud Support Plans
- Certified Google Cloud Partners

---

**Note**: This infrastructure code implements the complete route optimization solution described in the recipe. For detailed implementation guidance, refer to the original recipe documentation.