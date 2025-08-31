# Infrastructure as Code for Real-time Video Collaboration with WebRTC and Cloud Run

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-time Video Collaboration with WebRTC and Cloud Run".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a complete video collaboration platform with:
- **Cloud Run**: Serverless WebRTC signaling server with automatic scaling
- **Firestore**: Real-time database for room management and participant synchronization
- **Identity-Aware Proxy (IAP)**: Zero-trust authentication and access control
- **Container Registry**: Secure storage for the WebRTC signaling application container

## Prerequisites

- Google Cloud account with billing enabled
- Google Cloud CLI (gcloud) installed and configured
- Project Editor or Owner permissions
- Docker installed for local container development (for manual deployment)
- Terraform installed (version ≥ 1.0) - for Terraform implementation
- Basic knowledge of WebRTC concepts and video streaming

### Required APIs

The following Google Cloud APIs will be automatically enabled:
- Cloud Run API
- Firestore API
- Identity-Aware Proxy API
- Cloud Build API
- Container Registry API

### Estimated Costs

- **Development/Testing**: $5-15 per month
- **Production**: $20-100+ per month depending on usage
- **Key Cost Factors**: Cloud Run CPU/memory usage, Firestore operations, IAP requests

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended IaC solution for native GCP deployments.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export USER_EMAIL="your-email@domain.com"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/video-collaboration \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="inputs.yaml"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/video-collaboration
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive provider ecosystem support.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Set variables (create terraform.tfvars file)
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region = "us-central1"
user_email = "your-email@domain.com"
service_name = "webrtc-signaling"
firestore_database = "video-rooms"
EOF

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide imperative deployment with maximum flexibility and debugging capability.

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export USER_EMAIL="your-email@domain.com"

# Deploy infrastructure
./deploy.sh

# Monitor deployment
gcloud run services list
gcloud firestore databases list
```

## Configuration Options

### Infrastructure Manager Variables

Edit `inputs.yaml` to customize your deployment:

```yaml
project_id: "your-project-id"
region: "us-central1"
user_email: "your-email@domain.com"
service_name: "webrtc-signaling"
firestore_database: "video-rooms"
min_instances: 0
max_instances: 10
memory: "512Mi"
cpu: "1"
```

### Terraform Variables

Key variables in `variables.tf`:

- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `user_email`: Email for IAP access control
- `service_name`: Cloud Run service name
- `firestore_database`: Firestore database name
- `container_memory`: Memory allocation for containers
- `container_cpu`: CPU allocation for containers
- `min_instances`: Minimum Cloud Run instances
- `max_instances`: Maximum Cloud Run instances

### Bash Script Environment Variables

Set these variables before running deployment scripts:

```bash
export PROJECT_ID="your-project-id"          # Required: GCP project ID
export REGION="us-central1"                  # Optional: deployment region
export USER_EMAIL="your-email@domain.com"    # Required: user for IAP access
export SERVICE_NAME="webrtc-signaling"       # Optional: Cloud Run service name
export FIRESTORE_DATABASE="video-rooms"      # Optional: Firestore database name
```

## Post-Deployment Configuration

### 1. OAuth Consent Screen Setup

After infrastructure deployment, configure OAuth for IAP:

```bash
# Open OAuth consent screen configuration
echo "Configure OAuth consent screen at:"
echo "https://console.cloud.google.com/apis/credentials/consent?project=${PROJECT_ID}"

# Required settings:
# - Application name: Video Collaboration Platform
# - User support email: your-email@domain.com
# - Application home page: https://your-domain.com
# - Application privacy policy: https://your-domain.com/privacy
# - Authorized domains: your-domain.com
```

### 2. OAuth 2.0 Client Creation

Create OAuth client credentials for IAP:

```bash
# Create OAuth 2.0 client
echo "Create OAuth 2.0 client at:"
echo "https://console.cloud.google.com/apis/credentials?project=${PROJECT_ID}"

# Settings:
# - Application type: Web application
# - Name: Video Collaboration IAP Client
# - Authorized redirect URIs: https://iap.googleapis.com/v1/oauth/clientIds/CLIENT_ID:handleRedirect
```

### 3. Enable Identity-Aware Proxy

Configure IAP for the Cloud Run service:

```bash
# Enable IAP
echo "Enable IAP at:"
echo "https://console.cloud.google.com/security/iap?project=${PROJECT_ID}"

# Steps:
# 1. Select Cloud Run service
# 2. Toggle IAP to "On"
# 3. Select OAuth client created above
# 4. Add authorized users/groups
```

### 4. Application Testing

Test the deployed video collaboration platform:

```bash
# Get Cloud Run service URL
SERVICE_URL=$(gcloud run services describe webrtc-signaling \
    --region=${REGION} \
    --format='value(status.url)')

echo "Video Collaboration Platform URL: ${SERVICE_URL}"

# Test health endpoint
curl -f "${SERVICE_URL}/health"

# Open in browser (after IAP configuration)
echo "Open in browser: ${SERVICE_URL}"
```

## Validation & Testing

### Infrastructure Validation

```bash
# Verify Cloud Run deployment
gcloud run services describe webrtc-signaling \
    --region=${REGION} \
    --format="table(metadata.name,status.url,spec.template.spec.containers[0].image)"

# Check Firestore database
gcloud firestore databases list --format="table(name,type,locationId)"

# Validate API enablement
gcloud services list --enabled --filter="name:run.googleapis.com OR name:firestore.googleapis.com OR name:iap.googleapis.com"
```

### Application Testing

```bash
# Test WebRTC signaling server
curl -I "${SERVICE_URL}/socket.io/?EIO=4&transport=polling"

# Verify static file serving
curl -I "${SERVICE_URL}/"

# Test Firestore connectivity
gcloud firestore documents create-auto-id \
    --collection=test-rooms \
    --data='{"test": "connection", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
    --database=video-rooms
```

### Multi-User Video Testing

1. Open multiple browser windows to the service URL
2. Join the same room ID (e.g., "test-room-123")
3. Verify local video streams appear
4. Confirm remote participant videos display
5. Test audio/video control functionality
6. Validate real-time synchronization

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/video-collaboration

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Manual verification
gcloud run services list
gcloud firestore databases list
```

### Complete Project Cleanup

For complete resource removal:

```bash
# Disable APIs (optional)
gcloud services disable run.googleapis.com
gcloud services disable firestore.googleapis.com
gcloud services disable iap.googleapis.com

# Delete project (if created specifically for this recipe)
gcloud projects delete ${PROJECT_ID}
```

## Troubleshooting

### Common Issues

**IAP Configuration Issues**:
```bash
# Check IAP status
gcloud iap web get-iam-policy --resource-type=cloud-run --service=webrtc-signaling --region=${REGION}

# Verify OAuth client configuration
gcloud auth print-access-token | curl -H "Authorization: Bearer $(cat)" \
    https://www.googleapis.com/oauth2/v1/tokeninfo
```

**Cloud Run Deployment Failures**:
```bash
# Check build logs
gcloud builds list --limit=5

# View service logs
gcloud logs read "resource.type=cloud_run_revision AND resource.labels.service_name=webrtc-signaling" --limit=50
```

**Firestore Connection Issues**:
```bash
# Verify database exists
gcloud firestore databases describe video-rooms

# Check IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" --filter="bindings.role:roles/datastore.user"
```

### Performance Optimization

**Cloud Run Scaling**:
```bash
# Monitor concurrent requests
gcloud monitoring metrics list --filter="metric.type:run.googleapis.com/container/request_count"

# Adjust scaling parameters
gcloud run services update webrtc-signaling \
    --region=${REGION} \
    --min-instances=1 \
    --max-instances=20 \
    --concurrency=100
```

**Firestore Performance**:
```bash
# Monitor Firestore usage
gcloud logging read "resource.type=firestore_database" --limit=20

# Check index performance
gcloud firestore indexes list --database=video-rooms
```

## Security Considerations

### Network Security

- IAP provides zero-trust access control
- Cloud Run automatically provides HTTPS termination
- Firestore uses encrypted connections by default
- WebRTC uses DTLS for media encryption

### Authentication & Authorization

```bash
# Verify IAP member permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --filter="bindings.role:roles/iap.httpsResourceAccessor"

# Add additional users to IAP
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:additional-user@domain.com" \
    --role="roles/iap.httpsResourceAccessor"
```

### Data Protection

- Firestore data is encrypted at rest
- Cloud Run environment variables are encrypted
- Container images are stored securely in Container Registry
- WebRTC media streams use peer-to-peer encryption

## Extensions and Customizations

### Custom Domain Configuration

```bash
# Map custom domain to Cloud Run
gcloud run domain-mappings create \
    --service=webrtc-signaling \
    --domain=video.yourdomain.com \
    --region=${REGION}
```

### Enhanced Monitoring

```bash
# Create custom dashboards
gcloud monitoring dashboards create --config-from-file=monitoring-dashboard.json

# Set up alerting policies
gcloud alpha monitoring policies create --policy-from-file=alerting-policy.yaml
```

### Load Testing

```bash
# Install artillery for load testing
npm install -g artillery

# Create load test configuration
cat > load-test.yml << EOF
config:
  target: '${SERVICE_URL}'
  phases:
    - duration: 60
      arrivalRate: 10
scenarios:
  - name: "WebRTC Signaling Load Test"
    weight: 100
    engine: socketio
    socketio:
      query:
        roomId: "load-test-room"
EOF

# Run load test
artillery run load-test.yml
```

## Support and Documentation

### Official Documentation

- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Firestore Documentation](https://cloud.google.com/firestore/docs)
- [Identity-Aware Proxy Documentation](https://cloud.google.com/iap/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [WebRTC Specification](https://webrtc.org/getting-started/overview)

### Community Resources

- [Google Cloud Community](https://cloud.google.com/community)
- [WebRTC Community](https://webrtc.org/support/community)
- [Stack Overflow - Google Cloud](https://stackoverflow.com/questions/tagged/google-cloud-platform)

### Getting Help

For issues with this infrastructure code:
1. Review the troubleshooting section above
2. Check the original recipe documentation
3. Consult Google Cloud documentation
4. Reach out to Google Cloud support or community forums

---

**Note**: This infrastructure deploys a complete video collaboration platform. Ensure you understand the security implications and cost structure before deploying to production environments.