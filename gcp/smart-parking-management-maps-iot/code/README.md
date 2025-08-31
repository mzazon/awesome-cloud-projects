# Infrastructure as Code for Smart Parking Management with Maps Platform and IoT Core

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Parking Management with Maps Platform and MQTT Brokers".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Pub/Sub (topics and subscriptions)
  - Cloud Functions (deployment and management)
  - Firestore (database creation and management)
  - Maps Platform (API key management)
  - IAM (service account creation and policy binding)
- For Terraform: Terraform >= 1.0 installed
- For Infrastructure Manager: gcloud CLI with Infrastructure Manager API enabled
- MQTT broker service (EMQX Cloud, HiveMQ, or self-hosted) for production IoT device connectivity

> **Note**: Google Cloud IoT Core was retired in August 2023. This solution uses third-party MQTT brokers integrated with Google Cloud Pub/Sub as the recommended alternative architecture.

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Deploy infrastructure
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/smart-parking \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --local-source="."
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts for project configuration
```

## Architecture Overview

This infrastructure deploys:

- **Pub/Sub Topic**: Message ingestion from MQTT brokers
- **Cloud Functions**: 
  - Real-time parking data processing
  - REST API for parking management
- **Firestore Database**: NoSQL storage for parking spaces and zone data
- **Maps Platform API Key**: Location services and mapping
- **IAM Service Account**: Secure MQTT broker integration

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Deployment region"
    type: string
    default: "us-central1"
  parking_topic_name:
    description: "Pub/Sub topic name for parking events"
    type: string
    default: "parking-events"
```

### Terraform Variables

Edit `terraform/terraform.tfvars` or provide variables during apply:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
parking_topic_name      = "parking-events"
function_memory         = "256MB"
function_timeout        = "60s"
firestore_location_id   = "us-central1"
```

### Bash Script Configuration

The deployment script will prompt for:
- Project ID (or auto-generate if creating new project)
- Deployment region
- Resource naming preferences

## Post-Deployment Setup

After infrastructure deployment, complete the setup:

1. **Configure MQTT Broker Integration**:
   ```bash
   # Download service account key for MQTT broker
   gcloud iam service-accounts keys create mqtt-sa-key.json \
       --iam-account=mqtt-pubsub-publisher@PROJECT_ID.iam.gserviceaccount.com
   
   # Configure your MQTT broker to publish to the Pub/Sub topic
   # Topic name: parking-events-SUFFIX
   ```

2. **Test the API Endpoints**:
   ```bash
   # Get API endpoint URL
   API_ENDPOINT=$(gcloud functions describe parking-management-api \
       --region=REGION --gen2 --format="value(serviceConfig.uri)")
   
   # Test parking search
   curl "${API_ENDPOINT}/parking/search?lat=37.7749&lng=-122.4194&radius=1000"
   
   # Test zone statistics
   curl "${API_ENDPOINT}/parking/zones/downtown/stats"
   ```

3. **Initialize Sample Parking Data**:
   ```bash
   # Publish test sensor data
   gcloud pubsub topics publish parking-events-SUFFIX \
       --message='{"space_id":"A001","sensor_id":"parking-sensor-01","occupied":false,"confidence":0.98,"zone":"downtown","location":{"lat":37.7749,"lng":-122.4194},"timestamp":"2025-07-23T10:30:00Z"}'
   ```

## Monitoring and Validation

### Verify Deployment

```bash
# Check Pub/Sub topic
gcloud pubsub topics list --filter="name:parking-events"

# Check Cloud Functions
gcloud functions list --filter="name:parking" --regions=REGION

# Check Firestore database
gcloud firestore databases list

# Check Maps API key
gcloud services api-keys list --filter="displayName:'Smart Parking Maps API'"
```

### View Logs

```bash
# Cloud Function processing logs
gcloud functions logs read process-parking-data-SUFFIX \
    --region=REGION --gen2 --limit=10

# API function logs
gcloud functions logs read parking-management-api \
    --region=REGION --gen2 --limit=10
```

### Monitor Performance

```bash
# Pub/Sub topic metrics
gcloud monitoring metrics list \
    --filter="metric.type:pubsub.googleapis.com/topic/send_message_operation_count"

# Function invocation metrics
gcloud monitoring metrics list \
    --filter="metric.type:cloudfunctions.googleapis.com/function/executions"
```

## Cleanup

### Using Infrastructure Manager

```bash
cd infrastructure-manager/
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/smart-parking
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete specific resources
gcloud functions delete process-parking-data-SUFFIX --region=REGION --gen2 --quiet
gcloud functions delete parking-management-api --region=REGION --gen2 --quiet
gcloud pubsub topics delete parking-events-SUFFIX --quiet
gcloud iam service-accounts delete mqtt-pubsub-publisher@PROJECT_ID.iam.gserviceaccount.com --quiet

# For complete cleanup, delete the entire project
gcloud projects delete PROJECT_ID --quiet
```

## Cost Estimation

Estimated monthly costs for development/testing (assumes light usage):

- **Pub/Sub**: $0.40 per million messages + $0.05 per GB
- **Cloud Functions**: $0.0000025 per 100ms execution + $0.0000025 per GB-second
- **Firestore**: $0.18 per 100K reads + $0.18 per 100K writes + $1.08 per GB storage
- **Maps Platform**: $7 per 1,000 requests (with $200 monthly credit)

**Total estimated cost**: $5-15 per month for development workloads

## Security Considerations

- Service accounts use least-privilege IAM policies
- Maps API key is restricted to specific APIs
- MQTT broker integration uses service account authentication
- Cloud Functions enforce CORS for web application security
- Firestore uses security rules for data access control

## Troubleshooting

### Common Issues

1. **MQTT Broker Connection**:
   - Verify service account key is correctly configured in MQTT broker
   - Check IAM permissions for pubsub.publisher role
   - Validate Pub/Sub topic name in MQTT broker configuration

2. **Cloud Function Errors**:
   - Check function logs for detailed error messages
   - Verify Firestore database is initialized
   - Ensure proper IAM permissions for Firestore access

3. **API Endpoint Issues**:
   - Verify Cloud Function deployment status
   - Check CORS configuration for web application access
   - Validate request format and required parameters

### Debug Commands

```bash
# Test Pub/Sub message publishing
gcloud pubsub topics publish TOPIC_NAME --message="test message"

# Check service account permissions
gcloud projects get-iam-policy PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:mqtt-pubsub-publisher@PROJECT_ID.iam.gserviceaccount.com"

# Validate API key restrictions
gcloud services api-keys describe API_KEY_NAME --format="yaml"
```

## Customization

### Adding New Parking Zones

Modify Firestore collections to add new zones:

```bash
# Example: Add new zone configuration
gcloud firestore documents create \
    --collection-id=parking_zones \
    --document-id=midtown \
    --data='{"available":0,"total":50,"spaces":{},"zone_name":"Midtown District"}'
```

### Scaling Considerations

For production deployments:

- Increase Cloud Function memory allocation (512MB or 1GB)
- Implement Cloud Function concurrency controls
- Use Firestore composite indexes for complex queries
- Deploy MQTT brokers in multiple regions for redundancy
- Implement API rate limiting and authentication

## Integration Examples

### Mobile Application Integration

```javascript
// Example: Fetch available parking spaces
const response = await fetch(`${API_ENDPOINT}/parking/search?lat=${lat}&lng=${lng}&radius=500`);
const parkingData = await response.json();
console.log(`Found ${parkingData.total} available spaces`);
```

### Web Dashboard Integration

```javascript
// Example: Real-time zone statistics
const zoneStats = await fetch(`${API_ENDPOINT}/parking/zones/downtown/stats`);
const stats = await zoneStats.json();
document.getElementById('occupancy-rate').textContent = `${stats.occupancy_rate}%`;
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../smart-parking-management-maps-iot.md)
2. Review [Google Cloud Documentation](https://cloud.google.com/docs)
3. Consult [MQTT broker integration guides](https://cloud.google.com/pubsub/docs/mqtt)
4. Reference [Firestore real-time updates documentation](https://cloud.google.com/firestore/docs/listen)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update variable descriptions and defaults
3. Validate security configurations
4. Update this README with any new requirements or procedures
5. Ensure compatibility with the original recipe architecture