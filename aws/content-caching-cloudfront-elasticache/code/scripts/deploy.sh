#!/bin/bash

# Deploy script for Content Caching Strategies with CloudFront and ElastiCache
# This script deploys a multi-tier caching architecture using CloudFront and ElastiCache

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    
    # Remove any created files
    rm -f lambda_function.py lambda_function.zip index.html
    rm -f distribution-config.json bucket-policy.json
    rm -f test-invalidation.sh
    rm -rf redis* __pycache__
    
    # Optionally clean up AWS resources (uncomment if desired)
    # log_warning "To clean up AWS resources, run: ./destroy.sh"
    
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Header
echo -e "${BLUE}"
echo "=================================================="
echo "  Content Caching Strategies Deployment Script"
echo "  CloudFront + ElastiCache + Lambda + API Gateway"
echo "=================================================="
echo -e "${NC}"

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    log_error "jq is not installed. Please install it first."
    exit 1
fi

# Check if pip is installed
if ! command -v pip &> /dev/null; then
    log_error "pip is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

log_success "Prerequisites check passed"

# Set environment variables
log "Setting up environment variables..."
export AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    log_error "AWS region not configured. Please set a default region."
    exit 1
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

export BUCKET_NAME="cache-demo-${RANDOM_SUFFIX}"
export CACHE_CLUSTER_ID="demo-cache-${RANDOM_SUFFIX}"
export FUNCTION_NAME="cache-demo-${RANDOM_SUFFIX}"
export DISTRIBUTION_ID=""

log_success "Environment variables configured"
log "Using random suffix: ${RANDOM_SUFFIX}"
log "AWS Region: ${AWS_REGION}"
log "AWS Account ID: ${AWS_ACCOUNT_ID}"

# Cost warning
log_warning "This deployment will create AWS resources that incur charges:"
log_warning "- ElastiCache Redis cluster: ~$15-30/month"
log_warning "- CloudFront distribution: Based on usage"
log_warning "- Lambda executions: Based on usage"
log_warning "- API Gateway requests: Based on usage"
echo ""
read -p "Do you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Deployment cancelled by user"
    exit 0
fi

# Step 1: Create S3 bucket for static content
log "Step 1: Creating S3 bucket for static content..."
aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}

# Create sample static content
log "Creating sample HTML content..."
cat > index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Cache Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .api-result { background: #f0f0f0; padding: 20px; margin: 20px 0; }
        .header { background: #232f3e; color: white; padding: 20px; margin: -40px -40px 40px -40px; }
        .metrics { display: flex; gap: 20px; margin: 20px 0; }
        .metric { background: #fff; border: 1px solid #ddd; padding: 15px; border-radius: 5px; flex: 1; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Multi-Tier Caching Demo</h1>
        <p>Demonstrating CloudFront + ElastiCache integration</p>
    </div>
    
    <h2>Live API Data</h2>
    <div id="api-result" class="api-result">Loading data from API...</div>
    
    <div class="metrics">
        <div class="metric">
            <h3>Cache Status</h3>
            <div id="cache-status">Checking...</div>
        </div>
        <div class="metric">
            <h3>Response Time</h3>
            <div id="response-time">Measuring...</div>
        </div>
        <div class="metric">
            <h3>Data Source</h3>
            <div id="data-source">Unknown</div>
        </div>
    </div>
    
    <button onclick="refreshData()" style="padding: 10px 20px; background: #ff9900; color: white; border: none; border-radius: 3px; cursor: pointer;">Refresh Data</button>
    
    <script>
        async function fetchData() {
            const startTime = performance.now();
            try {
                const response = await fetch("/api/data");
                const data = await response.json();
                const endTime = performance.now();
                const responseTime = Math.round(endTime - startTime);
                
                document.getElementById("api-result").innerHTML = 
                    `<strong>API Response:</strong><br><pre>${JSON.stringify(data, null, 2)}</pre>`;
                
                document.getElementById("cache-status").textContent = 
                    data.cache_hit ? "Cache Hit ✅" : "Cache Miss ❌";
                document.getElementById("response-time").textContent = 
                    `${responseTime}ms`;
                document.getElementById("data-source").textContent = 
                    data.source || "Unknown";
                    
            } catch (error) {
                document.getElementById("api-result").innerHTML = 
                    `<strong>Error:</strong> ${error.message}`;
                document.getElementById("cache-status").textContent = "Error";
                document.getElementById("response-time").textContent = "N/A";
                document.getElementById("data-source").textContent = "Error";
            }
        }
        
        function refreshData() {
            document.getElementById("api-result").innerHTML = "Loading...";
            fetchData();
        }
        
        // Load data on page load
        fetchData();
        
        // Auto-refresh every 30 seconds
        setInterval(fetchData, 30000);
    </script>
</body>
</html>
EOF

aws s3 cp index.html s3://${BUCKET_NAME}/index.html --content-type "text/html"
log_success "S3 bucket and sample content created"

# Step 2: Create ElastiCache Redis Cluster
log "Step 2: Creating ElastiCache Redis cluster..."
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=is-default,Values=true" \
    --query "Vpcs[0].VpcId" --output text)

SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "Subnets[*].SubnetId" --output text)

# Create subnet group for ElastiCache
aws elasticache create-cache-subnet-group \
    --cache-subnet-group-name "${CACHE_CLUSTER_ID}-subnet-group" \
    --cache-subnet-group-description "Demo cache subnet group" \
    --subnet-ids ${SUBNET_IDS}

# Create ElastiCache Redis cluster
aws elasticache create-cache-cluster \
    --cache-cluster-id ${CACHE_CLUSTER_ID} \
    --cache-node-type cache.t3.micro \
    --engine redis \
    --num-cache-nodes 1 \
    --cache-subnet-group-name "${CACHE_CLUSTER_ID}-subnet-group" \
    --port 6379

log_success "ElastiCache cluster creation initiated"

# Step 3: Create IAM role for Lambda
log "Step 3: Creating IAM role for Lambda..."
aws iam create-role \
    --role-name "CacheDemoLambdaRole-${RANDOM_SUFFIX}" \
    --assume-role-policy-document '{
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
    }' > /dev/null

# Attach necessary policies
aws iam attach-role-policy \
    --role-name "CacheDemoLambdaRole-${RANDOM_SUFFIX}" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

aws iam attach-role-policy \
    --role-name "CacheDemoLambdaRole-${RANDOM_SUFFIX}" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"

log_success "Lambda IAM role created"

# Step 4: Create Lambda function code
log "Step 4: Creating Lambda function code..."
cat > lambda_function.py << 'EOF'
import json
import redis
import time
import os
from datetime import datetime

def lambda_handler(event, context):
    # ElastiCache endpoint (will be set via environment variable)
    redis_endpoint = os.environ.get('REDIS_ENDPOINT', 'localhost')
    
    try:
        # Connect to Redis
        r = redis.Redis(host=redis_endpoint, port=6379, decode_responses=True, socket_timeout=5)
        
        # Check if data exists in cache
        cache_key = "demo_data"
        cached_data = r.get(cache_key)
        
        if cached_data:
            # Return cached data
            data = json.loads(cached_data)
            data['cache_hit'] = True
            data['source'] = 'ElastiCache'
            data['retrieved_at'] = datetime.now().isoformat()
        else:
            # Simulate database query
            time.sleep(0.1)  # Simulate DB query time
            
            # Generate fresh data
            data = {
                'timestamp': datetime.now().isoformat(),
                'message': 'Hello from Lambda and ElastiCache!',
                'query_time': '100ms (simulated)',
                'cache_hit': False,
                'source': 'Database (simulated)',
                'retrieved_at': datetime.now().isoformat(),
                'random_value': int(time.time() * 1000) % 10000
            }
            
            # Cache the data for 5 minutes
            r.setex(cache_key, 300, json.dumps(data))
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Cache-Control': 'public, max-age=60',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps(data, indent=2)
        }
        
    except redis.RedisError as e:
        # Redis connection failed, fallback to direct response
        fallback_data = {
            'timestamp': datetime.now().isoformat(),
            'message': 'Fallback response (Redis unavailable)',
            'error': f'Redis connection failed: {str(e)}',
            'cache_hit': False,
            'source': 'Lambda (no cache)',
            'retrieved_at': datetime.now().isoformat()
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Cache-Control': 'no-cache',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps(fallback_data, indent=2)
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': str(e),
                'message': 'Internal server error',
                'timestamp': datetime.now().isoformat()
            })
        }
EOF

# Package Lambda function
log "Packaging Lambda function..."
pip install redis -t . --quiet
zip -r lambda_function.zip lambda_function.py redis* > /dev/null
log_success "Lambda function package created"

# Step 5: Wait for ElastiCache and deploy Lambda
log "Step 5: Waiting for ElastiCache cluster to be available..."
aws elasticache wait cache-cluster-available --cache-cluster-id ${CACHE_CLUSTER_ID}

# Get ElastiCache endpoint
REDIS_ENDPOINT=$(aws elasticache describe-cache-clusters \
    --cache-cluster-id ${CACHE_CLUSTER_ID} \
    --show-cache-node-info \
    --query "CacheClusters[0].CacheNodes[0].Endpoint.Address" \
    --output text)

# Get default security group for VPC access
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
        "Name=group-name,Values=default" \
    --query "SecurityGroups[0].GroupId" --output text)

# Create Lambda function
ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/CacheDemoLambdaRole-${RANDOM_SUFFIX}"

log "Creating Lambda function..."
aws lambda create-function \
    --function-name ${FUNCTION_NAME} \
    --runtime python3.9 \
    --role ${ROLE_ARN} \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://lambda_function.zip \
    --environment "Variables={REDIS_ENDPOINT=${REDIS_ENDPOINT}}" \
    --vpc-config "SubnetIds=${SUBNET_IDS// /,},SecurityGroupIds=${SECURITY_GROUP_ID}" \
    --timeout 30 \
    --description "Cache demo function with ElastiCache integration" > /dev/null

log_success "Lambda function deployed with ElastiCache integration"

# Step 6: Create API Gateway
log "Step 6: Creating API Gateway..."
API_ID=$(aws apigatewayv2 create-api \
    --name "cache-demo-api-${RANDOM_SUFFIX}" \
    --protocol-type HTTP \
    --description "API for cache demo" \
    --query "ApiId" --output text)

# Create Lambda integration
INTEGRATION_ID=$(aws apigatewayv2 create-integration \
    --api-id ${API_ID} \
    --integration-type AWS_PROXY \
    --integration-uri "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${FUNCTION_NAME}" \
    --payload-format-version "2.0" \
    --query "IntegrationId" --output text)

# Create route
aws apigatewayv2 create-route \
    --api-id ${API_ID} \
    --route-key "GET /api/data" \
    --target "integrations/${INTEGRATION_ID}" > /dev/null

# Create OPTIONS route for CORS
aws apigatewayv2 create-route \
    --api-id ${API_ID} \
    --route-key "OPTIONS /api/data" \
    --target "integrations/${INTEGRATION_ID}" > /dev/null

# Create deployment
aws apigatewayv2 create-deployment \
    --api-id ${API_ID} \
    --stage-name "prod" \
    --description "Production deployment" > /dev/null

# Add Lambda permission for API Gateway
aws lambda add-permission \
    --function-name ${FUNCTION_NAME} \
    --statement-id "api-gateway-invoke-${RANDOM_SUFFIX}" \
    --action "lambda:InvokeFunction" \
    --principal "apigateway.amazonaws.com" \
    --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*" > /dev/null

API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
log_success "API Gateway created: ${API_ENDPOINT}"

# Step 7: Create CloudFront Origin Access Control
log "Step 7: Creating CloudFront distribution..."
OAC_ID=$(aws cloudfront create-origin-access-control \
    --origin-access-control-config '{
      "Name": "S3-OAC-'${RANDOM_SUFFIX}'",
      "Description": "OAC for S3 bucket access",
      "OriginAccessControlOriginType": "s3",
      "SigningBehavior": "always",
      "SigningProtocol": "sigv4"
    }' \
    --query "OriginAccessControl.Id" --output text)

# Create CloudFront distribution configuration
cat > distribution-config.json << EOF
{
  "CallerReference": "cache-demo-${RANDOM_SUFFIX}",
  "Comment": "Multi-tier caching demo - CloudFront + ElastiCache",
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-${BUCKET_NAME}",
    "ViewerProtocolPolicy": "redirect-to-https",
    "MinTTL": 0,
    "ForwardedValues": {
      "QueryString": false,
      "Cookies": {
        "Forward": "none"
      }
    },
    "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  },
  "Origins": [
    {
      "Id": "S3-${BUCKET_NAME}",
      "DomainName": "${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com",
      "OriginAccessControlId": "${OAC_ID}",
      "S3OriginConfig": {
        "OriginAccessIdentity": ""
      }
    },
    {
      "Id": "API-${API_ID}",
      "DomainName": "${API_ID}.execute-api.${AWS_REGION}.amazonaws.com",
      "OriginPath": "/prod",
      "CustomOriginConfig": {
        "HTTPPort": 443,
        "HTTPSPort": 443,
        "OriginProtocolPolicy": "https-only"
      }
    }
  ],
  "CacheBehaviors": [
    {
      "PathPattern": "/api/*",
      "TargetOriginId": "API-${API_ID}",
      "ViewerProtocolPolicy": "redirect-to-https",
      "MinTTL": 0,
      "ForwardedValues": {
        "QueryString": true,
        "Cookies": {
          "Forward": "none"
        }
      },
      "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    }
  ],
  "Enabled": true,
  "PriceClass": "PriceClass_100"
}
EOF

# Create CloudFront distribution
DISTRIBUTION_ID=$(aws cloudfront create-distribution \
    --distribution-config file://distribution-config.json \
    --query "Distribution.Id" --output text)

log_success "CloudFront distribution created: ${DISTRIBUTION_ID}"

# Step 8: Configure S3 bucket policy for CloudFront
log "Step 8: Configuring S3 bucket policy..."
DIST_ARN="arn:aws:cloudfront::${AWS_ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"

cat > bucket-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "${DIST_ARN}"
        }
      }
    }
  ]
}
EOF

aws s3api put-bucket-policy \
    --bucket ${BUCKET_NAME} \
    --policy file://bucket-policy.json

log_success "S3 bucket policy configured"

# Step 9: Create monitoring and testing resources
log "Step 9: Setting up monitoring and testing..."

# Create CloudWatch log group
aws logs create-log-group \
    --log-group-name "/aws/cloudfront/cache-demo-${RANDOM_SUFFIX}" 2>/dev/null || true

# Create CloudWatch alarm for cache hit ratio
aws cloudwatch put-metric-alarm \
    --alarm-name "CloudFront-CacheHitRatio-Low-${RANDOM_SUFFIX}" \
    --alarm-description "Alert when cache hit ratio is low" \
    --metric-name "CacheHitRate" \
    --namespace "AWS/CloudFront" \
    --statistic "Average" \
    --period 300 \
    --threshold 80 \
    --comparison-operator "LessThanThreshold" \
    --evaluation-periods 2 \
    --dimensions Name=DistributionId,Value=${DISTRIBUTION_ID} > /dev/null

# Create cache invalidation test script
cat > test-invalidation.sh << EOF
#!/bin/bash
echo "Testing cache invalidation..."

# Create invalidation
INVALIDATION_ID=\$(aws cloudfront create-invalidation \\
    --distribution-id ${DISTRIBUTION_ID} \\
    --paths "/api/*" \\
    --query "Invalidation.Id" --output text)

echo "Invalidation created: \${INVALIDATION_ID}"

# Monitor invalidation status
aws cloudfront wait invalidation-completed \\
    --distribution-id ${DISTRIBUTION_ID} \\
    --id \${INVALIDATION_ID}

echo "✅ Cache invalidation completed"
EOF

chmod +x test-invalidation.sh

log_success "Monitoring and testing resources created"

# Get CloudFront distribution domain name
DOMAIN_NAME=$(aws cloudfront get-distribution \
    --id ${DISTRIBUTION_ID} \
    --query "Distribution.DomainName" --output text)

# Save deployment information
cat > deployment-info.txt << EOF
Deployment Information
=====================

Resources Created:
- S3 Bucket: ${BUCKET_NAME}
- ElastiCache Cluster: ${CACHE_CLUSTER_ID}
- Lambda Function: ${FUNCTION_NAME}
- API Gateway: ${API_ID}
- CloudFront Distribution: ${DISTRIBUTION_ID}
- IAM Role: CacheDemoLambdaRole-${RANDOM_SUFFIX}

Endpoints:
- CloudFront URL: https://${DOMAIN_NAME}
- API Gateway URL: ${API_ENDPOINT}

Redis Endpoint: ${REDIS_ENDPOINT}

Files Created:
- test-invalidation.sh (cache invalidation testing)
- deployment-info.txt (this file)

Next Steps:
1. Wait 10-15 minutes for CloudFront deployment to complete
2. Visit https://${DOMAIN_NAME} to test the caching demo
3. Monitor cache performance in CloudWatch
4. Use test-invalidation.sh to test cache invalidation

Cleanup:
Run ./destroy.sh to remove all resources
EOF

# Final success message
echo ""
log_success "🎉 Deployment completed successfully!"
echo ""
echo -e "${GREEN}📋 Deployment Summary:${NC}"
echo -e "   S3 Bucket: ${BUCKET_NAME}"
echo -e "   ElastiCache: ${CACHE_CLUSTER_ID}"
echo -e "   Lambda: ${FUNCTION_NAME}"
echo -e "   API Gateway: ${API_ENDPOINT}"
echo -e "   CloudFront: https://${DOMAIN_NAME}"
echo ""
echo -e "${YELLOW}⏳ Important Notes:${NC}"
echo -e "   • CloudFront deployment takes 10-15 minutes to complete"
echo -e "   • Visit https://${DOMAIN_NAME} to test the caching demo"
echo -e "   • View deployment details in deployment-info.txt"
echo -e "   • Run ./destroy.sh when finished to avoid charges"
echo ""
echo -e "${BLUE}🔍 Testing:${NC}"
echo -e "   • Test API directly: curl ${API_ENDPOINT}/api/data"
echo -e "   • Run cache invalidation: ./test-invalidation.sh"
echo -e "   • Monitor in CloudWatch console"
echo ""

# Cleanup temporary files
rm -f lambda_function.py lambda_function.zip index.html
rm -f distribution-config.json bucket-policy.json
rm -rf redis* __pycache__

log_success "Deployment script completed"