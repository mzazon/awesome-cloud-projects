# Infrastructure as Code for Weather Forecast API with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Weather Forecast API with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Cloud Functions API, Cloud Run API, Cloud Build API, and Artifact Registry API enabled
- OpenWeatherMap API key (optional, for production use)
- Appropriate IAM permissions for:
  - Cloud Functions deployment
  - Cloud Run service management
  - IAM role binding
  - Artifact Registry access
  - Cloud Build execution

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/weather-forecast-api \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/weather-forecast-api
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
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

# View deployment status
gcloud run services list --filter="weather-forecast"
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"
export FUNCTION_NAME="weather-forecast"
export OPENWEATHER_API_KEY="your-openweather-api-key"  # Optional
```

### Infrastructure Manager Variables

Create a `terraform.tfvars` file in the `infrastructure-manager/` directory:

```hcl
project_id = "your-gcp-project-id"
region = "us-central1"
function_name = "weather-forecast"
openweather_api_key = "your-openweather-api-key"  # Optional
memory_limit = "512Mi"
timeout_seconds = 60
```

### Terraform Variables

Customize the deployment by modifying variables in `terraform/terraform.tfvars`:

```hcl
project_id = "your-gcp-project-id"
region = "us-central1"
function_name = "weather-forecast"
openweather_api_key = "your-openweather-api-key"  # Optional
memory_limit = "512Mi"
timeout_seconds = 60
allow_unauthenticated = true
```

## Testing the Deployment

After successful deployment, test your weather API:

```bash
# Get the function URL from outputs
FUNCTION_URL=$(terraform output -raw function_url)

# Test with default city (London)
curl "${FUNCTION_URL}"

# Test with specific city
curl "${FUNCTION_URL}?city=Tokyo"

# Test with invalid city
curl "${FUNCTION_URL}?city=InvalidCity"
```

Expected response format:

```json
{
  "city": "Tokyo",
  "country": "JP",
  "temperature": 22.5,
  "feels_like": 23.1,
  "humidity": 65,
  "description": "clear sky",
  "wind_speed": 3.2,
  "timestamp": 1673456789
}
```

## Monitoring and Logging

### View Function Logs

```bash
# View recent logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=${FUNCTION_NAME}" \
    --limit=50 \
    --format="table(timestamp,severity,textPayload)"

# Stream live logs
gcloud logging tail "resource.type=cloud_run_revision AND resource.labels.service_name=${FUNCTION_NAME}"
```

### Check Function Metrics

```bash
# View function details
gcloud run services describe ${FUNCTION_NAME} --region=${REGION}

# Check function revisions
gcloud run revisions list --service=${FUNCTION_NAME} --region=${REGION}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/weather-forecast-api

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
# Run cleanup script
./scripts/destroy.sh

# Verify resources are deleted
gcloud run services list --filter="weather-forecast"
```

## Security Considerations

### API Key Management

- **Development**: Use demo API key for testing (limited functionality)
- **Production**: Store OpenWeatherMap API key in Google Secret Manager
- **Environment Variables**: Never commit API keys to source control

### Access Control

- Function is deployed with `--allow-unauthenticated` for public access
- For private access, remove this flag and configure IAM policies
- Consider using API Gateway for advanced authentication and rate limiting

### Network Security

- Function uses HTTPS by default
- CORS headers are configured for web browser access
- Input validation prevents injection attacks

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   ```bash
   # Check enabled APIs
   gcloud services list --enabled --filter="name:cloudfunctions OR name:cloudbuild OR name:artifactregistry"
   
   # Verify IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

2. **API returns "Invalid API key" error**:
   ```bash
   # Check environment variable
   gcloud run services describe ${FUNCTION_NAME} --region=${REGION} --format="value(spec.template.spec.template.spec.containers[0].env[0].value)"
   
   # Update API key
   gcloud run deploy ${FUNCTION_NAME} --region=${REGION} --set-env-vars OPENWEATHER_API_KEY=your-new-key
   ```

3. **Function timeout errors**:
   ```bash
   # Increase timeout (max 3600 seconds)
   gcloud run deploy ${FUNCTION_NAME} --region=${REGION} --timeout=120
   ```

### Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
# Set environment variable for debug logging
gcloud run deploy ${FUNCTION_NAME} --region=${REGION} --set-env-vars DEBUG=true

# View detailed logs
gcloud logging read "resource.type=cloud_run_revision AND severity>=INFO" --limit=20
```

## Cost Optimization

### Free Tier Limits

- **Cloud Functions**: 2 million invocations per month (free)
- **Cloud Run**: 180,000 vCPU-seconds per month (free)
- **OpenWeatherMap**: 1,000 API calls per day (free tier)

### Cost-Saving Tips

1. **Memory Allocation**: Use minimum required memory (128Mi-1Gi)
2. **Timeout Settings**: Set appropriate timeout values to prevent long-running requests
3. **Monitoring**: Use Cloud Monitoring to track usage and optimize resource allocation

## Customization

### Function Configuration

Modify function behavior by updating environment variables:

```bash
# Add response caching
gcloud run deploy ${FUNCTION_NAME} --region=${REGION} \
    --set-env-vars CACHE_TTL=300,ENABLE_CACHE=true

# Configure request timeout
gcloud run deploy ${FUNCTION_NAME} --region=${REGION} \
    --set-env-vars REQUEST_TIMEOUT=30
```

### Scaling Configuration

```bash
# Configure concurrency and scaling
gcloud run deploy ${FUNCTION_NAME} --region=${REGION} \
    --concurrency=100 \
    --min-instances=0 \
    --max-instances=10
```

## Integration Examples

### Frontend Integration

```javascript
// JavaScript example
async function getWeather(city) {
    const response = await fetch(`${FUNCTION_URL}?city=${city}`);
    const data = await response.json();
    return data;
}

// React component example
const WeatherComponent = () => {
    const [weather, setWeather] = useState(null);
    
    useEffect(() => {
        getWeather('London').then(setWeather);
    }, []);
    
    return weather ? (
        <div>
            <h2>{weather.city}</h2>
            <p>Temperature: {weather.temperature}°C</p>
            <p>Description: {weather.description}</p>
        </div>
    ) : <div>Loading...</div>;
};
```

### Mobile App Integration

```bash
# iOS Swift example
let url = URL(string: "\(functionURL)?city=\(cityName)")!
URLSession.shared.dataTask(with: url) { data, response, error in
    // Handle response
}.resume()

# Android Kotlin example
val request = Request.Builder()
    .url("$functionUrl?city=$cityName")
    .build()
    
client.newCall(request).enqueue(callback)
```

## Support

For issues with this infrastructure code, refer to:

- [Original Recipe Documentation](../weather-forecast-api-functions.md)
- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Google Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [OpenWeatherMap API Documentation](https://openweathermap.org/api)

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Modify as needed for your production requirements.