# Infrastructure as Code for Weather API with Cloud Functions and Firestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Weather API with Cloud Functions and Firestore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (version 450.0.0 or higher)
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions deployment
  - Firestore database management
  - Cloud Build API usage
  - Artifact Registry access
- OpenWeatherMap API key (free tier available at openweathermap.org)

## Quick Start

### Using Infrastructure Manager (GCP)

Infrastructure Manager provides Google Cloud's native infrastructure as code capabilities with deep integration into GCP services.

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export WEATHER_API_KEY="your_openweathermap_api_key"

# Deploy using Infrastructure Manager
gcloud infra-manager deployments create weather-api-deployment \
    --location=${REGION} \
    --git-source-repo="https://github.com/your-repo/weather-api" \
    --git-source-directory="infrastructure-manager/" \
    --input-values="project_id=${PROJECT_ID},region=${REGION},weather_api_key=${WEATHER_API_KEY}"
```

### Using Terraform

Terraform provides cross-platform infrastructure management with extensive Google Cloud provider support.

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export WEATHER_API_KEY="your_openweathermap_api_key"

# Initialize and deploy with Terraform
cd terraform/
terraform init
terraform plan -var="project_id=${PROJECT_ID}" \
               -var="region=${REGION}" \
               -var="weather_api_key=${WEATHER_API_KEY}"
terraform apply -var="project_id=${PROJECT_ID}" \
                -var="region=${REGION}" \
                -var="weather_api_key=${WEATHER_API_KEY}"
```

### Using Bash Scripts

Automated deployment scripts provide a simple way to deploy the complete solution with minimal configuration.

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export WEATHER_API_KEY="your_openweathermap_api_key"

# Deploy using bash scripts
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

The infrastructure deploys the following Google Cloud resources:

- **Cloud Function (Gen2)**: Serverless HTTP function for weather API
- **Firestore Database**: NoSQL document database for caching weather data
- **Cloud Build**: Automated function deployment and source management
- **Artifact Registry**: Container image storage for Cloud Functions
- **IAM Roles**: Service account and permissions for secure function execution

## Configuration Options

### Environment Variables

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `PROJECT_ID` | Google Cloud project ID | Yes | None |
| `REGION` | Deployment region | Yes | `us-central1` |
| `WEATHER_API_KEY` | OpenWeatherMap API key | Yes | None |
| `FUNCTION_NAME` | Cloud Function name | No | `weather-api` |
| `CACHE_TTL_MINUTES` | Cache time-to-live in minutes | No | `10` |

### Terraform Variables

```hcl
# terraform/terraform.tfvars.example
project_id = "your-project-id"
region = "us-central1"
weather_api_key = "your_openweathermap_api_key"
function_name = "weather-api"
cache_ttl_minutes = 10
```

### Infrastructure Manager Configuration

```yaml
# infrastructure-manager/config.yaml
inputs:
  project_id: "your-project-id"
  region: "us-central1"
  weather_api_key: "your_openweathermap_api_key"
  function_name: "weather-api"
  cache_ttl_minutes: 10
```

## API Usage

Once deployed, the weather API will be available at the Cloud Function's HTTP trigger URL:

```bash
# Get weather for London (default)
curl "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/weather-api"

# Get weather for a specific city
curl "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/weather-api?city=Paris"

# Example response
{
  "coord": {"lon": -0.1257, "lat": 51.5085},
  "weather": [{"id": 300, "main": "Drizzle", "description": "light intensity drizzle", "icon": "09d"}],
  "main": {"temp": 15.2, "feels_like": 14.8, "temp_min": 14.1, "temp_max": 16.3, "pressure": 1013, "humidity": 82},
  "name": "London",
  "cod": 200
}
```

## Monitoring and Observability

### Cloud Function Metrics

Monitor function performance through Google Cloud Console:

```bash
# View function logs
gcloud functions logs read weather-api --region=${REGION}

# Monitor function metrics
gcloud logging read "resource.type=cloud_function resource.labels.function_name=weather-api" --limit=50
```

### Firestore Usage

Track cache performance and database usage:

```bash
# Check Firestore collection statistics
gcloud firestore databases describe --database="(default)"

# Monitor cached weather data
gcloud firestore collections list
```

## Security Considerations

- Weather API key is stored as a Cloud Function environment variable
- Cloud Function uses service account with minimal required permissions
- HTTPS-only communication enforced by default
- CORS headers configured for web application integration
- No authentication required for public weather data access

## Cost Optimization

- Cloud Functions Gen2 provides improved cold start performance
- Firestore caching reduces external API calls by ~90%
- Free tier limits: 2M invocations/month, 400,000 GB-seconds compute time
- Firestore free tier: 1GB storage, 50,000 reads/day, 20,000 writes/day
- Estimated monthly cost: $0-2 for light usage within free tier

## Cleanup

### Using Infrastructure Manager (GCP)

```bash
# Delete the Infrastructure Manager deployment
gcloud infra-manager deployments delete weather-api-deployment \
    --location=${REGION} \
    --quiet
```

### Using Terraform

```bash
# Destroy infrastructure with Terraform
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" \
                  -var="region=${REGION}" \
                  -var="weather_api_key=${WEATHER_API_KEY}"
```

### Using Bash Scripts

```bash
# Cleanup using bash scripts
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud Function
gcloud functions delete weather-api --region=${REGION} --quiet

# Delete Firestore database
gcloud firestore databases delete --database="(default)" --quiet

# Disable APIs (optional)
gcloud services disable cloudfunctions.googleapis.com
gcloud services disable firestore.googleapis.com
gcloud services disable cloudbuild.googleapis.com
```

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   gcloud builds log [BUILD_ID]
   ```

2. **Weather API key errors**:
   ```bash
   # Verify environment variable is set
   gcloud functions describe weather-api --region=${REGION} --format="value(serviceConfig.environmentVariables)"
   ```

3. **Firestore permission errors**:
   ```bash
   # Check service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

4. **CORS issues**:
   - Verify CORS headers in function response
   - Check browser developer tools for specific CORS errors

### Performance Optimization

- Monitor cache hit rates through Cloud Logging
- Adjust cache TTL based on weather data update frequency
- Consider implementing different TTL values for different cities
- Use Cloud Monitoring to set up alerting for high error rates

## Customization

### Adding Features

1. **Weather Forecasting**: Extend the API to include 5-day forecast data
2. **Location Geocoding**: Add support for coordinates instead of city names
3. **Weather Alerts**: Implement Pub/Sub notifications for severe weather
4. **API Authentication**: Add API key validation for access control

### Scaling Considerations

- Cloud Functions automatically scale to handle traffic spikes
- Firestore provides automatic multi-region replication
- Consider implementing rate limiting for high-traffic scenarios
- Use Cloud CDN for global performance optimization

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for detailed implementation guidance
2. Refer to [Google Cloud Functions documentation](https://cloud.google.com/functions/docs)
3. Consult [Firestore best practices](https://cloud.google.com/firestore/docs/best-practices)
4. Review [Infrastructure Manager documentation](https://cloud.google.com/infrastructure-manager/docs)
5. Access [Terraform Google Cloud provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Additional Resources

- [OpenWeatherMap API Documentation](https://openweathermap.org/api)
- [Cloud Functions Python Runtime](https://cloud.google.com/functions/docs/concepts/python-runtime)
- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/get-started)
- [Google Cloud Cost Calculator](https://cloud.google.com/products/calculator)