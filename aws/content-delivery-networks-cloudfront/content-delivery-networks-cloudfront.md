---
title: Content Delivery Networks with CloudFront
id: q3c7d1e9
category: networking
difficulty: 400
subject: aws
services: CloudFront, S3, Lambda, WAF
estimated-time: 200 minutes
recipe-version: 1.3
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: cloudfront, cdn, content-delivery, lambda-edge, advanced-networking
recipe-generator-version: 1.3
---

# Content Delivery Networks with CloudFront

## Problem

Global enterprises need sophisticated content delivery networks that can handle multiple content origins, implement real-time content manipulation, provide advanced security controls, and deliver granular performance insights. Traditional CDN solutions often fall short when organizations require edge computing capabilities, dynamic content transformation, comprehensive security policies, and detailed analytics for optimizing user experience across diverse geographical locations and device types.

## Solution

Build an advanced CloudFront distribution architecture that integrates multiple origins, implements Lambda@Edge functions for dynamic content processing, utilizes CloudFront Functions for lightweight transformations, incorporates AWS WAF for security, and provides comprehensive monitoring through CloudWatch. This solution enables real-time content manipulation, advanced caching strategies, security controls, and detailed performance analytics.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Users"
        U1[Global Users]
        U2[Mobile Users]
        U3[API Clients]
    end
    
    subgraph "CloudFront Edge"
        CF[CloudFront Distribution]
        CFF[CloudFront Functions]
        LEF[Lambda@Edge Functions]
        WAF[AWS WAF]
    end
    
    subgraph "Origins"
        S3[S3 Static Content]
        ALB[Application Load Balancer]
        API[API Gateway]
        CUSTOM[Custom Origin]
    end
    
    subgraph "Security & Monitoring"
        SM[AWS Secrets Manager]
        CW[CloudWatch]
        RT[Real-time Logs]
        KVS[CloudFront KeyValueStore]
    end
    
    U1 --> CF
    U2 --> CF
    U3 --> CF
    
    CF --> CFF
    CF --> LEF
    CF --> WAF
    
    CF --> S3
    CF --> ALB
    CF --> API
    CF --> CUSTOM
    
    LEF --> SM
    CF --> CW
    CF --> RT
    CFF --> KVS
    
    style CF fill:#FF9900
    style WAF fill:#FF6B6B
    style LEF fill:#4ECDC4
    style CFF fill:#45B7D1
```

## Prerequisites

1. AWS account with CloudFront, Lambda, S3, and WAF permissions
2. AWS CLI v2 installed and configured (or AWS CloudShell)
3. Basic knowledge of JavaScript and HTTP protocols
4. Understanding of CDN concepts and edge computing
5. Estimated cost: $50-100/month for testing (varies by traffic volume)

> **Note**: This recipe creates resources that may incur charges. Lambda@Edge functions have additional costs for execution time and requests.

## Preparation

```bash
# Set environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 8 --require-each-included-type \
    --output text --query RandomPassword)

export CDN_PROJECT_NAME="advanced-cdn-${RANDOM_SUFFIX}"
export S3_BUCKET_NAME="cdn-content-${RANDOM_SUFFIX}"
export LAMBDA_FUNCTION_NAME="cdn-edge-processor-${RANDOM_SUFFIX}"
export WAF_WEBACL_NAME="cdn-security-${RANDOM_SUFFIX}"
export CLOUDFRONT_FUNCTION_NAME="cdn-request-processor-${RANDOM_SUFFIX}"

# Create S3 bucket for static content
aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}

# Create sample content for testing
mkdir -p /tmp/cdn-content/api
echo '<html><body><h1>Main Site</h1><p>Version: 1.0</p></body></html>' \
    > /tmp/cdn-content/index.html
echo '<html><body><h1>API Documentation</h1><p>Version: 2.0</p></body></html>' \
    > /tmp/cdn-content/api/index.html
echo '{"message": "Hello from API", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'"}' \
    > /tmp/cdn-content/api/status.json

# Upload content to S3
aws s3 cp /tmp/cdn-content s3://${S3_BUCKET_NAME}/ --recursive

echo "✅ Environment prepared with bucket: ${S3_BUCKET_NAME}"
```

## Steps

1. **Create CloudFront Function for Request Processing**:

   CloudFront Functions execute at the edge for lightweight request/response processing with sub-millisecond execution times. They're ideal for cache key normalization, header manipulation, and simple redirects without the overhead of Lambda@Edge. This function removes tracking parameters to improve cache hit ratios and handles basic URL redirects, demonstrating edge-based request processing.

   ```bash
   # Create CloudFront Function for header manipulation
   cat > /tmp/cloudfront-function.js << 'EOF'
   function handler(event) {
       var request = event.request;
       var headers = request.headers;
       
       // Add security headers
       headers['x-forwarded-proto'] = {value: 'https'};
       headers['x-request-id'] = {value: generateRequestId()};
       
       // Normalize cache key by removing specific query parameters
       var uri = request.uri;
       var querystring = request.querystring;
       
       // Remove tracking parameters to improve cache hit ratio
       delete querystring.utm_source;
       delete querystring.utm_medium;
       delete querystring.utm_campaign;
       delete querystring.fbclid;
       
       // Redirect old paths to new structure
       if (uri.startsWith('/old-api/')) {
           uri = uri.replace('/old-api/', '/api/');
           request.uri = uri;
       }
       
       return request;
   }
   
   function generateRequestId() {
       return 'req-' + Math.random().toString(36).substr(2, 9);
   }
   EOF
   
   # Create CloudFront Function
   aws cloudfront create-function \
       --name ${CLOUDFRONT_FUNCTION_NAME} \
       --function-config Comment="Request processing function",Runtime="cloudfront-js-2.0" \
       --function-code fileb:///tmp/cloudfront-function.js
   
   # Get function details
   FUNCTION_ETAG=$(aws cloudfront describe-function \
       --name ${CLOUDFRONT_FUNCTION_NAME} \
       --query 'ETag' --output text)
   
   # Publish the function
   aws cloudfront publish-function \
       --name ${CLOUDFRONT_FUNCTION_NAME} \
       --if-match ${FUNCTION_ETAG}
   
   echo "✅ CloudFront Function created and published"
   ```

   The function uses the cloudfront-js-2.0 runtime for enhanced capabilities and removes tracking parameters to improve cache hit ratios. Publishing makes the function available for association with distribution behaviors, enabling edge-based request processing.

2. **Create Lambda@Edge Function for Advanced Processing**:

   Lambda@Edge functions run at edge locations and provide full programming language capabilities for complex request/response processing. They're perfect for security header injection, content personalization, and API integrations that require more processing power than CloudFront Functions. This implementation demonstrates comprehensive security header injection for enhanced protection.

   ```bash
   # Create Lambda@Edge function for response manipulation
   mkdir -p /tmp/lambda-edge
   cat > /tmp/lambda-edge/index.js << 'EOF'
   const aws = require('aws-sdk');
   
   exports.handler = async (event, context) => {
       const response = event.Records[0].cf.response;
       const request = event.Records[0].cf.request;
       const headers = response.headers;
       
       // Add comprehensive security headers
       headers['strict-transport-security'] = [{
           key: 'Strict-Transport-Security',
           value: 'max-age=31536000; includeSubDomains; preload'
       }];
       
       headers['x-content-type-options'] = [{
           key: 'X-Content-Type-Options',
           value: 'nosniff'
       }];
       
       headers['x-frame-options'] = [{
           key: 'X-Frame-Options',
           value: 'SAMEORIGIN'
       }];
       
       headers['x-xss-protection'] = [{
           key: 'X-XSS-Protection',
           value: '1; mode=block'
       }];
       
       headers['referrer-policy'] = [{
           key: 'Referrer-Policy',
           value: 'strict-origin-when-cross-origin'
       }];
       
       headers['content-security-policy'] = [{
           key: 'Content-Security-Policy',
           value: "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
       }];
       
       // Add custom headers based on request path
       if (request.uri.startsWith('/api/')) {
           headers['access-control-allow-origin'] = [{
               key: 'Access-Control-Allow-Origin',
               value: '*'
           }];
           headers['access-control-allow-methods'] = [{
               key: 'Access-Control-Allow-Methods',
               value: 'GET, POST, OPTIONS, PUT, DELETE'
           }];
           headers['access-control-allow-headers'] = [{
               key: 'Access-Control-Allow-Headers',
               value: 'Content-Type, Authorization, X-Requested-With'
           }];
       }
       
       // Add performance headers
       headers['x-edge-location'] = [{
           key: 'X-Edge-Location',
           value: event.Records[0].cf.config.distributionId
       }];
       
       headers['x-cache-status'] = [{
           key: 'X-Cache-Status',
           value: 'PROCESSED'
       }];
       
       return response;
   };
   EOF
   
   # Create deployment package
   cd /tmp/lambda-edge
   zip -r lambda-edge.zip index.js
   
   # Create IAM role for Lambda@Edge
   cat > /tmp/lambda-edge-trust-policy.json << 'EOF'
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Effect": "Allow",
               "Principal": {
                   "Service": [
                       "lambda.amazonaws.com",
                       "edgelambda.amazonaws.com"
                   ]
               },
               "Action": "sts:AssumeRole"
           }
       ]
   }
   EOF
   
   # Create the role
   aws iam create-role \
       --role-name ${LAMBDA_FUNCTION_NAME}-role \
       --assume-role-policy-document file:///tmp/lambda-edge-trust-policy.json
   
   # Attach basic execution policy
   aws iam attach-role-policy \
       --role-name ${LAMBDA_FUNCTION_NAME}-role \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   
   # Wait for role to be available
   sleep 10
   
   # Create Lambda function in us-east-1 (required for Lambda@Edge)
   aws lambda create-function \
       --region us-east-1 \
       --function-name ${LAMBDA_FUNCTION_NAME} \
       --runtime nodejs20.x \
       --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_FUNCTION_NAME}-role \
       --handler index.handler \
       --zip-file fileb:///tmp/lambda-edge/lambda-edge.zip \
       --timeout 5 \
       --memory-size 128
   
   # Get function version (required for Lambda@Edge)
   LAMBDA_VERSION=$(aws lambda publish-version \
       --region us-east-1 \
       --function-name ${LAMBDA_FUNCTION_NAME} \
       --query 'Version' --output text)
   
   export LAMBDA_ARN="arn:aws:lambda:us-east-1:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}:${LAMBDA_VERSION}"
   
   echo "✅ Lambda@Edge function created with ARN: ${LAMBDA_ARN}"
   ```

   Lambda@Edge functions must be created in us-east-1 and require a published version (not $LATEST) for CloudFront association. The function uses nodejs20.x runtime and adds comprehensive security headers to all responses, improving the security posture of delivered content. For additional implementation examples, see the [Lambda@Edge example functions documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/lambda-examples.html).

3. **Create WAF Web ACL for Security**:

   AWS WAF provides application-layer protection by filtering malicious requests before they reach your origins. The Web ACL combines managed rule sets for common vulnerabilities with custom rate limiting to protect against various attack vectors. This configuration implements enterprise-grade security controls at the edge, protecting against OWASP Top 10 vulnerabilities and sophisticated attack patterns.

   ```bash
   # Create WAF Web ACL with comprehensive rules
   cat > /tmp/waf-webacl.json << 'EOF'
   {
       "Name": "WAF_WEB_ACL_NAME_PLACEHOLDER",
       "Scope": "CLOUDFRONT",
       "DefaultAction": {
           "Allow": {}
       },
       "Rules": [
           {
               "Name": "AWSManagedRulesCommonRuleSet",
               "Priority": 1,
               "OverrideAction": {
                   "None": {}
               },
               "Statement": {
                   "ManagedRuleGroupStatement": {
                       "VendorName": "AWS",
                       "Name": "AWSManagedRulesCommonRuleSet"
                   }
               },
               "VisibilityConfig": {
                   "SampledRequestsEnabled": true,
                   "CloudWatchMetricsEnabled": true,
                   "MetricName": "CommonRuleSetMetric"
               }
           },
           {
               "Name": "AWSManagedRulesKnownBadInputsRuleSet",
               "Priority": 2,
               "OverrideAction": {
                   "None": {}
               },
               "Statement": {
                   "ManagedRuleGroupStatement": {
                       "VendorName": "AWS",
                       "Name": "AWSManagedRulesKnownBadInputsRuleSet"
                   }
               },
               "VisibilityConfig": {
                   "SampledRequestsEnabled": true,
                   "CloudWatchMetricsEnabled": true,
                   "MetricName": "KnownBadInputsRuleSetMetric"
               }
           },
           {
               "Name": "RateLimitRule",
               "Priority": 3,
               "Action": {
                   "Block": {}
               },
               "Statement": {
                   "RateBasedStatement": {
                       "Limit": 2000,
                       "AggregateKeyType": "IP"
                   }
               },
               "VisibilityConfig": {
                   "SampledRequestsEnabled": true,
                   "CloudWatchMetricsEnabled": true,
                   "MetricName": "RateLimitRuleMetric"
               }
           }
       ],
       "VisibilityConfig": {
           "SampledRequestsEnabled": true,
           "CloudWatchMetricsEnabled": true,
           "MetricName": "WAF_WEB_ACL_NAME_PLACEHOLDER"
       }
   }
   EOF
   
   # Replace placeholder with actual name
   sed -i.bak "s/WAF_WEB_ACL_NAME_PLACEHOLDER/${WAF_WEBACL_NAME}/g" \
       /tmp/waf-webacl.json
   
   # Create WAF Web ACL
   WAF_WEBACL_ID=$(aws wafv2 create-web-acl \
       --cli-input-json file:///tmp/waf-webacl.json \
       --query 'Summary.Id' --output text)
   
   export WAF_WEBACL_ARN="arn:aws:wafv2:us-east-1:${AWS_ACCOUNT_ID}:global/webacl/${WAF_WEBACL_NAME}/${WAF_WEBACL_ID}"
   
   echo "✅ WAF Web ACL created with ID: ${WAF_WEBACL_ID}"
   ```

   The Web ACL includes managed rule sets for common vulnerabilities (OWASP Top 10), known bad inputs, and a rate-limiting rule set to 2000 requests per IP per 5-minute window. These rules provide comprehensive protection against most web application attacks. For detailed information about WAF integration patterns, see the [AWS WAF with CloudFront documentation](https://docs.aws.amazon.com/waf/latest/developerguide/cloudfront-features.html).

4. **Create Origin Access Control for S3**:

   Origin Access Control (OAC) secures S3 origins by ensuring only CloudFront can access bucket content. OAC supports all S3 features including SSE-KMS encryption and is the recommended replacement for the legacy Origin Access Identity (OAI). This implementation provides enhanced security for S3 content delivery through CloudFront.

   ```bash
   # Create Origin Access Control
   cat > /tmp/oac-config.json << 'EOF'
   {
       "Name": "OAC_NAME_PLACEHOLDER",
       "OriginAccessControlConfig": {
           "Name": "OAC_NAME_PLACEHOLDER",
           "Description": "Origin Access Control for S3 bucket",
           "SigningProtocol": "sigv4",
           "SigningBehavior": "always",
           "OriginAccessControlOriginType": "s3"
       }
   }
   EOF
   
   # Replace placeholder
   sed -i.bak "s/OAC_NAME_PLACEHOLDER/${CDN_PROJECT_NAME}-oac/g" \
       /tmp/oac-config.json
   
   # Create OAC
   OAC_ID=$(aws cloudfront create-origin-access-control \
       --origin-access-control-config file:///tmp/oac-config.json \
       --query 'OriginAccessControl.Id' --output text)
   
   export OAC_ID
   
   echo "✅ Origin Access Control created with ID: ${OAC_ID}"
   ```

   The OAC uses AWS SigV4 signing for secure authentication with S3, providing better security than the legacy OAI approach. This ensures that direct access to S3 bucket URLs is blocked while maintaining CloudFront access. For comprehensive guidance on S3 access restrictions, see the [CloudFront S3 origin access control documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html).

5. **Create Advanced CloudFront Distribution**:

   This step creates a sophisticated CloudFront distribution with multiple origins, custom cache behaviors, and integrated edge functions. The distribution demonstrates advanced CDN patterns including origin failover, content-based routing, and security integration. The configuration enables HTTP/2 and HTTP/3 support for optimal performance.

   ```bash
   # Get CloudFront Function ARN
   CLOUDFRONT_FUNCTION_ARN=$(aws cloudfront describe-function \
       --name ${CLOUDFRONT_FUNCTION_NAME} \
       --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)
   
   # Create comprehensive distribution configuration
   cat > /tmp/distribution-config.json << 'EOF'
   {
       "CallerReference": "CALLER_REF_PLACEHOLDER",
       "Comment": "Advanced CDN with multiple origins and edge functions",
       "Enabled": true,
       "Origins": {
           "Quantity": 2,
           "Items": [
               {
                   "Id": "S3Origin",
                   "DomainName": "S3_BUCKET_PLACEHOLDER.s3.amazonaws.com",
                   "OriginPath": "",
                   "CustomHeaders": {
                       "Quantity": 0
                   },
                   "S3OriginConfig": {
                       "OriginAccessIdentity": ""
                   },
                   "OriginAccessControlId": "OAC_ID_PLACEHOLDER",
                   "ConnectionAttempts": 3,
                   "ConnectionTimeout": 10,
                   "OriginShield": {
                       "Enabled": false
                   }
               },
               {
                   "Id": "CustomOrigin",
                   "DomainName": "httpbin.org",
                   "OriginPath": "",
                   "CustomHeaders": {
                       "Quantity": 0
                   },
                   "CustomOriginConfig": {
                       "HTTPPort": 80,
                       "HTTPSPort": 443,
                       "OriginProtocolPolicy": "https-only",
                       "OriginSslProtocols": {
                           "Quantity": 1,
                           "Items": ["TLSv1.2"]
                       },
                       "OriginReadTimeout": 30,
                       "OriginKeepaliveTimeout": 5
                   },
                   "ConnectionAttempts": 3,
                   "ConnectionTimeout": 10,
                   "OriginShield": {
                       "Enabled": false
                   }
               }
           ]
       },
       "DefaultCacheBehavior": {
           "TargetOriginId": "S3Origin",
           "ViewerProtocolPolicy": "redirect-to-https",
           "TrustedSigners": {
               "Enabled": false,
               "Quantity": 0
           },
           "TrustedKeyGroups": {
               "Enabled": false,
               "Quantity": 0
           },
           "AllowedMethods": {
               "Quantity": 7,
               "Items": ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"],
               "CachedMethods": {
                   "Quantity": 2,
                   "Items": ["GET", "HEAD"]
               }
           },
           "SmoothStreaming": false,
           "Compress": true,
           "LambdaFunctionAssociations": {
               "Quantity": 1,
               "Items": [
                   {
                       "LambdaFunctionARN": "LAMBDA_ARN_PLACEHOLDER",
                       "EventType": "origin-response",
                       "IncludeBody": false
                   }
               ]
           },
           "FunctionAssociations": {
               "Quantity": 1,
               "Items": [
                   {
                       "FunctionARN": "CLOUDFRONT_FUNCTION_ARN_PLACEHOLDER",
                       "EventType": "viewer-request"
                   }
               ]
           },
           "FieldLevelEncryptionId": "",
           "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
           "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
       },
       "CacheBehaviors": {
           "Quantity": 2,
           "Items": [
               {
                   "PathPattern": "/api/*",
                   "TargetOriginId": "CustomOrigin",
                   "ViewerProtocolPolicy": "redirect-to-https",
                   "TrustedSigners": {
                       "Enabled": false,
                       "Quantity": 0
                   },
                   "TrustedKeyGroups": {
                       "Enabled": false,
                       "Quantity": 0
                   },
                   "AllowedMethods": {
                       "Quantity": 7,
                       "Items": ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"],
                       "CachedMethods": {
                           "Quantity": 2,
                           "Items": ["GET", "HEAD"]
                       }
                   },
                   "SmoothStreaming": false,
                   "Compress": true,
                   "LambdaFunctionAssociations": {
                       "Quantity": 1,
                       "Items": [
                           {
                               "LambdaFunctionARN": "LAMBDA_ARN_PLACEHOLDER",
                               "EventType": "origin-response",
                               "IncludeBody": false
                           }
                       ]
                   },
                   "FunctionAssociations": {
                       "Quantity": 0
                   },
                   "FieldLevelEncryptionId": "",
                   "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
                   "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
               },
               {
                   "PathPattern": "/static/*",
                   "TargetOriginId": "S3Origin",
                   "ViewerProtocolPolicy": "redirect-to-https",
                   "TrustedSigners": {
                       "Enabled": false,
                       "Quantity": 0
                   },
                   "TrustedKeyGroups": {
                       "Enabled": false,
                       "Quantity": 0
                   },
                   "AllowedMethods": {
                       "Quantity": 2,
                       "Items": ["GET", "HEAD"],
                       "CachedMethods": {
                           "Quantity": 2,
                           "Items": ["GET", "HEAD"]
                       }
                   },
                   "SmoothStreaming": false,
                   "Compress": true,
                   "LambdaFunctionAssociations": {
                       "Quantity": 0
                   },
                   "FunctionAssociations": {
                       "Quantity": 0
                   },
                   "FieldLevelEncryptionId": "",
                   "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6"
               }
           ]
       },
       "CustomErrorResponses": {
           "Quantity": 2,
           "Items": [
               {
                   "ErrorCode": 404,
                   "ResponsePagePath": "/404.html",
                   "ResponseCode": "404",
                   "ErrorCachingMinTTL": 300
               },
               {
                   "ErrorCode": 500,
                   "ResponsePagePath": "/500.html",
                   "ResponseCode": "500",
                   "ErrorCachingMinTTL": 0
               }
           ]
       },
       "Logging": {
           "Enabled": true,
           "IncludeCookies": false,
           "Bucket": "S3_BUCKET_PLACEHOLDER.s3.amazonaws.com",
           "Prefix": "cloudfront-logs/"
       },
       "PriceClass": "PriceClass_All",
       "ViewerCertificate": {
           "CloudFrontDefaultCertificate": true,
           "MinimumProtocolVersion": "TLSv1.2_2021",
           "CertificateSource": "cloudfront"
       },
       "Restrictions": {
           "GeoRestriction": {
               "RestrictionType": "none",
               "Quantity": 0
           }
       },
       "WebACLId": "WAF_WEBACL_ARN_PLACEHOLDER",
       "HttpVersion": "http2and3",
       "IsIPV6Enabled": true,
       "DefaultRootObject": "index.html"
   }
   EOF
   
   # Replace placeholders
   sed -i.bak "s/CALLER_REF_PLACEHOLDER/${CDN_PROJECT_NAME}-$(date +%s)/g" \
       /tmp/distribution-config.json
   sed -i.bak "s/S3_BUCKET_PLACEHOLDER/${S3_BUCKET_NAME}/g" \
       /tmp/distribution-config.json
   sed -i.bak "s/OAC_ID_PLACEHOLDER/${OAC_ID}/g" \
       /tmp/distribution-config.json
   sed -i.bak "s|LAMBDA_ARN_PLACEHOLDER|${LAMBDA_ARN}|g" \
       /tmp/distribution-config.json
   sed -i.bak "s|CLOUDFRONT_FUNCTION_ARN_PLACEHOLDER|${CLOUDFRONT_FUNCTION_ARN}|g" \
       /tmp/distribution-config.json
   sed -i.bak "s|WAF_WEBACL_ARN_PLACEHOLDER|${WAF_WEBACL_ARN}|g" \
       /tmp/distribution-config.json
   
   # Create CloudFront distribution
   DISTRIBUTION_OUTPUT=$(aws cloudfront create-distribution \
       --distribution-config file:///tmp/distribution-config.json)
   
   export DISTRIBUTION_ID=$(echo $DISTRIBUTION_OUTPUT | \
       jq -r '.Distribution.Id')
   export DISTRIBUTION_DOMAIN=$(echo $DISTRIBUTION_OUTPUT | \
       jq -r '.Distribution.DomainName')
   
   echo "✅ CloudFront distribution created with ID: ${DISTRIBUTION_ID}"
   echo "✅ Distribution domain: ${DISTRIBUTION_DOMAIN}"
   ```

   The distribution uses TLSv1.2 as the minimum SSL protocol for security, enables HTTP/2 and HTTP/3 for performance, and configures multiple cache behaviors for different content types. The configuration integrates both CloudFront Functions and Lambda@Edge for comprehensive edge processing capabilities.

6. **Configure S3 Bucket Policy for OAC**:

   Securing S3 origins requires implementing a bucket policy that restricts access exclusively to CloudFront through the Origin Access Control (OAC). This security pattern ensures that content can only be accessed through CloudFront's global edge network, preventing direct access to S3 URLs and maintaining consistent security controls across all content delivery.

   ```bash
   # Create S3 bucket policy to allow CloudFront access
   cat > /tmp/s3-policy.json << 'EOF'
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
               "Resource": "arn:aws:s3:::S3_BUCKET_PLACEHOLDER/*",
               "Condition": {
                   "StringEquals": {
                       "AWS:SourceArn": "arn:aws:cloudfront::AWS_ACCOUNT_ID_PLACEHOLDER:distribution/DISTRIBUTION_ID_PLACEHOLDER"
                   }
               }
           }
       ]
   }
   EOF
   
   # Replace placeholders
   sed -i.bak "s/S3_BUCKET_PLACEHOLDER/${S3_BUCKET_NAME}/g" \
       /tmp/s3-policy.json
   sed -i.bak "s/AWS_ACCOUNT_ID_PLACEHOLDER/${AWS_ACCOUNT_ID}/g" \
       /tmp/s3-policy.json
   sed -i.bak "s/DISTRIBUTION_ID_PLACEHOLDER/${DISTRIBUTION_ID}/g" \
       /tmp/s3-policy.json
   
   # Apply bucket policy
   aws s3api put-bucket-policy \
       --bucket ${S3_BUCKET_NAME} \
       --policy file:///tmp/s3-policy.json
   
   echo "✅ S3 bucket policy configured for CloudFront access"
   ```

   The policy uses AWS IAM conditions to verify the CloudFront distribution's identity before granting access to bucket objects. This security implementation follows the principle of least privilege by restricting access to a single, verified CloudFront distribution through the AWS:SourceArn condition.

7. **Enable Real-time Logs and Monitoring**:

   Real-time logging provides immediate visibility into CloudFront performance and security events by streaming detailed request data to Amazon Kinesis Data Streams. This operational capability enables rapid detection of anomalies, performance bottlenecks, and security incidents across the global edge network.

   ```bash
   # Create CloudWatch log group for real-time logs
   aws logs create-log-group \
       --log-group-name /aws/cloudfront/realtime-logs/${CDN_PROJECT_NAME}
   
   # Create Kinesis Data Stream for real-time logs
   aws kinesis create-stream \
       --stream-name cloudfront-realtime-logs-${RANDOM_SUFFIX} \
       --shard-count 1
   
   # Wait for stream to be active
   aws kinesis wait stream-exists \
       --stream-name cloudfront-realtime-logs-${RANDOM_SUFFIX}
   
   # Create IAM role for CloudFront real-time logs
   cat > /tmp/realtime-logs-trust-policy.json << 'EOF'
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Effect": "Allow",
               "Principal": {
                   "Service": "cloudfront.amazonaws.com"
               },
               "Action": "sts:AssumeRole"
           }
       ]
   }
   EOF
   
   # Create role
   aws iam create-role \
       --role-name CloudFront-RealTimeLogs-${RANDOM_SUFFIX} \
       --assume-role-policy-document file:///tmp/realtime-logs-trust-policy.json
   
   # Create policy for Kinesis access
   cat > /tmp/realtime-logs-policy.json << 'EOF'
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Effect": "Allow",
               "Action": [
                   "kinesis:PutRecords",
                   "kinesis:PutRecord"
               ],
               "Resource": "arn:aws:kinesis:*:*:stream/cloudfront-realtime-logs-*"
           }
       ]
   }
   EOF
   
   # Attach policy to role
   aws iam put-role-policy \
       --role-name CloudFront-RealTimeLogs-${RANDOM_SUFFIX} \
       --policy-name KinesisAccess \
       --policy-document file:///tmp/realtime-logs-policy.json
   
   # Wait for role to be available
   sleep 10
   
   # Create real-time log configuration
   KINESIS_STREAM_ARN="arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/cloudfront-realtime-logs-${RANDOM_SUFFIX}"
   REALTIME_LOGS_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/CloudFront-RealTimeLogs-${RANDOM_SUFFIX}"
   
   aws cloudfront create-realtime-log-config \
       --name "realtime-logs-${RANDOM_SUFFIX}" \
       --end-points StreamType=Kinesis,StreamArn=${KINESIS_STREAM_ARN},RoleArn=${REALTIME_LOGS_ROLE_ARN} \
       --fields timestamp c-ip sc-status cs-method cs-uri-stem \
           cs-uri-query cs-referer cs-user-agent
   
   echo "✅ Real-time logging configured"
   ```

   The configuration captures essential request details including timestamps, client IPs, response codes, and user agents, supporting comprehensive operational visibility across the global edge network. Real-time logging enables advanced analytics, automated alerting, and real-time decision making for traffic management and security response.

8. **Create Custom Monitoring Dashboard**:

   CloudWatch dashboards provide centralized visualization of CloudFront performance metrics, enabling operations teams to monitor traffic patterns, error rates, cache performance, and security events in real-time. This operational dashboard consolidates key performance indicators from multiple AWS services.

   ```bash
   # Create CloudWatch dashboard
   cat > /tmp/dashboard-config.json << 'EOF'
   {
       "widgets": [
           {
               "type": "metric",
               "x": 0,
               "y": 0,
               "width": 12,
               "height": 6,
               "properties": {
                   "metrics": [
                       ["AWS/CloudFront", "Requests", "DistributionId", "DISTRIBUTION_ID_PLACEHOLDER"],
                       [".", "BytesDownloaded", ".", "."],
                       [".", "BytesUploaded", ".", "."]
                   ],
                   "period": 300,
                   "stat": "Sum",
                   "region": "us-east-1",
                   "title": "CloudFront Traffic"
               }
           },
           {
               "type": "metric",
               "x": 12,
               "y": 0,
               "width": 12,
               "height": 6,
               "properties": {
                   "metrics": [
                       ["AWS/CloudFront", "4xxErrorRate", "DistributionId", "DISTRIBUTION_ID_PLACEHOLDER"],
                       [".", "5xxErrorRate", ".", "."]
                   ],
                   "period": 300,
                   "stat": "Average",
                   "region": "us-east-1",
                   "title": "Error Rates"
               }
           },
           {
               "type": "metric",
               "x": 0,
               "y": 6,
               "width": 12,
               "height": 6,
               "properties": {
                   "metrics": [
                       ["AWS/CloudFront", "CacheHitRate", "DistributionId", "DISTRIBUTION_ID_PLACEHOLDER"]
                   ],
                   "period": 300,
                   "stat": "Average",
                   "region": "us-east-1",
                   "title": "Cache Hit Rate"
               }
           },
           {
               "type": "metric",
               "x": 12,
               "y": 6,
               "width": 12,
               "height": 6,
               "properties": {
                   "metrics": [
                       ["AWS/WAFV2", "AllowedRequests", "WebACL", "WAF_WEBACL_NAME_PLACEHOLDER", "Rule", "ALL", "Region", "CloudFront"],
                       [".", "BlockedRequests", ".", ".", ".", ".", ".", "."]
                   ],
                   "period": 300,
                   "stat": "Sum",
                   "region": "us-east-1",
                   "title": "WAF Activity"
                   }
               }
           ]
       }
   }
   EOF
   
   # Replace placeholders
   sed -i.bak "s/DISTRIBUTION_ID_PLACEHOLDER/${DISTRIBUTION_ID}/g" \
       /tmp/dashboard-config.json
   sed -i.bak "s/WAF_WEBACL_NAME_PLACEHOLDER/${WAF_WEBACL_NAME}/g" \
       /tmp/dashboard-config.json
   
   # Create dashboard
   aws cloudwatch put-dashboard \
       --dashboard-name "CloudFront-Advanced-CDN-${RANDOM_SUFFIX}" \
       --dashboard-body file:///tmp/dashboard-config.json
   
   echo "✅ CloudWatch dashboard created"
   ```

   The dashboard widgets display critical metrics including request volumes, error rates, cache hit ratios, and WAF security events, supporting data-driven decision making for CDN optimization and incident response.

9. **Configure CloudFront KeyValueStore for Dynamic Content**:

   CloudFront KeyValueStore provides a low-latency, globally distributed data store that enables dynamic configuration changes without requiring distribution updates. This capability supports advanced use cases including feature flags, A/B testing, maintenance mode controls, and real-time content personalization.

   ```bash
   # Create KeyValueStore for dynamic configuration
   KVS_NAME="cdn-config-${RANDOM_SUFFIX}"
   
   aws cloudfront create-key-value-store \
       --name ${KVS_NAME} \
       --comment "Dynamic configuration store for CDN"
   
   # Wait for KVS to be ready
   sleep 30
   
   # Get KVS details
   KVS_ID=$(aws cloudfront describe-key-value-store \
       --name ${KVS_NAME} \
       --query 'KeyValueStore.Id' --output text)
   
   KVS_ARN=$(aws cloudfront describe-key-value-store \
       --name ${KVS_NAME} \
       --query 'KeyValueStore.ARN' --output text)
   
   # Add initial key-value pairs
   aws cloudfront put-key \
       --kvs-arn ${KVS_ARN} \
       --key "maintenance_mode" \
       --value "false"
   
   aws cloudfront put-key \
       --kvs-arn ${KVS_ARN} \
       --key "feature_flags" \
       --value '{"new_ui": true, "beta_features": false}'
   
   aws cloudfront put-key \
       --kvs-arn ${KVS_ARN} \
       --key "redirect_rules" \
       --value '{"old_domain": "new_domain.com", "legacy_path": "/new-path"}'
   
   echo "✅ CloudFront KeyValueStore configured with ID: ${KVS_ID}"
   ```

   The KeyValueStore integrates seamlessly with CloudFront Functions, allowing edge logic to access configuration data with minimal latency impact on request processing. For comprehensive information about KeyValueStore capabilities, refer to the [CloudFront KeyValueStore documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/kvs-with-functions.html).

10. **Test and Validate Distribution**:

    Comprehensive testing validates that the CloudFront distribution properly handles multiple content types, implements security controls, and delivers content with expected performance characteristics. This validation process verifies edge function execution, cache behavior configuration, security header injection, and WAF protection.

    ```bash
    # Wait for distribution to be deployed
    echo "Waiting for CloudFront distribution to be deployed..."
    aws cloudfront wait distribution-deployed \
        --id ${DISTRIBUTION_ID}
    
    # Test basic functionality
    echo "Testing CloudFront distribution..."
    
    # Test main origin
    curl -I https://${DISTRIBUTION_DOMAIN}/
    
    # Test API path (should use custom origin)
    curl -I https://${DISTRIBUTION_DOMAIN}/api/ip
    
    # Test static content path
    curl -I https://${DISTRIBUTION_DOMAIN}/static/
    
    # Test with different user agents
    curl -H "User-Agent: Mozilla/5.0 (Mobile)" \
        -I https://${DISTRIBUTION_DOMAIN}/
    
    # Test security headers
    curl -s -I https://${DISTRIBUTION_DOMAIN}/ | grep -i security
    
    # Test cache behavior
    curl -s -I https://${DISTRIBUTION_DOMAIN}/ | grep -i cache
    
    echo "✅ CloudFront distribution deployed and tested"
    echo "✅ Distribution URL: https://${DISTRIBUTION_DOMAIN}"
    ```

    Testing multiple paths and user agents ensures the distribution behaves correctly under various client scenarios and content access patterns. The distribution is ready for production traffic and can handle complex routing, security, and performance requirements.

## Validation & Testing

1. **Verify CloudFront Distribution Configuration**:

   ```bash
   # Check distribution status
   aws cloudfront get-distribution \
       --id ${DISTRIBUTION_ID} \
       --query 'Distribution.Status' --output text
   ```

   Expected output: `Deployed`

2. **Test Edge Functions**:

   ```bash
   # Test CloudFront Function (request processing)
   curl -v https://${DISTRIBUTION_DOMAIN}/?utm_source=test&utm_medium=email
   
   # Test Lambda@Edge (response processing)
   curl -I https://${DISTRIBUTION_DOMAIN}/ | \
       grep -E "X-Content-Type-Options|X-Frame-Options"
   ```

   Expected output: Security headers should be present

3. **Validate WAF Protection**:

   ```bash
   # Test rate limiting (may need multiple requests)
   for i in {1..10}; do
       curl -s -o /dev/null -w "%{http_code}\n" \
           https://${DISTRIBUTION_DOMAIN}/
   done
   
   # Check WAF metrics
   aws wafv2 get-sampled-requests \
       --web-acl-arn ${WAF_WEBACL_ARN} \
       --rule-metric-name CommonRuleSetMetric \
       --scope CLOUDFRONT \
       --time-window StartTime=$(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S'),EndTime=$(date -u '+%Y-%m-%dT%H:%M:%S') \
       --max-items 10
   ```

4. **Test Cache Behavior**:

   ```bash
   # Test cache hit/miss
   curl -s -I https://${DISTRIBUTION_DOMAIN}/ | grep -i x-cache
   curl -s -I https://${DISTRIBUTION_DOMAIN}/ | grep -i x-cache
   
   # Test different cache behaviors
   curl -s -I https://${DISTRIBUTION_DOMAIN}/api/status | grep -i cache
   curl -s -I https://${DISTRIBUTION_DOMAIN}/static/style.css | grep -i cache
   ```

5. **Monitor Real-time Logs**:

   ```bash
   # Check if logs are being generated
   aws kinesis describe-stream \
       --stream-name cloudfront-realtime-logs-${RANDOM_SUFFIX} \
       --query 'StreamDescription.StreamStatus' --output text
   
   # Sample real-time log data
   aws kinesis get-records \
       --shard-iterator $(aws kinesis get-shard-iterator \
           --stream-name cloudfront-realtime-logs-${RANDOM_SUFFIX} \
           --shard-id shardId-000000000000 \
           --shard-iterator-type TRIM_HORIZON \
           --query 'ShardIterator' --output text) \
       --query 'Records[0].Data' --output text | base64 -d
   ```

## Cleanup

1. **Disable and Delete CloudFront Distribution**:

   ```bash
   # Get current distribution config
   DIST_CONFIG=$(aws cloudfront get-distribution-config \
       --id ${DISTRIBUTION_ID})
   
   ETAG=$(echo $DIST_CONFIG | jq -r '.ETag')
   
   # Disable distribution
   echo $DIST_CONFIG | jq '.DistributionConfig.Enabled = false' | \
       jq '.DistributionConfig' > /tmp/disable-dist.json
   
   aws cloudfront update-distribution \
       --id ${DISTRIBUTION_ID} \
       --distribution-config file:///tmp/disable-dist.json \
       --if-match ${ETAG}
   
   # Wait for distribution to be disabled
   aws cloudfront wait distribution-deployed \
       --id ${DISTRIBUTION_ID}
   
   # Get new ETag and delete
   NEW_ETAG=$(aws cloudfront get-distribution \
       --id ${DISTRIBUTION_ID} \
       --query 'ETag' --output text)
   
   aws cloudfront delete-distribution \
       --id ${DISTRIBUTION_ID} \
       --if-match ${NEW_ETAG}
   
   echo "✅ CloudFront distribution deleted"
   ```

2. **Delete Lambda@Edge Function**:

   ```bash
   # Delete Lambda function
   aws lambda delete-function \
       --region us-east-1 \
       --function-name ${LAMBDA_FUNCTION_NAME}
   
   # Delete IAM role
   aws iam detach-role-policy \
       --role-name ${LAMBDA_FUNCTION_NAME}-role \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   
   aws iam delete-role \
       --role-name ${LAMBDA_FUNCTION_NAME}-role
   
   echo "✅ Lambda@Edge function and role deleted"
   ```

3. **Delete CloudFront Function**:

   ```bash
   # Delete CloudFront Function
   aws cloudfront delete-function \
       --name ${CLOUDFRONT_FUNCTION_NAME} \
       --if-match $(aws cloudfront describe-function \
           --name ${CLOUDFRONT_FUNCTION_NAME} \
           --query 'ETag' --output text)
   
   echo "✅ CloudFront Function deleted"
   ```

4. **Delete WAF Resources**:

   ```bash
   # Delete WAF Web ACL
   aws wafv2 delete-web-acl \
       --scope CLOUDFRONT \
       --id ${WAF_WEBACL_ID} \
       --lock-token $(aws wafv2 get-web-acl \
           --scope CLOUDFRONT \
           --id ${WAF_WEBACL_ID} \
           --query 'LockToken' --output text)
   
   echo "✅ WAF Web ACL deleted"
   ```

5. **Delete Origin Access Control**:

   ```bash
   # Delete OAC
   aws cloudfront delete-origin-access-control \
       --id ${OAC_ID}
   
   echo "✅ Origin Access Control deleted"
   ```

6. **Delete KeyValueStore**:

   ```bash
   # Delete KeyValueStore
   aws cloudfront delete-key-value-store \
       --name ${KVS_NAME}
   
   echo "✅ CloudFront KeyValueStore deleted"
   ```

7. **Delete Monitoring Resources**:

   ```bash
   # Delete CloudWatch dashboard
   aws cloudwatch delete-dashboards \
       --dashboard-names "CloudFront-Advanced-CDN-${RANDOM_SUFFIX}"
   
   # Delete Kinesis stream
   aws kinesis delete-stream \
       --stream-name cloudfront-realtime-logs-${RANDOM_SUFFIX}
   
   # Delete CloudWatch log group
   aws logs delete-log-group \
       --log-group-name /aws/cloudfront/realtime-logs/${CDN_PROJECT_NAME}
   
   # Delete real-time logs IAM role
   aws iam delete-role-policy \
       --role-name CloudFront-RealTimeLogs-${RANDOM_SUFFIX} \
       --policy-name KinesisAccess
   
   aws iam delete-role \
       --role-name CloudFront-RealTimeLogs-${RANDOM_SUFFIX}
   
   echo "✅ Monitoring resources deleted"
   ```

8. **Delete S3 Resources**:

   ```bash
   # Remove S3 bucket policy
   aws s3api delete-bucket-policy \
       --bucket ${S3_BUCKET_NAME}
   
   # Delete S3 bucket contents and bucket
   aws s3 rm s3://${S3_BUCKET_NAME} --recursive
   aws s3 rb s3://${S3_BUCKET_NAME}
   
   echo "✅ S3 resources deleted"
   ```

9. **Clean up local files**:

   ```bash
   # Remove temporary files
   rm -rf /tmp/cdn-content /tmp/lambda-edge
   rm -f /tmp/cloudfront-function.js /tmp/waf-webacl.json
   rm -f /tmp/oac-config.json /tmp/distribution-config.json
   rm -f /tmp/s3-policy.json /tmp/dashboard-config.json
   rm -f /tmp/realtime-logs-trust-policy.json
   rm -f /tmp/realtime-logs-policy.json
   rm -f /tmp/lambda-edge-trust-policy.json
   rm -f /tmp/*.json.bak
   
   echo "✅ Local files cleaned up"
   ```

## Discussion

This advanced CloudFront architecture demonstrates sophisticated content delivery capabilities that go far beyond basic CDN functionality. The solution integrates multiple AWS services to create a comprehensive edge computing platform that handles content transformation, security, and monitoring at scale.

The architecture leverages CloudFront Functions for lightweight, high-performance operations like cache key normalization and header manipulation, while Lambda@Edge handles more complex processing that requires additional computing resources and third-party integrations. This dual-function approach optimizes both performance and cost, as CloudFront Functions execute in sub-millisecond timeframes with minimal overhead, while Lambda@Edge provides full programming language support for complex business logic. For detailed guidance on choosing between these edge computing options, see the [AWS documentation on differences between CloudFront Functions and Lambda@Edge](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/edge-functions-choosing.html).

The monitoring and logging implementation provides comprehensive visibility into CDN performance and security events. Real-time logs stream to Kinesis for immediate analysis, while CloudWatch dashboards provide operational insights into traffic patterns, error rates, and cache performance. The KeyValueStore integration enables dynamic configuration changes without requiring distribution updates, supporting use cases like feature flags, A/B testing, and emergency traffic routing. The integration of AWS WAF provides enterprise-grade security with managed rule sets, rate limiting, and geo-blocking capabilities, protecting against common web exploits and DDoS attacks. For additional security integration patterns, see the [AWS WAF with CloudFront documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/distribution-web-awswaf.html) and the [guide to restricting S3 access](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html).

The solution addresses common enterprise challenges including content personalization, security compliance, performance optimization, and operational monitoring. By implementing multiple origins with different cache behaviors, organizations can optimize content delivery based on content type and user requirements while maintaining security and performance standards across all touchpoints. This architecture pattern is particularly valuable for large-scale applications requiring global content delivery with advanced security, performance optimization, and operational visibility.

> **Tip**: Monitor cache hit ratios closely and adjust cache policies based on content types and user access patterns to maximize performance and reduce origin load.

## Challenge

Extend this solution by implementing these advanced enhancements:

1. **Implement A/B Testing Framework**: Create Lambda@Edge functions that perform user segmentation and serve different content versions based on user attributes, geographic location, or device type, with results tracking through CloudWatch custom metrics.

2. **Add Image Optimization Pipeline**: Integrate with Lambda@Edge to automatically optimize images based on device capabilities, implementing WebP conversion for supported browsers and dynamic resizing based on viewport detection.

3. **Create Multi-Region Failover**: Implement origin failover mechanisms using CloudFront origin groups with health checks, and create automated failover procedures using Lambda functions triggered by CloudWatch alarms.

4. **Build Advanced Security Controls**: Implement custom WAF rules using AWS Lambda for intelligent threat detection, integrate with AWS Shield Advanced for DDoS protection, and create automated security response workflows using Step Functions.

5. **Develop Cost Optimization Automation**: Create Lambda functions that analyze CloudFront usage patterns and automatically adjust cache policies, price classes, and origin selection based on cost efficiency metrics and performance requirements.

## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [AWS CDK (Python)](code/cdk-python/) - AWS CDK Python implementation
- [AWS CDK (TypeScript)](code/cdk-typescript/) - AWS CDK TypeScript implementation
- [CloudFormation](code/cloudformation.yaml) - AWS CloudFormation template
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using AWS CLI commands to deploy infrastructure
- [Terraform](code/terraform/) - Terraform configuration files