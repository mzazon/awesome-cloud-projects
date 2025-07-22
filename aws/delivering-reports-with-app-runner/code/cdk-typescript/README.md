# Scheduled Email Reports with CDK TypeScript

This CDK TypeScript application deploys a scheduled email reporting system using AWS App Runner, SES, EventBridge Scheduler, and CloudWatch.

## Architecture

The application creates:

- **AWS App Runner Service**: Containerized Flask application for report generation
- **Amazon SES**: Email sending service with verified identity
- **EventBridge Scheduler**: Daily scheduling at 9 AM UTC
- **IAM Roles**: Proper permissions for service interactions
- **CloudWatch**: Monitoring, logging, and dashboards
- **Custom Resource**: Updates scheduler target URL after App Runner deployment

## Prerequisites

- AWS CLI v2 configured with appropriate permissions
- Node.js 18+ and npm installed
- CDK CLI installed (`npm install -g aws-cdk`)
- Verified email address for SES
- GitHub repository with the Flask application code

## Application Configuration

Before deployment, you need to set up your configuration:

1. **Verify Email Address**: Replace the default email with your verified SES email
2. **GitHub Repository**: Update the repository URL to your Flask application
3. **Schedule**: Modify the cron expression if needed (default: daily at 9 AM UTC)

### Configuration Options

You can configure the application using CDK context or environment variables:

```bash
# Using CDK context
cdk deploy -c verifiedEmail=your-email@example.com -c githubRepo=https://github.com/your-username/your-repo

# Using environment variables
export SES_VERIFIED_EMAIL=your-email@example.com
export GITHUB_REPO_URL=https://github.com/your-username/your-repo
cdk deploy
```

## Deployment

1. **Install Dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK** (if first time):
   ```bash
   cdk bootstrap
   ```

3. **Synthesize CloudFormation**:
   ```bash
   cdk synth
   ```

4. **Deploy Stack**:
   ```bash
   # With configuration
   cdk deploy -c verifiedEmail=your-verified-email@example.com -c githubRepo=https://github.com/your-username/email-reports-app
   
   # Or using environment variables
   export SES_VERIFIED_EMAIL=your-verified-email@example.com
   export GITHUB_REPO_URL=https://github.com/your-username/email-reports-app
   cdk deploy
   ```

## Flask Application Structure

Your GitHub repository should contain:

```
email-reports-app/
├── app.py                 # Flask application with /health and /generate-report endpoints
├── requirements.txt       # Python dependencies (Flask, boto3)
├── Dockerfile            # Container configuration
└── apprunner.yaml        # App Runner service configuration
```

### Required Flask Endpoints

- `GET /health`: Health check endpoint returning JSON status
- `POST /generate-report`: Report generation endpoint that sends email via SES

### Environment Variables

The App Runner service receives:
- `SES_VERIFIED_EMAIL`: Your verified email address
- `AWS_DEFAULT_REGION`: AWS region for the deployment

## Monitoring and Logging

The stack includes:

1. **CloudWatch Log Group**: Application logs from App Runner
2. **CloudWatch Metrics**: Custom metrics for report generation
3. **CloudWatch Alarms**: Alerts for generation failures
4. **CloudWatch Dashboard**: Visual monitoring interface

## Testing

After deployment:

1. **Verify Email**: Check your email for SES verification
2. **Test Endpoints**: 
   ```bash
   # Get service URL from stack outputs
   curl https://your-service-url.awsapprunner.com/health
   curl -X POST https://your-service-url.awsapprunner.com/generate-report
   ```
3. **Check CloudWatch**: Monitor logs and metrics in AWS console

## Customization

### Schedule Expression

Modify the schedule in `app.ts`:

```typescript
scheduleExpression: 'cron(0 9 * * ? *)'  // Daily at 9 AM UTC
// Examples:
// 'cron(0 8 * * MON *)'     // Every Monday at 8 AM
// 'cron(0 17 ? * FRI *)'    // Every Friday at 5 PM
// 'rate(12 hours)'          // Every 12 hours
```

### App Runner Configuration

Adjust CPU/memory in the stack:

```typescript
instanceConfiguration: {
  cpu: '0.25 vCPU',     // Options: 0.25, 0.5, 1, 2 vCPU
  memory: '0.5 GB',     // Options: 0.5, 1, 2, 3, 4 GB
  // ...
}
```

### Email Recipients

Modify the Flask application to support multiple recipients or dynamic recipient lists.

## Cost Optimization

- App Runner pricing: ~$5-10/month for 0.25 vCPU, 0.5 GB memory
- SES pricing: $0.10 per 1,000 emails
- EventBridge Scheduler: $1.00 per million invocations
- CloudWatch: Based on log retention and metrics

## Security Features

- **IAM Roles**: Least privilege principles
- **SES Verification**: Prevents unauthorized email sending
- **CloudWatch Logs**: Audit trail for all activities
- **HTTPS**: Secure communication with App Runner

## Troubleshooting

### Common Issues

1. **Email Not Verified**: Check SES console and verify email address
2. **GitHub Access**: Ensure repository is public or configure access tokens
3. **Scheduler Not Working**: Check IAM permissions and service URL
4. **App Runner Build Failed**: Check Dockerfile and requirements.txt

### Debugging

```bash
# Check stack events
aws cloudformation describe-stack-events --stack-name ScheduledEmailReportsStack

# Check App Runner logs
aws logs tail /aws/apprunner/email-reports-service-xxxxxxxx --follow

# Test schedule manually
aws scheduler invoke --name daily-report-schedule-xxxxxxxx
```

## Cleanup

To destroy all resources:

```bash
cdk destroy
```

This will remove all AWS resources created by the stack, including:
- App Runner service
- EventBridge schedule
- IAM roles and policies
- CloudWatch resources
- SES email identity (verification status preserved)

## Development

### Local Testing

```bash
# Install dependencies
npm install

# Run tests
npm test

# Build TypeScript
npm run build

# Watch mode for development
npm run watch
```

### Code Structure

- `app.ts`: CDK application entry point
- `lib/scheduled-email-reports-stack.ts`: Main stack definition
- `test/`: Unit tests (if implemented)

## Support

For issues related to:
- AWS CDK: [CDK Documentation](https://docs.aws.amazon.com/cdk/)
- App Runner: [App Runner Documentation](https://docs.aws.amazon.com/apprunner/)
- Amazon SES: [SES Documentation](https://docs.aws.amazon.com/ses/)
- EventBridge Scheduler: [Scheduler Documentation](https://docs.aws.amazon.com/eventbridge/latest/userguide/scheduler.html)