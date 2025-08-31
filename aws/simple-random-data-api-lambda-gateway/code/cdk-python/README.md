# Simple Random Data API - CDK Python Application

This CDK Python application creates a serverless REST API using AWS Lambda and API Gateway that generates random data including quotes, numbers, and colors.

## Architecture

The application consists of:

- **AWS Lambda Function**: Python 3.12 runtime that generates random data based on query parameters
- **API Gateway REST API**: Regional endpoint with CORS enabled for web browser access
- **IAM Role**: Lambda execution role with CloudWatch logging permissions
- **CloudWatch Log Group**: Centralized logging with 1-week retention

## Prerequisites

- Python 3.8 or later
- AWS CLI v2 configured with appropriate credentials
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Lambda and API Gateway permissions in your AWS account

## Installation

1. **Clone or download the CDK application**:
   ```bash
   # Navigate to the cdk-python directory
   cd aws/simple-random-data-api-lambda-gateway/code/cdk-python/
   ```

2. **Create and activate a Python virtual environment**:
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK (if not done previously)**:
   ```bash
   cdk bootstrap
   ```

## Deployment

1. **Synthesize the CloudFormation template** (optional):
   ```bash
   cdk synth
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

3. **Note the API endpoint URL** from the deployment output:
   ```
   Outputs:
   SimpleRandomDataApiStack.ApiEndpointUrl = https://abc123def4.execute-api.us-east-1.amazonaws.com/dev/random
   ```

## Usage

### API Endpoints

The API provides a single endpoint: `GET /random`

#### Query Parameters

- `type` (optional): Specifies the type of random data to generate
  - `quote` (default): Returns a random inspirational quote
  - `number`: Returns a random number between 1-1000
  - `color`: Returns a random color with name, hex, and RGB values

#### Examples

1. **Random quote** (default):
   ```bash
   curl "https://your-api-id.execute-api.region.amazonaws.com/dev/random"
   ```

2. **Explicit quote request**:
   ```bash
   curl "https://your-api-id.execute-api.region.amazonaws.com/dev/random?type=quote"
   ```

3. **Random number**:
   ```bash
   curl "https://your-api-id.execute-api.region.amazonaws.com/dev/random?type=number"
   ```

4. **Random color**:
   ```bash
   curl "https://your-api-id.execute-api.region.amazonaws.com/dev/random?type=color"
   ```

#### Response Format

All responses return JSON with the following structure:

```json
{
  "type": "quote|number|color",
  "data": "actual data value",
  "timestamp": "aws-request-id",
  "message": "Success message"
}
```

#### Example Responses

**Quote Response:**
```json
{
  "type": "quote",
  "data": "The only way to do great work is to love what you do. - Steve Jobs",
  "timestamp": "12345678-1234-1234-1234-123456789012",
  "message": "Random quote generated successfully"
}
```

**Number Response:**
```json
{
  "type": "number", 
  "data": 742,
  "timestamp": "12345678-1234-1234-1234-123456789012",
  "message": "Random number generated successfully"
}
```

**Color Response:**
```json
{
  "type": "color",
  "data": {
    "name": "Ocean Blue",
    "hex": "#006994", 
    "rgb": "rgb(0, 105, 148)"
  },
  "timestamp": "12345678-1234-1234-1234-123456789012",
  "message": "Random color generated successfully"
}
```

## Development

### Code Structure

- `app.py`: Main CDK application entry point and stack definition
- `requirements.txt`: Python dependencies
- `setup.py`: Package configuration
- `cdk.json`: CDK configuration and feature flags

### Lambda Function Code

The Lambda function code is embedded inline within the CDK stack for simplicity. It includes:
- Request logging and error handling
- Query parameter parsing
- Random data generation for quotes, numbers, and colors
- Proper CORS headers for web browser compatibility

### Customization

You can customize the application by modifying:

1. **Lambda timeout and memory**: Update `timeout` and `memory_size` in the Lambda function definition
2. **API throttling**: Modify `rate_limit` and `burst_limit` in the API Gateway stage
3. **Log retention**: Change `retention` in the CloudWatch Log Group
4. **Random data**: Update the `quotes` and `colors` arrays in the Lambda function code

### Local Testing

To test changes before deployment:

1. **Synthesize CloudFormation**:
   ```bash
   cdk synth
   ```

2. **Compare changes**:
   ```bash
   cdk diff
   ```

3. **Deploy changes**:
   ```bash
   cdk deploy
   ```

## Monitoring

### CloudWatch Logs

Lambda function logs are automatically sent to CloudWatch:
```bash
# View logs using AWS CLI
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/random-data-api"

# View recent log events
aws logs filter-log-events \
    --log-group-name "/aws/lambda/random-data-api-simplerandomdataapistack" \
    --start-time $(date -d '1 hour ago' +%s)000
```

### API Gateway Metrics

Monitor API performance in the AWS Console:
- API Gateway → APIs → Random Data API → Monitoring
- View request count, latency, and error rates

## Cleanup

To avoid ongoing AWS charges, destroy the stack when no longer needed:

```bash
cdk destroy
```

Confirm the deletion when prompted. This will remove:
- Lambda function
- API Gateway
- IAM role
- CloudWatch Log Group

## Cost Estimation

This application uses AWS Free Tier eligible services:
- **Lambda**: 1 million free requests per month
- **API Gateway**: 1 million free API calls per month (first 12 months)
- **CloudWatch Logs**: 5 GB free per month

Typical costs after Free Tier:
- Lambda: $0.0000002 per request + $0.0000166667 per GB-second
- API Gateway: $3.50 per million requests
- CloudWatch Logs: $0.50 per GB ingested

## Troubleshooting

### Common Issues

1. **CDK bootstrap required**:
   ```bash
   cdk bootstrap aws://ACCOUNT-NUMBER/REGION
   ```

2. **Python virtual environment**:
   ```bash
   deactivate && rm -rf venv
   python3 -m venv venv && source venv/bin/activate
   pip install -r requirements.txt
   ```

3. **AWS credentials**:
   ```bash
   aws configure
   # or
   export AWS_PROFILE=your-profile
   ```

4. **API Gateway CORS errors**: The stack includes CORS configuration, but browsers may cache preflight responses

### Support

- [AWS CDK Python Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-python.html)
- [AWS Lambda Python Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/lambda-python.html)
- [API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)

## License

This sample code is provided under the MIT-0 License. See the LICENSE file for details.