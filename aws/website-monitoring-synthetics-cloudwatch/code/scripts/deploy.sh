#!/bin/bash
set -e

# Website Monitoring with CloudWatch Synthetics - Deployment Script
# This script deploys a complete synthetic monitoring solution for website availability and performance

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Cleanup function for partial deployments
cleanup_on_error() {
    error "Deployment failed. Starting cleanup..."
    
    # Clean up temporary files
    rm -f synthetics-trust-policy.json canary-script.js canary-package.zip dashboard-config.json
    
    # Attempt to clean up AWS resources if they exist
    if [[ -n "$CANARY_NAME" ]]; then
        aws synthetics delete-canary --name "$CANARY_NAME" 2>/dev/null || true
    fi
    
    if [[ -n "$ROLE_ARN" ]]; then
        aws iam detach-role-policy \
            --role-name "SyntheticsCanaryRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchSyntheticsExecutionRolePolicy 2>/dev/null || true
        aws iam delete-role --role-name "SyntheticsCanaryRole-${RANDOM_SUFFIX}" 2>/dev/null || true
    fi
    
    if [[ -n "$S3_BUCKET" ]]; then
        aws s3 rm "s3://${S3_BUCKET}" --recursive 2>/dev/null || true
        aws s3 rb "s3://${S3_BUCKET}" 2>/dev/null || true
    fi
    
    if [[ -n "$SNS_TOPIC_ARN" ]]; then
        aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" 2>/dev/null || true
    fi
    
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

echo "=========================================="
echo "Website Monitoring with CloudWatch Synthetics"
echo "Deployment Script v1.0"
echo "=========================================="

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install AWS CLI v2.15 or later."
    exit 1
fi

# Check AWS CLI version
AWS_CLI_VERSION=$(aws --version 2>&1 | awk '{print $1}' | cut -d'/' -f2 | cut -d'.' -f1-2)
log "AWS CLI version: $AWS_CLI_VERSION"

# Check if user is authenticated
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS CLI is not configured or you don't have valid credentials."
    error "Please run 'aws configure' or set up your AWS credentials."
    exit 1
fi

# Get user input with defaults
echo ""
read -p "Enter the website URL to monitor (default: https://example.com): " input_url
WEBSITE_URL=${input_url:-"https://example.com"}

read -p "Enter your email for notifications (required): " NOTIFICATION_EMAIL
if [[ -z "$NOTIFICATION_EMAIL" ]]; then
    error "Email address is required for notifications"
    exit 1
fi

# Validate email format
if [[ ! "$NOTIFICATION_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    error "Invalid email format"
    exit 1
fi

read -p "Enter AWS region (default: current CLI region): " input_region
AWS_REGION=${input_region:-$(aws configure get region)}

if [[ -z "$AWS_REGION" ]]; then
    error "AWS region is required. Please specify a region or configure AWS CLI with a default region."
    exit 1
fi

# Set environment variables
export AWS_REGION
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))

# Set monitoring configuration
export CANARY_NAME="website-monitor-${RANDOM_SUFFIX}"
export S3_BUCKET="synthetics-artifacts-${RANDOM_SUFFIX}"

success "AWS environment configured for region: ${AWS_REGION}"
success "Canary name: ${CANARY_NAME}"
success "Account ID: ${AWS_ACCOUNT_ID}"

# Step 1: Create S3 Bucket for Canary Artifacts
log "Step 1: Creating S3 bucket for canary artifacts..."

# Check if bucket already exists
if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
    warn "S3 bucket ${S3_BUCKET} already exists. Using existing bucket."
else
    # Create S3 bucket for synthetics artifacts
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://${S3_BUCKET}"
    else
        aws s3 mb "s3://${S3_BUCKET}" --region "$AWS_REGION"
    fi
    
    # Enable versioning for artifact history
    aws s3api put-bucket-versioning \
        --bucket "$S3_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Configure lifecycle policy for cost optimization
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$S3_BUCKET" \
        --lifecycle-configuration '{
          "Rules": [{
            "ID": "SyntheticsArtifactRetention",
            "Status": "Enabled",
            "Filter": {"Prefix": ""},
            "Transitions": [{
              "Days": 30,
              "StorageClass": "STANDARD_IA"
            }],
            "Expiration": {"Days": 90}
          }]
        }'
fi

success "S3 bucket ready: ${S3_BUCKET}"

# Step 2: Create IAM Role for Synthetics Canary
log "Step 2: Creating IAM role for synthetics canary..."

# Check if role already exists
if aws iam get-role --role-name "SyntheticsCanaryRole-${RANDOM_SUFFIX}" &>/dev/null; then
    warn "IAM role SyntheticsCanaryRole-${RANDOM_SUFFIX} already exists. Using existing role."
    ROLE_ARN=$(aws iam get-role \
        --role-name "SyntheticsCanaryRole-${RANDOM_SUFFIX}" \
        --query 'Role.Arn' --output text)
else
    # Create trust policy for Synthetics service
    cat > synthetics-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create IAM role for canary execution
    aws iam create-role \
        --role-name "SyntheticsCanaryRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document file://synthetics-trust-policy.json
    
    # Attach AWS managed policy for Synthetics execution
    aws iam attach-role-policy \
        --role-name "SyntheticsCanaryRole-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchSyntheticsExecutionRolePolicy
    
    # Wait for role to be ready
    log "Waiting for IAM role to be ready..."
    sleep 10
    
    # Get the role ARN for canary creation
    ROLE_ARN=$(aws iam get-role \
        --role-name "SyntheticsCanaryRole-${RANDOM_SUFFIX}" \
        --query 'Role.Arn' --output text)
fi

success "IAM role ready: ${ROLE_ARN}"

# Step 3: Create Website Monitoring Canary Script
log "Step 3: Creating website monitoring canary script..."

# Create canary script for website monitoring
cat > canary-script.js << 'EOF'
const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');

const checkWebsite = async function () {
    let page = await synthetics.getPage();
    
    // Navigate to website with performance monitoring
    const response = await synthetics.executeStepFunction('loadHomepage', async function () {
        return await page.goto(synthetics.getConfiguration().getUrl(), {
            waitUntil: 'networkidle0',
            timeout: 30000
        });
    });
    
    // Verify successful response
    if (response.status() < 200 || response.status() > 299) {
        throw new Error(`Failed to load page: ${response.status()}`);
    }
    
    // Check for critical page elements
    await synthetics.executeStepFunction('verifyPageElements', async function () {
        await page.waitForSelector('body', { timeout: 10000 });
        
        // Verify page title exists
        const title = await page.title();
        if (!title || title.length === 0) {
            throw new Error('Page title is missing');
        }
        
        log.info(`Page title: ${title}`);
        
        // Check for JavaScript errors
        const errors = await page.evaluate(() => {
            return window.console.errors || [];
        });
        
        if (errors.length > 0) {
            log.warn(`JavaScript errors detected: ${errors.length}`);
        }
    });
    
    // Capture performance metrics
    await synthetics.executeStepFunction('captureMetrics', async function () {
        const metrics = await page.evaluate(() => {
            const navigation = performance.getEntriesByType('navigation')[0];
            return {
                loadTime: navigation.loadEventEnd - navigation.loadEventStart,
                domContentLoaded: navigation.domContentLoadedEventEnd - navigation.domContentLoadedEventStart,
                responseTime: navigation.responseEnd - navigation.requestStart
            };
        });
        
        // Log custom metrics
        log.info(`Load time: ${metrics.loadTime}ms`);
        log.info(`DOM content loaded: ${metrics.domContentLoaded}ms`);
        log.info(`Response time: ${metrics.responseTime}ms`);
        
        // Set custom CloudWatch metrics
        await synthetics.addUserAgentMetric('LoadTime', metrics.loadTime, 'Milliseconds');
        await synthetics.addUserAgentMetric('ResponseTime', metrics.responseTime, 'Milliseconds');
    });
};

exports.handler = async () => {
    return await synthetics.executeStep('checkWebsite', checkWebsite);
};
EOF

# Create ZIP package for canary deployment
if command -v zip &> /dev/null; then
    zip canary-package.zip canary-script.js
else
    # Alternative for systems without zip
    tar -czf canary-package.zip canary-script.js
fi

success "Canary script created and packaged"

# Step 4: Deploy CloudWatch Synthetics Canary
log "Step 4: Deploying CloudWatch Synthetics canary..."

# Check if canary already exists
if aws synthetics get-canary --name "$CANARY_NAME" &>/dev/null; then
    warn "Canary ${CANARY_NAME} already exists. Updating configuration..."
    # Update existing canary
    aws synthetics update-canary \
        --name "$CANARY_NAME" \
        --runtime-version syn-nodejs-puppeteer-10.0 \
        --execution-role-arn "$ROLE_ARN" \
        --schedule '{
          "Expression": "rate(5 minutes)",
          "DurationInSeconds": 0
        }' \
        --code '{
          "Handler": "canary-script.handler",
          "ZipFile": "'$(base64 -w 0 canary-package.zip 2>/dev/null || base64 -i canary-package.zip)'"
        }' \
        --artifact-s3-location "s3://${S3_BUCKET}/canary-artifacts" \
        --run-config '{
          "TimeoutInSeconds": 60,
          "MemoryInMB": 960,
          "ActiveTracing": true,
          "EnvironmentVariables": {
            "URL": "'"$WEBSITE_URL"'"
          }
        }' \
        --success-retention-period-in-days 31 \
        --failure-retention-period-in-days 31
else
    # Create the synthetics canary
    aws synthetics create-canary \
        --name "$CANARY_NAME" \
        --runtime-version syn-nodejs-puppeteer-10.0 \
        --execution-role-arn "$ROLE_ARN" \
        --schedule '{
          "Expression": "rate(5 minutes)",
          "DurationInSeconds": 0
        }' \
        --code '{
          "Handler": "canary-script.handler",
          "ZipFile": "'$(base64 -w 0 canary-package.zip 2>/dev/null || base64 -i canary-package.zip)'"
        }' \
        --artifact-s3-location "s3://${S3_BUCKET}/canary-artifacts" \
        --run-config '{
          "TimeoutInSeconds": 60,
          "MemoryInMB": 960,
          "ActiveTracing": true,
          "EnvironmentVariables": {
            "URL": "'"$WEBSITE_URL"'"
          }
        }' \
        --success-retention-period-in-days 31 \
        --failure-retention-period-in-days 31 \
        --tags '{
          "Purpose": "WebsiteMonitoring",
          "Environment": "Production",
          "CreatedBy": "SyntheticsRecipe"
        }'
fi

# Start the canary
aws synthetics start-canary --name "$CANARY_NAME" || true

success "Canary deployed and started: ${CANARY_NAME}"

# Step 5: Create CloudWatch Alarms for Monitoring
log "Step 5: Creating CloudWatch alarms for monitoring..."

# Create SNS topic for alerts
SNS_TOPIC_ARN=$(aws sns create-topic \
    --name "synthetics-alerts-${RANDOM_SUFFIX}" \
    --query 'TopicArn' --output text)

# Subscribe email to SNS topic
aws sns subscribe \
    --topic-arn "$SNS_TOPIC_ARN" \
    --protocol email \
    --notification-endpoint "$NOTIFICATION_EMAIL"

# Create alarm for canary failures
aws cloudwatch put-metric-alarm \
    --alarm-name "${CANARY_NAME}-FailureAlarm" \
    --alarm-description "Alert when website monitoring canary fails" \
    --metric-name SuccessPercent \
    --namespace CloudWatchSynthetics \
    --statistic Average \
    --period 300 \
    --threshold 90 \
    --comparison-operator LessThanThreshold \
    --evaluation-periods 2 \
    --alarm-actions "$SNS_TOPIC_ARN" \
    --dimensions Name=CanaryName,Value="$CANARY_NAME"

# Create alarm for high response times
aws cloudwatch put-metric-alarm \
    --alarm-name "${CANARY_NAME}-ResponseTimeAlarm" \
    --alarm-description "Alert when website response time is high" \
    --metric-name Duration \
    --namespace CloudWatchSynthetics \
    --statistic Average \
    --period 300 \
    --threshold 10000 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --alarm-actions "$SNS_TOPIC_ARN" \
    --dimensions Name=CanaryName,Value="$CANARY_NAME"

success "CloudWatch alarms created with SNS notifications"
warn "Check your email (${NOTIFICATION_EMAIL}) for SNS subscription confirmation"

# Step 6: Configure CloudWatch Dashboard
log "Step 6: Creating CloudWatch dashboard..."

# Create CloudWatch dashboard configuration
cat > dashboard-config.json << EOF
{
  "widgets": [
    {
      "type": "metric",
      "x": 0, "y": 0, "width": 12, "height": 6,
      "properties": {
        "metrics": [
          ["CloudWatchSynthetics", "SuccessPercent", "CanaryName", "${CANARY_NAME}"],
          [".", "Duration", ".", "."]
        ],
        "period": 300,
        "stat": "Average",
        "region": "${AWS_REGION}",
        "title": "Website Monitoring Overview",
        "yAxis": {"left": {"min": 0, "max": 100}}
      }
    },
    {
      "type": "metric",
      "x": 12, "y": 0, "width": 12, "height": 6,
      "properties": {
        "metrics": [
          ["CloudWatchSynthetics", "Failed", "CanaryName", "${CANARY_NAME}"],
          [".", "Passed", ".", "."]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "Test Results",
        "yAxis": {"left": {"min": 0}}
      }
    }
  ]
}
EOF

# Create the dashboard
aws cloudwatch put-dashboard \
    --dashboard-name "Website-Monitoring-${RANDOM_SUFFIX}" \
    --dashboard-body file://dashboard-config.json

success "CloudWatch dashboard created: Website-Monitoring-${RANDOM_SUFFIX}"

# Clean up temporary files
rm -f synthetics-trust-policy.json canary-script.js canary-package.zip dashboard-config.json

# Save deployment info for cleanup script
cat > .deployment-info << EOF
CANARY_NAME=${CANARY_NAME}
S3_BUCKET=${S3_BUCKET}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
SNS_TOPIC_ARN=${SNS_TOPIC_ARN}
AWS_REGION=${AWS_REGION}
DASHBOARD_NAME=Website-Monitoring-${RANDOM_SUFFIX}
EOF

echo ""
echo "=========================================="
echo "✅ DEPLOYMENT COMPLETED SUCCESSFULLY!"
echo "=========================================="
echo ""
echo "📊 Dashboard URL: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=Website-Monitoring-${RANDOM_SUFFIX}"
echo "🔍 Canary URL: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#synthetics:canary/detail/${CANARY_NAME}"
echo "📧 Email notifications will be sent to: ${NOTIFICATION_EMAIL}"
echo "🌐 Monitoring URL: ${WEBSITE_URL}"
echo ""
echo "The canary will run every 5 minutes and generate monitoring data."
echo "Check your email for SNS subscription confirmation."
echo ""
echo "To clean up all resources, run: ./destroy.sh"
echo ""