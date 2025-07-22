# Infrastructure as Code for Location-Based Service Recommendations with Google Maps Platform and Vertex AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Location-Based Service Recommendations with Google Maps Platform and Vertex AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) v2 installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Vertex AI API
  - Cloud Run Admin
  - Cloud Firestore Admin
  - Maps Platform APIs
  - Service Account Admin
  - Project IAM Admin
- Node.js 18+ (for application code)
- Terraform 1.5+ (if using Terraform implementation)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended infrastructure as code solution that uses declarative YAML configuration.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/location-recommender \
    --service-account=SERVICE_ACCOUNT_EMAIL \
    --local-source="."

# Monitor deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/location-recommender
```

### Using Terraform

Terraform provides multi-cloud infrastructure management with extensive provider ecosystem support.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure changes
terraform apply

# Verify deployment
terraform output
```

### Using Bash Scripts

Automated deployment scripts provide a quick way to deploy the complete solution.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# Check deployment status
gcloud run services list --region=us-central1
```

## Architecture Overview

This IaC deploys a serverless location-based recommendation system with the following components:

- **Cloud Run Service**: Hosts the Node.js recommendation API
- **Cloud Firestore**: Stores user preferences and recommendation cache
- **Vertex AI Integration**: Provides AI-powered recommendation capabilities
- **Google Maps Platform APIs**: Enables location services and place data
- **IAM Service Account**: Manages secure access between services
- **API Keys**: Provides secure access to Maps Platform services

## Configuration Variables

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `service_name`: Cloud Run service name
- `firestore_database`: Firestore database name
- `min_instances`: Minimum Cloud Run instances (default: 0)
- `max_instances`: Maximum Cloud Run instances (default: 10)

### Terraform Variables

Edit `terraform/terraform.tfvars` or set environment variables:

```bash
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"
export TF_VAR_service_name="location-recommender"
```

Key variables in `terraform/variables.tf`:

- `project_id`: Google Cloud project ID
- `region`: Deployment region
- `service_name`: Name for the Cloud Run service
- `firestore_database`: Firestore database identifier
- `maps_api_restrictions`: API key restrictions configuration
- `cloud_run_cpu`: CPU allocation for Cloud Run service
- `cloud_run_memory`: Memory allocation for Cloud Run service

## Deployment Outputs

After successful deployment, you'll receive:

- **Service URL**: HTTPS endpoint for the recommendation API
- **Maps API Key**: Configured API key for Maps Platform services
- **Firestore Database**: Database name for user data storage
- **Service Account**: Email of the created service account

## Testing the Deployment

### Health Check

```bash
# Test service health
curl -X GET "https://YOUR_SERVICE_URL/"
```

### Location Recommendations

```bash
# Test recommendation endpoint
curl -X POST "https://YOUR_SERVICE_URL/recommend" \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "test-user-123",
    "latitude": 37.7749,
    "longitude": -122.4194,
    "preferences": {
      "category": "restaurant",
      "cuisine": "italian"
    },
    "radius": 1500
  }'
```

## Security Considerations

### API Key Security

- Maps Platform API key is restricted to specific APIs
- Consider adding HTTP referrer or IP restrictions for production
- Monitor API usage through Google Cloud Console

### Service Account Permissions

- Service account follows least privilege principle
- Permissions limited to required Google Cloud services
- Consider using Workload Identity for enhanced security

### Data Protection

- All data transmission uses HTTPS encryption
- Firestore data is encrypted at rest by default
- User location data should be handled according to privacy regulations

## Monitoring and Observability

### Cloud Run Monitoring

```bash
# View service logs
gcloud logs read "resource.type=cloud_run_revision AND resource.labels.service_name=location-recommender"

# Monitor service metrics
gcloud monitoring metrics list --filter="resource.type=cloud_run_revision"
```

### Firestore Monitoring

```bash
# Check Firestore operations
gcloud logging read "resource.type=firestore_database" --limit=50
```

### Maps API Usage

- Monitor API usage in Google Cloud Console
- Set up billing alerts to control costs
- Review API quotas and limits

## Cost Optimization

### Cloud Run

- Uses pay-per-request pricing model
- Automatic scaling to zero reduces costs during low traffic
- CPU allocation optimized for recommendation workloads

### Firestore

- Document-based pricing model
- Efficient indexing reduces query costs
- Consider TTL policies for cache data

### Maps Platform APIs

- Monitor API calls to optimize usage
- Implement caching strategies for repeated locations
- Use appropriate API call limits

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/location-recommender
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
gcloud run services list --region=us-central1
gcloud firestore databases list
```

## Troubleshooting

### Common Issues

1. **Maps Grounding Access**: Requires manual approval through Google form
2. **API Quotas**: Check API quotas if requests fail
3. **Permissions**: Verify service account has required permissions
4. **Region Availability**: Ensure all services are available in selected region

### Debug Commands

```bash
# Check service logs
gcloud logs tail "projects/PROJECT_ID/logs/run.googleapis.com"

# Verify API enablement
gcloud services list --enabled --filter="name:maps-backend.googleapis.com OR name:aiplatform.googleapis.com"

# Check IAM permissions
gcloud projects get-iam-policy PROJECT_ID
```

### Support Resources

- [Google Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Google Maps Platform Documentation](https://developers.google.com/maps/documentation)
- [Cloud Firestore Documentation](https://cloud.google.com/firestore/docs)

## Customization

### Extending the Solution

1. **Enhanced AI Models**: Integrate custom Vertex AI models for improved recommendations
2. **Real-time Updates**: Add Pub/Sub for real-time location tracking
3. **Caching Layer**: Implement Memorystore for Redis to cache frequent requests
4. **Mobile Integration**: Add Firebase SDK integration for mobile applications
5. **Analytics**: Integrate BigQuery for advanced analytics and reporting

### Environment-Specific Configurations

Create separate variable files for different environments:

```bash
# Development environment
cp terraform/terraform.tfvars.example terraform/dev.tfvars

# Production environment
cp terraform/terraform.tfvars.example terraform/prod.tfvars
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud service documentation
3. Verify IAM permissions and API enablement
4. Monitor service logs for detailed error information
5. Consult Google Cloud Support for service-specific issues

## License

This infrastructure code is provided as part of the cloud recipes collection. Refer to the repository license for usage terms.