# Infrastructure as Code for Weather Information API with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Weather Information API with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code using Terraform-compatible configuration
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts with comprehensive error handling

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Appropriate Google Cloud permissions for:
  - Cloud Functions (create, deploy, delete)
  - Cloud Build API access
  - Cloud Run API access
  - IAM role assignments
- For Infrastructure Manager: Google Cloud Infrastructure Manager API enabled
- For Terraform: Terraform CLI installed (version 1.0 or later)
- OpenWeatherMap API key (optional, demo mode available)

> **Note**: This recipe uses Google Cloud's generous free tier for Cloud Functions, including 2 million free invocations per month.

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native IaC service that uses Terraform-compatible configuration with enhanced Google Cloud integration.

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy using Infrastructure Manager
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/weather-api-deployment \
    --service-account projects/${PROJECT_ID}/serviceAccounts/infra-manager-sa@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars"
```

### Using Terraform

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Initialize and deploy with Terraform
cd terraform/
terraform init
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

The bash scripts provide a simple deployment option with comprehensive error handling and validation.

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable and deploy
chmod +x scripts/deploy.sh scripts/destroy.sh
./scripts/deploy.sh
```

## Configuration Options

### Environment Variables

All implementations support these environment variables for customization:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud Project ID | - | Yes |
| `REGION` | Deployment region | `us-central1` | No |
| `FUNCTION_NAME` | Cloud Function name | `weather-api` | No |
| `WEATHER_API_KEY` | OpenWeatherMap API key | `demo_key_please_replace` | No |
| `MEMORY_SIZE` | Function memory allocation | `256MB` | No |
| `TIMEOUT` | Function timeout in seconds | `60s` | No |

### API Key Configuration

For production use with real weather data:

1. Sign up for a free API key at [OpenWeatherMap](https://openweathermap.org/api)
2. Set the `WEATHER_API_KEY` environment variable before deployment
3. The function will automatically use real weather data instead of demo data

```bash
export WEATHER_API_KEY="your-openweathermap-api-key"
```

## Testing Your Deployment

After successful deployment, test the API endpoints:

### Basic Weather Query

```bash
# Get the function URL from deployment output
FUNCTION_URL=$(gcloud functions describe weather-api --region=${REGION} --format="value(httpsTrigger.url)")

# Test with demo data
curl "${FUNCTION_URL}?city=London"

# Test with different cities
curl "${FUNCTION_URL}?city=Tokyo"
curl "${FUNCTION_URL}?city=New York"
```

### Error Handling Tests

```bash
# Test without city parameter
curl "${FUNCTION_URL}"

# Test with empty city parameter
curl "${FUNCTION_URL}?city="

# Test with invalid city
curl "${FUNCTION_URL}?city=InvalidCityName123"
```

### Expected Response Format

```json
{
  "city": "London",
  "country": "GB",
  "temperature": 15.3,
  "feels_like": 14.1,
  "description": "Partly Cloudy",
  "humidity": 72,
  "wind_speed": 3.6,
  "timestamp": 1641234567
}
```

## Monitoring and Logs

### View Function Logs

```bash
# View recent function logs
gcloud functions logs read weather-api --region=${REGION} --limit=20

# Follow logs in real-time
gcloud functions logs tail weather-api --region=${REGION}
```

### Monitor Function Metrics

```bash
# View function details and metrics
gcloud functions describe weather-api --region=${REGION}

# View function usage metrics in Cloud Console
echo "Visit: https://console.cloud.google.com/functions/details/${REGION}/weather-api?project=${PROJECT_ID}"
```

## Cleanup

### Using Infrastructure Manager

```bash
cd infrastructure-manager/
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/weather-api-deployment
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify function is deleted
gcloud functions list --filter="name:weather-api"

# Clean up any remaining resources
gcloud functions delete weather-api --region=${REGION} --quiet
```

## Customization

### Function Configuration

To customize the Cloud Function deployment, modify these parameters in your chosen IaC implementation:

- **Memory allocation**: Adjust based on expected load (128MB - 8GB)
- **Timeout**: Set appropriate timeout for external API calls (default: 60s)
- **Environment variables**: Add additional configuration as needed
- **Runtime**: Currently uses Python 3.12 (latest supported)

### Security Enhancements

For production deployments, consider implementing:

1. **Authentication**: Remove `--allow-unauthenticated` and implement proper IAM
2. **Rate limiting**: Use Cloud Endpoints for API rate limiting
3. **CORS configuration**: Restrict CORS to specific domains
4. **API key validation**: Implement API key validation for your weather API

### Performance Optimization

- **Caching**: Implement Cloud Memorystore for caching weather responses
- **Cold start optimization**: Use minimum instances to reduce cold starts
- **Connection pooling**: Optimize external API connections
- **Response compression**: Enable gzip compression for responses

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   ```bash
   # Check API enablement
   gcloud services list --enabled | grep functions
   
   # Enable required APIs
   gcloud services enable cloudfunctions.googleapis.com cloudbuild.googleapis.com
   ```

2. **Permission denied errors**:
   ```bash
   # Check current authentication
   gcloud auth list
   
   # Check project permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Function returns 500 errors**:
   ```bash
   # Check function logs for errors
   gcloud functions logs read weather-api --region=${REGION}
   ```

4. **Weather API rate limiting**:
   - Implement caching to reduce API calls
   - Consider upgrading OpenWeatherMap API plan
   - Add retry logic with exponential backoff

### Support Resources

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Google Cloud Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [OpenWeatherMap API Documentation](https://openweathermap.org/api)

## Cost Optimization

### Estimate Costs

- **Cloud Functions**: $0.40 per million requests (after free tier)
- **Cloud Build**: $0.003 per build minute (120 build minutes free per day)
- **Outbound data transfer**: $0.12 per GB (1 GB free per month)

### Cost-Saving Tips

1. Use the free tier effectively (2 million requests/month)
2. Implement response caching to reduce external API calls
3. Optimize function memory allocation based on actual usage
4. Monitor usage with Cloud Billing alerts
5. Consider using Cloud Scheduler for regular weather updates instead of on-demand requests

## Architecture Benefits

This serverless architecture provides several advantages:

- **Zero server management**: No infrastructure to maintain
- **Automatic scaling**: Handles traffic spikes automatically
- **Pay-per-use pricing**: Only pay for actual function invocations
- **Built-in security**: Managed SSL certificates and DDoS protection
- **Global distribution**: Automatic deployment across Google's global network
- **High availability**: Built-in redundancy and failover capabilities

## Next Steps

After successful deployment, consider these enhancements:

1. **Add more weather endpoints**: Implement forecast, historical data, and weather alerts
2. **Create a web dashboard**: Build a simple frontend to visualize weather data
3. **Implement user authentication**: Add API key management for multiple users
4. **Set up monitoring alerts**: Configure alerts for function failures or high usage
5. **Add data persistence**: Store weather data in Cloud Firestore for offline access

## Support

For issues with this infrastructure code, refer to:

1. The original recipe documentation in the parent directory
2. Google Cloud Functions documentation
3. Provider-specific documentation (Infrastructure Manager, Terraform)
4. OpenWeatherMap API documentation for external API issues

---

**Recipe Version**: 1.1  
**Last Updated**: 2025-07-12  
**Generated IaC Types**: Infrastructure Manager, Terraform, Bash Scripts