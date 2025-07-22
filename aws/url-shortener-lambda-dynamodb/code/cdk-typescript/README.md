# URL Shortener CDK TypeScript Application

This CDK TypeScript application deploys a serverless URL shortener service using AWS Lambda, DynamoDB, and API Gateway.

## Architecture

- **AWS Lambda**: Serverless compute for URL shortening and redirection logic
- **Amazon DynamoDB**: NoSQL database for storing URL mappings
- **Amazon API Gateway**: HTTP API endpoints for creating and accessing short URLs
- **Amazon CloudWatch**: Monitoring and logging

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- Node.js 18.x or later
- AWS CDK CLI v2.x installed globally (`npm install -g aws-cdk`)
- Docker (required for bundling Lambda functions)

## Setup

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap your AWS environment** (first time only):
   ```bash
   npm run bootstrap
   ```

3. **Build the application**:
   ```bash
   npm run build
   ```

## Deployment

1. **Synthesize CloudFormation template** (optional):
   ```bash
   npm run synth
   ```

2. **Deploy the stack**:
   ```bash
   npm run deploy
   ```

3. **View stack outputs** after deployment to get the API Gateway URL and other resource information.

## API Usage

### Create a Short URL

```bash
curl -X POST https://your-api-id.execute-api.region.amazonaws.com/prod/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com/very-long-url"}'
```

Response:
```json
{
  "short_id": "abc123",
  "short_url": "https://your-domain.com/abc123",
  "original_url": "https://example.com/very-long-url",
  "expires_at": "2024-08-12T10:30:00.000Z"
}
```

### Redirect Using Short URL

```bash
curl -I https://your-api-id.execute-api.region.amazonaws.com/prod/abc123
```

This will return a 302 redirect to the original URL.

## Project Structure

```
.
├── app.ts                  # CDK app entry point
├── lib/
│   └── url-shortener-stack.ts  # Main stack definition
├── package.json            # Dependencies and scripts
├── tsconfig.json          # TypeScript configuration
├── cdk.json              # CDK configuration
└── README.md             # This file
```

## Key Features

- **Serverless Architecture**: Pay-per-use pricing with automatic scaling
- **Security**: IAM roles with least privilege access
- **Monitoring**: CloudWatch logs and metrics
- **CORS Enabled**: Cross-origin requests supported
- **URL Validation**: Input validation and error handling
- **Expiration**: URLs expire after 30 days (configurable)
- **Click Tracking**: Track URL usage with DynamoDB counters

## Configuration

The application uses the following default settings:

- Lambda timeout: 30 seconds
- Lambda memory: 256 MB
- DynamoDB billing: Pay-per-request
- URL expiration: 30 days
- Log retention: 1 week

These can be modified in `lib/url-shortener-stack.ts`.

## Monitoring

After deployment, you can monitor the application using:

1. **CloudWatch Logs**: View Lambda function logs
2. **CloudWatch Metrics**: Monitor API Gateway and Lambda metrics
3. **DynamoDB Metrics**: Track table performance

## Testing

Test the deployment using the provided API endpoints:

```bash
# Get the API Gateway URL from stack outputs
API_URL=$(aws cloudformation describe-stacks \
  --stack-name UrlShortenerStack \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
  --output text)

# Create a short URL
curl -X POST ${API_URL}shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://docs.aws.amazon.com/lambda/latest/dg/welcome.html"}'

# Test redirection (replace 'abc123' with actual short_id from response)
curl -I ${API_URL}abc123
```

## Cleanup

To remove all resources:

```bash
npm run destroy
```

## Cost Considerations

This application uses serverless services with pay-per-use pricing:

- **Lambda**: $0.20 per 1M requests + compute time
- **DynamoDB**: $1.25 per million write requests, $0.25 per million read requests
- **API Gateway**: $3.50 per million API calls
- **CloudWatch Logs**: $0.50 per GB ingested

Estimated monthly cost for light usage (1000 URLs created, 10000 redirects): $0.50-$2.00

## Security Best Practices

This application implements several security best practices:

- IAM roles with minimal required permissions
- Input validation for all user inputs
- HTTPS endpoints only
- CORS configuration for web applications
- CloudWatch logging for audit trails

## Customization

To customize the application:

1. **URL Expiration**: Modify the `timedelta(days=30)` in the Lambda function
2. **Short ID Length**: Adjust the `[:8]` slice in the `generate_short_id` function
3. **Custom Domain**: Add Route 53 and ACM certificate configuration
4. **Rate Limiting**: Configure API Gateway throttling settings
5. **Analytics**: Add additional DynamoDB attributes for tracking

## Troubleshooting

Common issues and solutions:

1. **Permission Errors**: Ensure your AWS credentials have sufficient permissions
2. **Region Mismatch**: Verify CDK is deploying to the correct region
3. **Bootstrap Required**: Run `cdk bootstrap` if you haven't used CDK in this account/region
4. **Node Version**: Ensure you're using Node.js 18.x or later

## Support

For issues with this CDK application:

1. Check CloudWatch Logs for Lambda function errors
2. Verify API Gateway integration configuration
3. Review DynamoDB table permissions and settings
4. Consult the AWS CDK documentation: https://docs.aws.amazon.com/cdk/

## License

This project is licensed under the MIT License.