---
title: Secure Content Delivery with CloudFront WAF
id: 8183bfc1
category: security
difficulty: 300
subject: aws
services: CloudFront, WAF, S3, Lambda
estimated-time: 45 minutes
recipe-version: 1.2
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: null
passed-qa: null
tags: security, cloudfront, waf, content-delivery, ddos-protection, geo-blocking
recipe-generator-version: 1.3
---

# Secure Content Delivery with CloudFront WAF

## Problem

Your organization delivers web content and applications to a global audience, but is experiencing increasing security threats including bot traffic, DDoS attacks, and attempts to exploit web vulnerabilities. The existing content delivery solution lacks advanced threat protection, has no geographic access controls, and provides limited visibility into malicious traffic patterns. Your security team needs a solution that can protect web applications and APIs while maintaining high-performance content delivery to legitimate users worldwide.

## Solution

Implement a comprehensive content protection system using Amazon CloudFront combined with AWS WAF (Web Application Firewall). This solution leverages CloudFront's global edge network for high-performance content delivery while applying multi-layered security controls through AWS WAF. By implementing geographic restrictions, rate-based rules, managed rule groups for common threats, and custom rules for application-specific vulnerabilities, the system can protect against a wide range of attack vectors.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Users"
        USER[End Users]
        MALICIOUS[Malicious Traffic]
    end
    
    subgraph "AWS WAF Protection"
        WAF[AWS WAF<br/>Web ACL]
        RULES[WAF Rules<br/>- Rate-based<br/>- Managed Rules<br/>- Geo Restrictions]
    end
    
    subgraph "CloudFront Distribution"
        EDGE[CloudFront Edge<br/>Locations]
        CACHE[CloudFront Cache]
    end
    
    subgraph "Origin"
        S3[S3 Bucket<br/>Static Content]
        ALB[Application Load<br/>Balancer]
        EC2[EC2 Instances<br/>Dynamic Content]
    end
    
    subgraph "Monitoring"
        CW[CloudWatch<br/>Metrics & Logs]
        DASH[CloudWatch<br/>Dashboard]
    end
    
    USER --> WAF
    MALICIOUS --> WAF
    WAF --> EDGE
    EDGE --> CACHE
    CACHE --> S3
    CACHE --> ALB
    ALB --> EC2
    
    WAF --> CW
    EDGE --> CW
    CW --> DASH
    
    style WAF fill:#FF6B6B
    style EDGE fill:#4ECDC4
    style S3 fill:#FFE66D
    style MALICIOUS fill:#FF4757
    style RULES fill:#FF6B6B
```

## Prerequisites

1. AWS account with appropriate permissions for CloudFront, WAF, S3, and CloudWatch
2. AWS CLI v2 installed and configured (or AWS CloudShell)
3. Basic understanding of web application security concepts
4. Existing S3 bucket with static content (or ability to create one)
5. Knowledge of HTTP methods, headers, and status codes
6. Estimated cost: $0.50-$2.00 per month for WAF rules and CloudFront requests (varies by traffic volume)

> **Note**: WAF charges are based on the number of web ACLs, rules, and web requests processed. See the [AWS WAF pricing page](https://aws.amazon.com/waf/pricing/) for detailed cost information.

## Preparation

```bash
# Set environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

export BUCKET_NAME="secure-content-${RANDOM_SUFFIX}"
export DISTRIBUTION_NAME="secure-distribution-${RANDOM_SUFFIX}"
export WAF_WEB_ACL_NAME="secure-web-acl-${RANDOM_SUFFIX}"

# Create S3 bucket for content storage
aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}

# Create sample content for testing
echo "<html><body><h1>Secure Content Test</h1><p>This content is protected by AWS WAF and CloudFront.</p></body></html>" > index.html

# Upload sample content to S3
aws s3 cp index.html s3://${BUCKET_NAME}/index.html

echo "✅ Environment prepared with bucket: ${BUCKET_NAME}"
```

## Steps

1. **Create AWS WAF Web ACL with Security Rules**:

   AWS WAF provides a centralized way to protect your web applications from common web exploits and attacks. A Web ACL (Access Control List) acts as a firewall for your web applications, inspecting each HTTP/HTTPS request and applying rules to allow, block, or monitor traffic. This foundational step establishes the security framework that will protect your content delivery system.

   ```bash
   # Create WAF Web ACL for CloudFront (global scope)
   aws wafv2 create-web-acl \
       --scope CLOUDFRONT \
       --region us-east-1 \
       --name ${WAF_WEB_ACL_NAME} \
       --description "Web ACL for CloudFront security protection" \
       --default-action Allow={} \
       --rules file://waf-rules.json
   
   # Get Web ACL ARN for CloudFront association
   export WAF_WEB_ACL_ARN=$(aws wafv2 list-web-acls \
       --scope CLOUDFRONT \
       --region us-east-1 \
       --query "WebACLs[?Name=='${WAF_WEB_ACL_NAME}'].ARN" \
       --output text)
   
   echo "✅ WAF Web ACL created: ${WAF_WEB_ACL_ARN}"
   ```

   The Web ACL is now configured with a default action to allow traffic, which will be refined as we add specific security rules. This approach ensures legitimate traffic continues to flow while we implement targeted protections.

2. **Configure WAF Managed Rules for Common Threats**:

   AWS Managed Rules provide pre-configured rule groups that protect against OWASP Top 10 vulnerabilities, known bad inputs, and other common attack vectors. These rules are maintained by AWS security experts and automatically updated as new threats emerge, providing enterprise-grade protection without requiring specialized security knowledge.

   ```bash
   # Create rules configuration file
   cat > waf-managed-rules.json << 'EOF'
   [
     {
       "Name": "AWS-AWSManagedRulesCommonRuleSet",
       "Priority": 1,
       "Statement": {
         "ManagedRuleGroupStatement": {
           "VendorName": "AWS",
           "Name": "AWSManagedRulesCommonRuleSet"
         }
       },
       "OverrideAction": {
         "None": {}
       },
       "VisibilityConfig": {
         "SampledRequestsEnabled": true,
         "CloudWatchMetricsEnabled": true,
         "MetricName": "CommonRuleSetMetric"
       }
     },
     {
       "Name": "AWS-AWSManagedRulesKnownBadInputsRuleSet",
       "Priority": 2,
       "Statement": {
         "ManagedRuleGroupStatement": {
           "VendorName": "AWS",
           "Name": "AWSManagedRulesKnownBadInputsRuleSet"
         }
       },
       "OverrideAction": {
         "None": {}
       },
       "VisibilityConfig": {
         "SampledRequestsEnabled": true,
         "CloudWatchMetricsEnabled": true,
         "MetricName": "KnownBadInputsMetric"
       }
     }
   ]
   EOF
   
   # Update Web ACL with managed rules
   aws wafv2 update-web-acl \
       --scope CLOUDFRONT \
       --region us-east-1 \
       --id $(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 \
           --query "WebACLs[?Name=='${WAF_WEB_ACL_NAME}'].Id" --output text) \
       --name ${WAF_WEB_ACL_NAME} \
       --description "Web ACL with managed rules for CloudFront" \
       --default-action Allow={} \
       --rules file://waf-managed-rules.json \
       --lock-token $(aws wafv2 get-web-acl --scope CLOUDFRONT --region us-east-1 \
           --id $(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 \
               --query "WebACLs[?Name=='${WAF_WEB_ACL_NAME}'].Id" --output text) \
           --query "LockToken" --output text)
   
   echo "✅ WAF managed rules configured for common threats"
   ```

   These managed rule groups now provide comprehensive protection against SQL injection, cross-site scripting (XSS), and other common attack patterns, significantly reducing your security exposure with minimal configuration effort.

3. **Implement Rate-Based Rules for DDoS Protection**:

   Rate-based rules are crucial for protecting against HTTP flood attacks and aggressive bot behavior. These rules monitor request patterns and automatically block source IP addresses that exceed defined thresholds, providing an effective defense against distributed denial-of-service attacks while allowing legitimate traffic to continue unimpeded.

   ```bash
   # Create rate-based rule configuration
   cat > rate-based-rule.json << 'EOF'
   [
     {
       "Name": "RateLimitRule",
       "Priority": 3,
       "Statement": {
         "RateBasedStatement": {
           "Limit": 2000,
           "AggregateKeyType": "IP"
         }
       },
       "Action": {
         "Block": {}
       },
       "VisibilityConfig": {
         "SampledRequestsEnabled": true,
         "CloudWatchMetricsEnabled": true,
         "MetricName": "RateLimitMetric"
       }
     }
   ]
   EOF
   
   # Get current Web ACL configuration
   aws wafv2 get-web-acl \
       --scope CLOUDFRONT \
       --region us-east-1 \
       --id $(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 \
           --query "WebACLs[?Name=='${WAF_WEB_ACL_NAME}'].Id" --output text) \
       --query "WebACL.Rules" > current-rules.json
   
   # Merge rate-based rule with existing rules
   jq '. + [
     {
       "Name": "RateLimitRule",
       "Priority": 3,
       "Statement": {
         "RateBasedStatement": {
           "Limit": 2000,
           "AggregateKeyType": "IP"
         }
       },
       "Action": {
         "Block": {}
       },
       "VisibilityConfig": {
         "SampledRequestsEnabled": true,
         "CloudWatchMetricsEnabled": true,
         "MetricName": "RateLimitMetric"
       }
     }
   ]' current-rules.json > updated-rules.json
   
   # Update Web ACL with rate-based rule
   aws wafv2 update-web-acl \
       --scope CLOUDFRONT \
       --region us-east-1 \
       --id $(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 \
           --query "WebACLs[?Name=='${WAF_WEB_ACL_NAME}'].Id" --output text) \
       --name ${WAF_WEB_ACL_NAME} \
       --description "Web ACL with rate-based rules" \
       --default-action Allow={} \
       --rules file://updated-rules.json \
       --lock-token $(aws wafv2 get-web-acl --scope CLOUDFRONT --region us-east-1 \
           --id $(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 \
               --query "WebACLs[?Name=='${WAF_WEB_ACL_NAME}'].Id" --output text) \
           --query "LockToken" --output text)
   
   echo "✅ Rate-based rules configured for DDoS protection"
   ```

   The rate-based rule now monitors incoming requests and automatically blocks IP addresses that exceed 2,000 requests per 5-minute window, providing effective protection against HTTP flood attacks while maintaining service availability for legitimate users.

4. **Create CloudFront Distribution with Origin Access Control**:

   CloudFront's global edge network provides low-latency content delivery while serving as the first line of defense when integrated with WAF. Origin Access Control (OAC) ensures that your S3 bucket can only be accessed through CloudFront, preventing direct access attempts that could bypass your security controls.

   ```bash
   # Create Origin Access Control for S3
   aws cloudfront create-origin-access-control \
       --origin-access-control-config \
       Name="OAC-${BUCKET_NAME}",Description="Origin Access Control for ${BUCKET_NAME}",SigningBehavior="always",SigningProtocol="sigv4",OriginAccessControlOriginType="s3" \
       --query "OriginAccessControl.Id" --output text > oac-id.txt
   
   export OAC_ID=$(cat oac-id.txt)
   
   # Create CloudFront distribution configuration
   cat > cloudfront-config.json << EOF
   {
     "CallerReference": "secure-distribution-$(date +%s)",
     "Comment": "Secure CloudFront distribution with WAF protection",
     "Origins": {
       "Quantity": 1,
       "Items": [
         {
           "Id": "${BUCKET_NAME}",
           "DomainName": "${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com",
           "OriginPath": "",
           "S3OriginConfig": {
             "OriginAccessIdentity": ""
           },
           "OriginAccessControlId": "${OAC_ID}"
         }
       ]
     },
     "DefaultCacheBehavior": {
       "TargetOriginId": "${BUCKET_NAME}",
       "ViewerProtocolPolicy": "redirect-to-https",
       "MinTTL": 0,
       "ForwardedValues": {
         "QueryString": false,
         "Cookies": {
           "Forward": "none"
         }
       },
       "TrustedSigners": {
         "Enabled": false,
         "Quantity": 0
       }
     },
     "Enabled": true,
     "WebACLId": "${WAF_WEB_ACL_ARN}",
     "PriceClass": "PriceClass_100"
   }
   EOF
   
   # Create CloudFront distribution
   aws cloudfront create-distribution \
       --distribution-config file://cloudfront-config.json \
       --query "Distribution.Id" --output text > distribution-id.txt
   
   export DISTRIBUTION_ID=$(cat distribution-id.txt)
   
   echo "✅ CloudFront distribution created with WAF protection: ${DISTRIBUTION_ID}"
   ```

   The CloudFront distribution is now configured with Origin Access Control, HTTPS enforcement, and WAF integration. This provides a secure, high-performance content delivery system that protects your origin servers while ensuring fast global access for legitimate users.

5. **Configure S3 Bucket Policy for CloudFront Access**:

   The S3 bucket policy restricts access to only allow CloudFront using the Origin Access Control identity. This security measure prevents direct access to your content, ensuring all requests pass through CloudFront and are subject to WAF inspection and protection.

   ```bash
   # Wait for distribution to be created
   aws cloudfront wait distribution-deployed --id ${DISTRIBUTION_ID}
   
   # Create S3 bucket policy for CloudFront OAC
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
             "AWS:SourceArn": "arn:aws:cloudfront::${AWS_ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"
           }
         }
       }
     ]
   }
   EOF
   
   # Apply bucket policy
   aws s3api put-bucket-policy \
       --bucket ${BUCKET_NAME} \
       --policy file://bucket-policy.json
   
   echo "✅ S3 bucket policy configured for CloudFront access"
   ```

   The bucket policy now ensures that only CloudFront can access your S3 content, establishing a secure content delivery pipeline where all requests are filtered through WAF before reaching your origin.

6. **Configure Geographic Restrictions**:

   Geographic restrictions provide an additional layer of security by blocking or allowing traffic based on the requesting user's country. This capability is particularly valuable for compliance requirements or when you need to restrict access to certain regions due to licensing, legal, or security considerations.

   ```bash
   # Get current distribution configuration
   aws cloudfront get-distribution-config \
       --id ${DISTRIBUTION_ID} \
       --query "DistributionConfig" > current-distribution-config.json
   
   # Update distribution with geographic restrictions
   jq '.Restrictions = {
     "GeoRestriction": {
       "RestrictionType": "blacklist",
       "Quantity": 2,
       "Items": ["RU", "CN"]
     }
   }' current-distribution-config.json > updated-distribution-config.json
   
   # Get current ETag for update
   export ETAG=$(aws cloudfront get-distribution-config \
       --id ${DISTRIBUTION_ID} \
       --query "ETag" --output text)
   
   # Apply geographic restrictions
   aws cloudfront update-distribution \
       --id ${DISTRIBUTION_ID} \
       --distribution-config file://updated-distribution-config.json \
       --if-match ${ETAG}
   
   echo "✅ Geographic restrictions configured"
   ```

   Geographic restrictions are now active, automatically blocking requests from specified countries at the CloudFront edge locations. This provides an efficient way to implement location-based access controls without impacting performance for allowed regions.

## Validation & Testing

1. **Verify WAF Web ACL Configuration**:

   ```bash
   # Check WAF Web ACL status and rules
   aws wafv2 get-web-acl \
       --scope CLOUDFRONT \
       --region us-east-1 \
       --id $(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 \
           --query "WebACLs[?Name=='${WAF_WEB_ACL_NAME}'].Id" --output text) \
       --query "WebACL.{Name:Name,Rules:Rules[].Name,DefaultAction:DefaultAction}"
   ```

   Expected output: Web ACL with managed rules, rate-based rules, and default allow action.

2. **Test CloudFront Distribution Access**:

   ```bash
   # Get CloudFront distribution domain name
   export DOMAIN_NAME=$(aws cloudfront get-distribution \
       --id ${DISTRIBUTION_ID} \
       --query "Distribution.DomainName" --output text)
   
   # Test HTTPS access (should succeed)
   curl -I https://${DOMAIN_NAME}/index.html
   
   # Test HTTP access (should redirect to HTTPS)
   curl -I http://${DOMAIN_NAME}/index.html
   ```

   Expected output: 200 OK for HTTPS requests, 301 redirect for HTTP requests.

3. **Verify S3 Direct Access Prevention**:

   ```bash
   # Attempt direct S3 access (should fail)
   curl -I https://${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com/index.html
   ```

   Expected output: 403 Forbidden error, confirming direct access is blocked.

4. **Test Rate-Based Rules (Optional)**:

   ```bash
   # Simulate multiple requests to test rate limiting
   for i in {1..10}; do
     curl -s https://${DOMAIN_NAME}/index.html > /dev/null
     echo "Request $i completed"
   done
   ```

   Note: Rate limiting may not be immediately visible with low request volumes.

## Cleanup

1. **Remove CloudFront Distribution**:

   ```bash
   # Disable distribution first
   aws cloudfront get-distribution-config \
       --id ${DISTRIBUTION_ID} \
       --query "DistributionConfig" > final-distribution-config.json
   
   jq '.Enabled = false' final-distribution-config.json > disabled-distribution-config.json
   
   export FINAL_ETAG=$(aws cloudfront get-distribution-config \
       --id ${DISTRIBUTION_ID} \
       --query "ETag" --output text)
   
   aws cloudfront update-distribution \
       --id ${DISTRIBUTION_ID} \
       --distribution-config file://disabled-distribution-config.json \
       --if-match ${FINAL_ETAG}
   
   # Wait for distribution to be disabled
   aws cloudfront wait distribution-deployed --id ${DISTRIBUTION_ID}
   
   # Delete distribution
   aws cloudfront delete-distribution \
       --id ${DISTRIBUTION_ID} \
       --if-match $(aws cloudfront get-distribution-config \
           --id ${DISTRIBUTION_ID} \
           --query "ETag" --output text)
   
   echo "✅ CloudFront distribution deleted"
   ```

2. **Remove Origin Access Control**:

   ```bash
   # Delete Origin Access Control
   aws cloudfront delete-origin-access-control \
       --id ${OAC_ID} \
       --if-match $(aws cloudfront get-origin-access-control \
           --id ${OAC_ID} \
           --query "ETag" --output text)
   
   echo "✅ Origin Access Control deleted"
   ```

3. **Remove WAF Web ACL**:

   ```bash
   # Delete WAF Web ACL
   aws wafv2 delete-web-acl \
       --scope CLOUDFRONT \
       --region us-east-1 \
       --id $(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 \
           --query "WebACLs[?Name=='${WAF_WEB_ACL_NAME}'].Id" --output text) \
       --lock-token $(aws wafv2 get-web-acl --scope CLOUDFRONT --region us-east-1 \
           --id $(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 \
               --query "WebACLs[?Name=='${WAF_WEB_ACL_NAME}'].Id" --output text) \
           --query "LockToken" --output text)
   
   echo "✅ WAF Web ACL deleted"
   ```

4. **Remove S3 Bucket and Content**:

   ```bash
   # Delete S3 bucket contents
   aws s3 rm s3://${BUCKET_NAME} --recursive
   
   # Delete S3 bucket
   aws s3 rb s3://${BUCKET_NAME}
   
   # Clean up local files
   rm -f index.html *.json *.txt
   
   echo "✅ S3 bucket and local files deleted"
   ```

## Discussion

The integration of Amazon CloudFront with AWS WAF creates a powerful security architecture that provides both performance optimization and comprehensive threat protection. CloudFront's global edge network serves as the first line of defense, intercepting malicious requests before they reach your origin infrastructure. This approach significantly reduces the load on your backend systems while providing consistent security enforcement across all global regions.

AWS WAF's managed rules offer enterprise-grade protection that automatically adapts to emerging threats. The Common Rule Set protects against OWASP Top 10 vulnerabilities, while the Known Bad Inputs rule set blocks requests containing malicious payloads. These rules are continuously updated by AWS security experts, ensuring your applications remain protected against the latest attack vectors without requiring manual intervention.

Rate-based rules provide crucial protection against HTTP flood attacks and aggressive bot behavior. By monitoring request patterns and automatically blocking source IP addresses that exceed defined thresholds, these rules create an effective defense against distributed denial-of-service attacks. The 5-minute sliding window approach ensures that legitimate traffic bursts don't trigger false positives while maintaining protection against sustained attacks.

The Origin Access Control mechanism ensures that your S3 content can only be accessed through CloudFront, preventing direct access attempts that could bypass security controls. This security model extends beyond simple access control—it creates a comprehensive security perimeter that forces all traffic through your configured protection mechanisms. For additional security guidance, refer to the [AWS WAF Best Practices](https://docs.aws.amazon.com/waf/latest/developerguide/waf-best-practices.html) documentation.

> **Warning**: Monitor your WAF metrics regularly to ensure rules are not blocking legitimate traffic. Fine-tune rate limits and rule configurations based on your application's traffic patterns and business requirements.

## Challenge

Extend this solution to create a more sophisticated content protection system by implementing the following enhancements:

1. Deploy a custom header verification system using Lambda@Edge that validates secure headers before requests reach your origin, rejecting any that don't contain the proper authentication tokens.

2. Implement AWS WAF Bot Control to detect and manage bot traffic, differentiating between good bots (search engines, monitoring tools) and malicious ones.

3. Create an automated IP reputation management system that uses Lambda to periodically fetch known bad IP lists from threat intelligence sources and dynamically updates your WAF IP set rules.

4. Integrate with AWS Shield Advanced for DDoS protection and configure real-time attack notifications through SNS.

5. Implement custom logging and monitoring dashboards using CloudWatch Insights to analyze traffic patterns and security events in real-time.

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*