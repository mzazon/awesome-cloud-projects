# Infrastructure as Code for Voice Recording Analysis with AI Speech and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Voice Recording Analysis with AI Speech and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Appropriate Azure subscription with permissions for:
  - Creating resource groups
  - Deploying Azure AI Speech Services
  - Creating Azure Functions (consumption plan)
  - Creating Storage Accounts and containers
  - Configuring application settings
- For Terraform: Terraform CLI installed (version 1.0+)
- For Bicep: Azure CLI with Bicep extension installed
- Audio file for testing (WAV, MP3, or similar format)

## Architecture Overview

This infrastructure deploys:
- Azure Storage Account with blob containers for audio input and transcript output
- Azure AI Speech Service with F0 (free) tier
- Azure Function App with consumption plan and Python runtime
- Application settings for secure service integration
- Function code for voice-to-text processing

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy infrastructure
az deployment group create \
    --resource-group myResourceGroup \
    --template-file bicep/main.bicep \
    --parameters location=eastus

# Get outputs for testing
az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
cd terraform/
terraform init
terraform plan -var="location=eastus" -var="resource_group_name=myResourceGroup"
terraform apply
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Configuration Options

### Bicep Parameters

- `location`: Azure region for deployment (default: eastus)
- `resourcePrefix`: Prefix for resource names (default: voice)
- `speechServiceSku`: Speech service pricing tier (default: F0)
- `storageAccountSku`: Storage account performance tier (default: Standard_LRS)

### Terraform Variables

- `location`: Azure region for deployment
- `resource_group_name`: Name of the resource group
- `resource_prefix`: Prefix for resource names
- `speech_service_sku`: Speech service pricing tier
- `storage_account_replication_type`: Storage replication type

## Testing the Deployment

1. **Upload Test Audio File**:
   ```bash
   # Get storage connection string from deployment outputs
   STORAGE_CONNECTION="<from deployment outputs>"
   
   # Upload audio file to input container
   az storage blob upload \
       --container-name "audio-input" \
       --file "/path/to/your/audio.wav" \
       --name "test-audio.wav" \
       --connection-string "${STORAGE_CONNECTION}"
   ```

2. **Test Function Endpoint**:
   ```bash
   # Get function URL and key from deployment outputs
   FUNCTION_URL="<from deployment outputs>"
   FUNCTION_KEY="<from deployment outputs>"
   
   # Test transcription
   curl -X POST "${FUNCTION_URL}?code=${FUNCTION_KEY}" \
       -H "Content-Type: application/json" \
       -d '{"filename": "test-audio.wav", "language": "en-US"}'
   ```

3. **Verify Results**:
   ```bash
   # List transcripts in output container
   az storage blob list \
       --container-name "transcripts" \
       --connection-string "${STORAGE_CONNECTION}" \
       --output table
   
   # Download transcript
   az storage blob download \
       --container-name "transcripts" \
       --name "test-audio_transcript.json" \
       --file "transcript-result.json" \
       --connection-string "${STORAGE_CONNECTION}"
   ```

## Cleanup

### Using Bicep
```bash
# Delete the resource group and all resources
az group delete --name myResourceGroup --yes --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Function Code Details

The deployed Azure Function includes:

- **HTTP Trigger**: Accepts POST requests with audio file information
- **Error Handling**: Comprehensive error handling for various failure scenarios
- **Language Support**: Configurable language detection (default: en-US)
- **Blob Integration**: Automatic download from input container and upload to output container
- **Speech Processing**: Integration with Azure AI Speech Services for transcription
- **JSON Response**: Structured response with transcript, confidence, and metadata

### Function Request Format

```json
{
  "filename": "audio-file.wav",
  "language": "en-US"
}
```

### Function Response Format

```json
{
  "filename": "audio-file.wav",
  "transcript": "Hello, this is the transcribed text.",
  "language": "en-US",
  "confidence": "high",
  "status": "success",
  "duration_processed": "N/A"
}
```

## Security Considerations

- Speech Service API keys are stored securely in Function App settings
- Storage connection strings are managed through application configuration
- Function endpoints require function key authentication
- Blob containers have public access disabled by default
- All resources follow Azure security best practices

## Cost Optimization

- Azure AI Speech Service uses F0 (free) tier with generous limits
- Function App uses consumption plan (pay-per-execution)
- Storage Account uses Standard_LRS for cost-effective storage
- Resources are tagged for cost tracking and management

## Troubleshooting

### Common Issues

1. **Function deployment fails**: Ensure Python 3.11 runtime is available in your region
2. **Speech recognition errors**: Verify audio file format and language settings
3. **Storage access issues**: Check connection string configuration in Function App settings
4. **Authentication failures**: Verify function key is correctly included in requests

### Monitoring

Enable Application Insights for comprehensive monitoring:
- Function execution logs
- Performance metrics
- Error tracking
- Dependency monitoring

## Customization

### Adding Support for Additional Languages

Modify the function code to support multiple languages:

```python
# In function_app.py
supported_languages = ["en-US", "es-ES", "fr-FR", "de-DE"]
language = req_body.get('language', 'en-US')
if language not in supported_languages:
    language = 'en-US'  # fallback
```

### Implementing Batch Processing

Add a blob trigger function for automatic processing:

```python
@app.blob_trigger(arg_name="inputblob", 
                  path="audio-input/{name}",
                  connection="STORAGE_CONNECTION")
def process_uploaded_audio(inputblob: func.InputStream):
    # Process automatically when files are uploaded
```

### Adding Real-time Processing

Integrate with Azure SignalR Service for real-time updates:

```python
# Add SignalR output binding for live transcription updates
@app.signalr_output(arg_name="signalr", hub_name="transcription")
def send_realtime_update(signalr: func.Out[str]):
    # Send progress updates during processing
```

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation
2. Review Azure Function logs in the Azure portal
3. Consult Azure AI Speech Service documentation
4. Verify resource configurations in Azure portal

## Contributing

When modifying the infrastructure:
1. Test changes in a development environment
2. Update both Bicep and Terraform implementations
3. Validate security configurations
4. Update documentation accordingly

## References

- [Azure AI Speech Service Documentation](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/)
- [Azure Functions Python Developer Guide](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-python)
- [Azure Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)