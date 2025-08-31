---
title: Hosting Websites with S3 CloudFront and Route 53
id: db114261
category: networking
difficulty: 200
subject: aws
services: s3, cloudfront, route53, acm
estimated-time: 120 minutes
recipe-version: 1.2
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: s3, cloudfront, route53, acm, static-website, cdn
recipe-generator-version: 1.3
---

# Building Static Website Hosting with S3, CloudFront, and Route 53

## Problem

Modern businesses need fast, scalable, and cost-effective web hosting solutions for their marketing websites, documentation portals, and single-page applications. Traditional web hosting often involves managing server infrastructure, dealing with traffic spikes, and handling global content delivery manually. Companies struggle with slow loading times for international users, high hosting costs for simple static sites, and complex SSL certificate management across multiple regions.

## Solution

Build a globally distributed static website hosting solution using Amazon S3 for storage, CloudFront for content delivery, and Route 53 for DNS management. This architecture provides automatic SSL/TLS encryption, global edge caching, and seamless scalability while maintaining cost-effectiveness for static content delivery.

## Architecture Diagram

```mermaid
graph TB
    subgraph "User Layer"
        USER[Users Worldwide]
    end
    
    subgraph "DNS Layer"
        R53[Route 53<br/>DNS Management]
    end
    
    subgraph "Content Delivery"
        CF[CloudFront<br/>Global CDN]
        ACM[Certificate Manager<br/>SSL/TLS Certificate]
    end
    
    subgraph "Origin Storage"
        S3[S3 Bucket<br/>Static Website Hosting]
        S3R[S3 Redirect Bucket<br/>Root Domain]
    end
    
    USER-->R53
    R53-->CF
    CF-->S3
    ACM-->CF
    R53-.->S3R
    
    style S3 fill:#FF9900
    style CF fill:#FF4B4B
    style R53 fill:#9D5AAE
    style ACM fill:#FF9900
    style S3R fill:#FFB366
```

## Prerequisites

1. AWS account with permissions for S3, CloudFront, Route 53, and Certificate Manager
2. AWS CLI v2 installed and configured (or AWS CloudShell)
3. A registered domain name (can be registered through Route 53 or external registrar)
4. Basic understanding of DNS concepts and web hosting
5. Estimated cost: $0.50-2.00/month for small websites (domain registration additional ~$12/year)

> **Note**: SSL certificates through AWS Certificate Manager are free when used with CloudFront and other AWS services.

## Preparation

```bash
# Set environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account --output text)

# Set your domain name (replace with your actual domain)
export DOMAIN_NAME="example.com"
export SUBDOMAIN="www.${DOMAIN_NAME}"

# Generate unique bucket names (S3 buckets must be globally unique)
export ROOT_BUCKET="${DOMAIN_NAME}"
export WWW_BUCKET="${SUBDOMAIN}"

echo "Domain: $DOMAIN_NAME"
echo "Subdomain: $SUBDOMAIN"
echo "Root bucket: $ROOT_BUCKET"
echo "WWW bucket: $WWW_BUCKET"
```

## Steps

1. **Create S3 bucket for subdomain (www) website hosting**:

   Amazon S3 static website hosting provides a cost-effective foundation for serving static content. Unlike traditional web servers, S3 eliminates server management overhead while offering 99.999999999% (11 9's) durability and virtually unlimited scalability. This step establishes the primary content origin that will serve your website files to users globally.

   ```bash
   # Create the main website bucket (handle us-east-1 special case)
   if [ "$AWS_REGION" = "us-east-1" ]; then
       aws s3api create-bucket --bucket "$WWW_BUCKET"
   else
       aws s3api create-bucket \
           --bucket "$WWW_BUCKET" \
           --region "$AWS_REGION" \
           --create-bucket-configuration LocationConstraint="$AWS_REGION"
   fi
   
   # Configure bucket for static website hosting
   aws s3 website "s3://$WWW_BUCKET/" \
       --index-document index.html \
       --error-document error.html
   
   echo "✅ Created and configured S3 bucket: $WWW_BUCKET"
   ```

   The bucket is now configured as a static website origin with designated index and error documents. This configuration enables S3 to serve web content directly and handle routing for single-page applications, forming the foundation for your global content delivery architecture.

2. **Create S3 bucket for root domain redirect**:

   Implementing a canonical URL structure improves SEO rankings and prevents content duplication issues. This redirect bucket ensures all traffic consolidates to the www subdomain, providing consistent user experience and simplified analytics tracking. The HTTPS protocol enforcement also maintains security standards across all access patterns.

   ```bash
   # Create the root domain bucket for redirect
   if [ "$AWS_REGION" = "us-east-1" ]; then
       aws s3api create-bucket --bucket "$ROOT_BUCKET"
   else
       aws s3api create-bucket \
           --bucket "$ROOT_BUCKET" \
           --region "$AWS_REGION" \
           --create-bucket-configuration LocationConstraint="$AWS_REGION"
   fi
   
   # Configure bucket to redirect to www subdomain
   cat > redirect-config.json << EOF
   {
       "RedirectAllRequestsTo": {
           "HostName": "$SUBDOMAIN",
           "Protocol": "https"
       }
   }
   EOF
   
   aws s3api put-bucket-website \
       --bucket "$ROOT_BUCKET" \
       --website-configuration file://redirect-config.json
   
   echo "✅ Created redirect bucket: $ROOT_BUCKET"
   ```

   The redirect configuration is now active, automatically forwarding all requests from the root domain to the www subdomain using HTTPS. This establishes a unified entry point for your website while maintaining professional URL standards and security protocols.

3. **Create sample website content**:

   Creating structured HTML content with proper metadata and responsive design ensures optimal performance across devices and search engines. This step demonstrates best practices for static website development, including semantic HTML structure, embedded CSS for performance, and proper viewport configuration for mobile compatibility.

   ```bash
   # Create a sample index.html file
   cat > index.html << EOF
   <!DOCTYPE html>
   <html lang="en">
   <head>
       <meta charset="UTF-8">
       <meta name="viewport" content="width=device-width, initial-scale=1.0">
       <title>Welcome to $DOMAIN_NAME</title>
       <style>
           body { font-family: Arial, sans-serif; margin: 40px; 
                  text-align: center; background-color: #f0f8ff; }
           h1 { color: #2c3e50; }
           p { color: #7f8c8d; font-size: 18px; }
       </style>
   </head>
   <body>
       <h1>Welcome to $DOMAIN_NAME</h1>
       <p>Your static website is now live with global CDN delivery!</p>
       <p>Powered by AWS S3, CloudFront, and Route 53</p>
   </body>
   </html>
   EOF
   
   # Create a custom error page
   cat > error.html << EOF
   <!DOCTYPE html>
   <html lang="en">
   <head>
       <meta charset="UTF-8">
       <meta name="viewport" content="width=device-width, initial-scale=1.0">
       <title>Page Not Found - $DOMAIN_NAME</title>
       <style>
           body { font-family: Arial, sans-serif; margin: 40px; 
                  text-align: center; background-color: #fff5f5; }
           h1 { color: #e74c3c; }
       </style>
   </head>
   <body>
       <h1>404 - Page Not Found</h1>
       <p>The page you're looking for doesn't exist.</p>
       <a href="/">Return to Home</a>
   </body>
   </html>
   EOF
   
   echo "✅ Created sample website content"
   ```

   The website content is now ready for deployment with optimized HTML structure and responsive design. These files demonstrate production-ready static website patterns that will render consistently across browsers and devices when served through the global CDN.

4. **Upload website content to S3**:

   S3 bucket policies provide fine-grained access control following the principle of least privilege. Public read access is required for static website hosting, but this configuration restricts permissions to only GET operations on objects, preventing unauthorized uploads or deletions. The content-type headers ensure proper MIME type handling for optimal browser rendering and caching.

   ```bash
   # Upload files to S3 bucket
   aws s3 cp index.html "s3://$WWW_BUCKET/" \
       --content-type "text/html"
   
   aws s3 cp error.html "s3://$WWW_BUCKET/" \
       --content-type "text/html"
   
   # Make bucket contents publicly readable
   cat > bucket-policy.json << EOF
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Sid": "PublicReadGetObject",
               "Effect": "Allow",
               "Principal": "*",
               "Action": "s3:GetObject",
               "Resource": "arn:aws:s3:::$WWW_BUCKET/*"
           }
       ]
   }
   EOF
   
   # Disable block public access (required for website hosting)
   aws s3api delete-public-access-block \
       --bucket "$WWW_BUCKET"
   
   # Apply bucket policy
   aws s3api put-bucket-policy \
       --bucket "$WWW_BUCKET" \
       --policy file://bucket-policy.json
   
   echo "✅ Uploaded content and configured public access"
   ```

   The website content is now publicly accessible with secure read-only permissions. This configuration balances accessibility requirements for web hosting with security best practices, enabling global content delivery while protecting against unauthorized modifications.

5. **Request SSL certificate in us-east-1 (required for CloudFront)**:

   AWS Certificate Manager provides free SSL/TLS certificates with automatic renewal, eliminating the complexity and cost of traditional certificate management. CloudFront requires certificates to be provisioned in the us-east-1 region regardless of your distribution's global presence. The DNS validation method provides automated verification while maintaining security best practices.

   ```bash
   # Note: Certificate MUST be in us-east-1 for CloudFront
   export CERT_ARN=$(aws acm request-certificate \
       --domain-name "$DOMAIN_NAME" \
       --subject-alternative-names "$SUBDOMAIN" \
       --validation-method DNS \
       --region us-east-1 \
       --query CertificateArn --output text)
   
   echo "Certificate ARN: $CERT_ARN"
   echo "✅ Requested SSL certificate for both domains"
   
   # Wait for certificate to be created
   sleep 10
   ```

   The SSL certificate request is now processing with DNS validation enabled for both root and www domains. This certificate will provide end-to-end encryption for all website traffic and automatically renew before expiration, ensuring continuous security without manual intervention.

6. **Create DNS validation records for certificate**:

   Route 53 provides authoritative DNS services with global anycast network distribution, ensuring fast resolution times worldwide. DNS validation for SSL certificates creates cryptographic proof of domain ownership without requiring file-based verification. This process integrates seamlessly with AWS services while maintaining industry-standard security protocols for certificate issuance.

   ```bash
   # Get hosted zone ID for your domain
   export HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
       --dns-name "$DOMAIN_NAME" \
       --query "HostedZones[0].Id" --output text | cut -d'/' -f3)
   
   echo "Hosted Zone ID: $HOSTED_ZONE_ID"
   
   # Get certificate validation records and create DNS records automatically
   aws acm describe-certificate \
       --certificate-arn "$CERT_ARN" \
       --region us-east-1 \
       --query 'Certificate.DomainValidationOptions' --output json > cert-validation.json
   
   # Extract validation data and create Route 53 records
   for domain in $(cat cert-validation.json | jq -r '.[].DomainName'); do
       validation_name=$(cat cert-validation.json | jq -r --arg domain "$domain" '.[] | select(.DomainName == $domain) | .ResourceRecord.Name')
       validation_value=$(cat cert-validation.json | jq -r --arg domain "$domain" '.[] | select(.DomainName == $domain) | .ResourceRecord.Value')
       
       cat > validation-record-${domain}.json << EOF
   {
       "Changes": [
           {
               "Action": "UPSERT",
               "ResourceRecordSet": {
                   "Name": "$validation_name",
                   "Type": "CNAME",
                   "TTL": 300,
                   "ResourceRecords": [
                       {
                           "Value": "$validation_value"
                       }
                   ]
               }
           }
       ]
   }
   EOF
       
       aws route53 change-resource-record-sets \
           --hosted-zone-id "$HOSTED_ZONE_ID" \
           --change-batch file://validation-record-${domain}.json
   done
   
   echo "✅ Created DNS validation records"
   echo "Waiting for certificate validation..."
   aws acm wait certificate-validated \
       --certificate-arn "$CERT_ARN" \
       --region us-east-1
   echo "✅ Certificate validated successfully"
   ```

   The DNS validation records are now configured and the certificate has been validated. This automated approach eliminates manual DNS record creation and ensures the certificate is ready for use with CloudFront.

7. **Create CloudFront distribution for www subdomain**:

   CloudFront's global edge network spans 400+ locations worldwide, dramatically reducing latency by serving content from the nearest geographic location to each user. The CDN also provides DDoS protection, request/response transformation capabilities, and advanced caching strategies that can reduce origin load by 85% or more. This configuration enforces HTTPS connections and enables compression for optimal performance.

   ```bash
   # Create CloudFront distribution configuration
   cat > cloudfront-config.json << EOF
   {
       "CallerReference": "$(date +%s)-$WWW_BUCKET",
       "Comment": "CloudFront distribution for $SUBDOMAIN",
       "DefaultRootObject": "index.html",
       "Aliases": {
           "Quantity": 1,
           "Items": ["$SUBDOMAIN"]
       },
       "Origins": {
           "Quantity": 1,
           "Items": [
               {
                   "Id": "$WWW_BUCKET-origin",
                   "DomainName": "${WWW_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com",
                   "CustomOriginConfig": {
                       "HTTPPort": 80,
                       "HTTPSPort": 443,
                       "OriginProtocolPolicy": "http-only"
                   }
               }
           ]
       },
       "DefaultCacheBehavior": {
           "TargetOriginId": "$WWW_BUCKET-origin",
           "ViewerProtocolPolicy": "redirect-to-https",
           "Compress": true,
           "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
           "TrustedSigners": {
               "Enabled": false,
               "Quantity": 0
           },
           "ForwardedValues": {
               "QueryString": false,
               "Cookies": {
                   "Forward": "none"
               }
           },
           "MinTTL": 0
       },
       "Enabled": true,
       "PriceClass": "PriceClass_100",
       "ViewerCertificate": {
           "ACMCertificateArn": "$CERT_ARN",
           "SSLSupportMethod": "sni-only",
           "MinimumProtocolVersion": "TLSv1.2_2021"
       }
   }
   EOF
   
   # Create CloudFront distribution
   export CF_DISTRIBUTION_ID=$(aws cloudfront create-distribution \
       --distribution-config file://cloudfront-config.json \
       --query 'Distribution.Id' --output text)
   
   echo "CloudFront Distribution ID: $CF_DISTRIBUTION_ID"
   echo "✅ Created CloudFront distribution"
   echo "Distribution deployment may take 10-15 minutes..."
   ```

   The CloudFront distribution is now deploying across AWS's global edge network, which typically takes 10-15 minutes to complete. Once deployed, your website will benefit from sub-second loading times globally, automatic content compression, and enterprise-grade security features including DDoS protection.

8. **Create CloudFront distribution for root domain redirect**:

   Creating a separate CloudFront distribution for the root domain ensures consistent HTTPS redirect behavior and maintains professional URL standards. This approach provides reliable redirection at the edge while maintaining the same SSL certificate and security posture as the main website distribution.

   ```bash
   # Create CloudFront distribution for root domain redirect
   cat > cloudfront-redirect-config.json << EOF
   {
       "CallerReference": "$(date +%s)-$ROOT_BUCKET",
       "Comment": "CloudFront distribution for $DOMAIN_NAME redirect",
       "Aliases": {
           "Quantity": 1,
           "Items": ["$DOMAIN_NAME"]
       },
       "Origins": {
           "Quantity": 1,
           "Items": [
               {
                   "Id": "$ROOT_BUCKET-origin",
                   "DomainName": "${ROOT_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com",
                   "CustomOriginConfig": {
                       "HTTPPort": 80,
                       "HTTPSPort": 443,
                       "OriginProtocolPolicy": "http-only"
                   }
               }
           ]
       },
       "DefaultCacheBehavior": {
           "TargetOriginId": "$ROOT_BUCKET-origin",
           "ViewerProtocolPolicy": "redirect-to-https",
           "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
           "TrustedSigners": {
               "Enabled": false,
               "Quantity": 0
           },
           "ForwardedValues": {
               "QueryString": false,
               "Cookies": {
                   "Forward": "none"
               }
           },
           "MinTTL": 0
       },
       "Enabled": true,
       "PriceClass": "PriceClass_100",
       "ViewerCertificate": {
           "ACMCertificateArn": "$CERT_ARN",
           "SSLSupportMethod": "sni-only",
           "MinimumProtocolVersion": "TLSv1.2_2021"
       }
   }
   EOF
   
   # Create CloudFront distribution for redirect
   export CF_REDIRECT_ID=$(aws cloudfront create-distribution \
       --distribution-config file://cloudfront-redirect-config.json \
       --query 'Distribution.Id' --output text)
   
   echo "CloudFront Redirect Distribution ID: $CF_REDIRECT_ID"
   echo "✅ Created CloudFront redirect distribution"
   ```

   The redirect distribution is now deploying, providing consistent HTTPS redirect behavior from the root domain to the www subdomain. This ensures users accessing either domain variant will receive the same secure, fast experience.

9. **Create Route 53 DNS records**:

   Route 53 alias records provide seamless integration with CloudFront distributions without exposing underlying IP addresses. This approach enables automatic failover capabilities and eliminates the need for manual DNS updates when AWS modifies CloudFront infrastructure. The alias record also provides better performance than CNAME records by resolving directly to optimal endpoints.

   ```bash
   # Wait for distributions to be deployed
   echo "Waiting for CloudFront distributions to deploy..."
   aws cloudfront wait distribution-deployed \
       --id "$CF_DISTRIBUTION_ID"
   aws cloudfront wait distribution-deployed \
       --id "$CF_REDIRECT_ID"
   echo "✅ CloudFront distributions deployed"
   
   # Get CloudFront domain names
   export CF_DOMAIN_NAME=$(aws cloudfront get-distribution \
       --id "$CF_DISTRIBUTION_ID" \
       --query 'Distribution.DomainName' --output text)
   
   export CF_REDIRECT_DOMAIN=$(aws cloudfront get-distribution \
       --id "$CF_REDIRECT_ID" \
       --query 'Distribution.DomainName' --output text)
   
   echo "CloudFront WWW Domain: $CF_DOMAIN_NAME"
   echo "CloudFront Redirect Domain: $CF_REDIRECT_DOMAIN"
   
   # Create DNS records for both domains
   cat > dns-records.json << EOF
   {
       "Changes": [
           {
               "Action": "UPSERT",
               "ResourceRecordSet": {
                   "Name": "$SUBDOMAIN",
                   "Type": "A",
                   "AliasTarget": {
                       "DNSName": "$CF_DOMAIN_NAME",
                       "EvaluateTargetHealth": false,
                       "HostedZoneId": "Z2FDTNDATAQYW2"
                   }
               }
           },
           {
               "Action": "UPSERT",  
               "ResourceRecordSet": {
                   "Name": "$DOMAIN_NAME",
                   "Type": "A",
                   "AliasTarget": {
                       "DNSName": "$CF_REDIRECT_DOMAIN",
                       "EvaluateTargetHealth": false,
                       "HostedZoneId": "Z2FDTNDATAQYW2"
                   }
               }
           }
       ]
   }
   EOF
   
   # Apply DNS changes
   aws route53 change-resource-record-sets \
       --hosted-zone-id "$HOSTED_ZONE_ID" \
       --change-batch file://dns-records.json
   
   echo "✅ Created DNS records for both domains"
   ```

   The DNS configuration is now complete with alias records pointing to your CloudFront distributions. DNS propagation typically takes 1-5 minutes globally, after which your website will be accessible via both your root domain and www subdomain with full SSL encryption and global CDN acceleration.

## Validation & Testing

1. **Check S3 website endpoints**:

   ```bash
   # Test S3 website endpoints directly
   curl -I "http://${WWW_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com"
   curl -I "http://${ROOT_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com"
   ```

   Expected output: HTTP 200 OK for www bucket, HTTP 301 redirect for root bucket

2. **Verify CloudFront distribution status**:

   ```bash
   # Check CloudFront distribution deployment status
   aws cloudfront get-distribution \
       --id "$CF_DISTRIBUTION_ID" \
       --query 'Distribution.Status' --output text
   
   aws cloudfront get-distribution \
       --id "$CF_REDIRECT_ID" \
       --query 'Distribution.Status' --output text
   ```

   Expected output: "Deployed" for both distributions

3. **Test SSL certificate validation**:

   ```bash
   # Check certificate status
   aws acm describe-certificate \
       --certificate-arn "$CERT_ARN" \
       --region us-east-1 \
       --query 'Certificate.Status' --output text
   ```

   Expected output: "ISSUED"

4. **Test website accessibility**:

   ```bash
   # Test website via CloudFront
   curl -I "https://$SUBDOMAIN"
   
   # Test redirect from root domain
   curl -I "https://$DOMAIN_NAME"
   
   # Test SSL certificate
   openssl s_client -connect "$SUBDOMAIN:443" -servername "$SUBDOMAIN" \
       -verify_return_error < /dev/null
   ```

   Expected: HTTP 200 for subdomain, HTTP 301 redirect for root domain, valid SSL certificate

## Cleanup

1. **Delete Route 53 DNS records**:

   ```bash
   # Delete DNS records
   cat > delete-dns-records.json << EOF
   {
       "Changes": [
           {
               "Action": "DELETE",
               "ResourceRecordSet": {
                   "Name": "$SUBDOMAIN",
                   "Type": "A",
                   "AliasTarget": {
                       "DNSName": "$CF_DOMAIN_NAME",
                       "EvaluateTargetHealth": false,
                       "HostedZoneId": "Z2FDTNDATAQYW2"
                   }
               }
           },
           {
               "Action": "DELETE",
               "ResourceRecordSet": {
                   "Name": "$DOMAIN_NAME",
                   "Type": "A",
                   "AliasTarget": {
                       "DNSName": "$CF_REDIRECT_DOMAIN",
                       "EvaluateTargetHealth": false,
                       "HostedZoneId": "Z2FDTNDATAQYW2"
                   }
               }
           }
       ]
   }
   EOF
   
   aws route53 change-resource-record-sets \
       --hosted-zone-id "$HOSTED_ZONE_ID" \
       --change-batch file://delete-dns-records.json
   
   echo "✅ Deleted DNS records"
   ```

2. **Delete CloudFront distributions**:

   ```bash
   # Disable and delete CloudFront distributions
   aws cloudfront get-distribution-config \
       --id "$CF_DISTRIBUTION_ID" > cf-config.json
   
   ETAG=$(aws cloudfront get-distribution-config \
       --id "$CF_DISTRIBUTION_ID" \
       --query 'ETag' --output text)
   
   # Update distribution config to disabled (simplified JSON editing)
   cat cf-config.json | jq '.DistributionConfig.Enabled = false' > cf-config-disabled.json
   
   aws cloudfront update-distribution \
       --id "$CF_DISTRIBUTION_ID" \
       --distribution-config file://cf-config-disabled.json \
       --if-match "$ETAG"
   
   # Wait for distribution to be disabled, then delete
   aws cloudfront wait distribution-deployed --id "$CF_DISTRIBUTION_ID"
   
   ETAG_DISABLED=$(aws cloudfront get-distribution \
       --id "$CF_DISTRIBUTION_ID" \
       --query 'ETag' --output text)
   
   aws cloudfront delete-distribution \
       --id "$CF_DISTRIBUTION_ID" \
       --if-match "$ETAG_DISABLED"
   
   # Repeat for redirect distribution
   aws cloudfront get-distribution-config \
       --id "$CF_REDIRECT_ID" > cf-redirect-config.json
   
   ETAG_REDIRECT=$(aws cloudfront get-distribution-config \
       --id "$CF_REDIRECT_ID" \
       --query 'ETag' --output text)
   
   cat cf-redirect-config.json | jq '.DistributionConfig.Enabled = false' > cf-redirect-disabled.json
   
   aws cloudfront update-distribution \
       --id "$CF_REDIRECT_ID" \
       --distribution-config file://cf-redirect-disabled.json \
       --if-match "$ETAG_REDIRECT"
   
   aws cloudfront wait distribution-deployed --id "$CF_REDIRECT_ID"
   
   ETAG_REDIRECT_DISABLED=$(aws cloudfront get-distribution \
       --id "$CF_REDIRECT_ID" \
       --query 'ETag' --output text)
   
   aws cloudfront delete-distribution \
       --id "$CF_REDIRECT_ID" \
       --if-match "$ETAG_REDIRECT_DISABLED"
   
   echo "✅ Deleted CloudFront distributions"
   ```

3. **Delete SSL certificate validation records**:

   ```bash
   # Delete certificate validation records
   for domain in $(cat cert-validation.json | jq -r '.[].DomainName'); do
       validation_name=$(cat cert-validation.json | jq -r --arg domain "$domain" '.[] | select(.DomainName == $domain) | .ResourceRecord.Name')
       validation_value=$(cat cert-validation.json | jq -r --arg domain "$domain" '.[] | select(.DomainName == $domain) | .ResourceRecord.Value')
       
       cat > delete-validation-${domain}.json << EOF
   {
       "Changes": [
           {
               "Action": "DELETE",
               "ResourceRecordSet": {
                   "Name": "$validation_name",
                   "Type": "CNAME",
                   "TTL": 300,
                   "ResourceRecords": [
                       {
                           "Value": "$validation_value"
                       }
                   ]
               }
           }
       ]
   }
   EOF
       
       aws route53 change-resource-record-sets \
           --hosted-zone-id "$HOSTED_ZONE_ID" \
           --change-batch file://delete-validation-${domain}.json
   done
   
   echo "✅ Deleted certificate validation records"
   ```

4. **Delete SSL certificate**:

   ```bash
   # Delete SSL certificate (only after CloudFront is deleted)
   aws acm delete-certificate \
       --certificate-arn "$CERT_ARN" \
       --region us-east-1
   
   echo "✅ Deleted SSL certificate"
   ```

5. **Delete S3 buckets and content**:

   ```bash
   # Delete website content
   aws s3 rm "s3://$WWW_BUCKET" --recursive
   aws s3 rm "s3://$ROOT_BUCKET" --recursive
   
   # Delete buckets
   aws s3api delete-bucket --bucket "$WWW_BUCKET"
   aws s3api delete-bucket --bucket "$ROOT_BUCKET"
   
   # Clean up local files
   rm -f index.html error.html bucket-policy.json
   rm -f redirect-config.json cloudfront-config.json cloudfront-redirect-config.json
   rm -f dns-records.json delete-dns-records.json
   rm -f cert-validation.json validation-record-*.json delete-validation-*.json
   rm -f cf-config.json cf-config-disabled.json cf-redirect-config.json cf-redirect-disabled.json
   
   echo "✅ Deleted S3 buckets and cleaned up files"
   ```

## Discussion

This static website hosting architecture provides several key advantages over traditional web hosting solutions. Amazon S3 offers virtually unlimited storage capacity with 99.999999999% (11 9's) durability, making it ideal for hosting static assets. The integration with CloudFront provides global content delivery through AWS's extensive edge network, dramatically reducing latency for users worldwide while also providing DDoS protection and traffic encryption.

The combination of Route 53 and Certificate Manager enables seamless SSL/TLS certificate management with automatic renewal, eliminating the complexity of manual certificate updates. Route 53's health checks and failover capabilities ensure high availability, while its integration with other AWS services provides superior performance compared to external DNS providers. The architecture scales automatically to handle traffic spikes without any manual intervention, following [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html) principles.

Cost optimization is achieved through CloudFront's edge caching, which reduces origin requests to S3, and S3's pay-per-use pricing model. For most small to medium websites, monthly costs typically range from $0.50 to $5.00, significantly lower than traditional hosting solutions. The architecture also supports modern development workflows with easy integration into CI/CD pipelines for automated deployments. According to [AWS CloudFront pricing](https://aws.amazon.com/cloudfront/pricing/), the first 1TB of data transfer out is free each month, making this solution extremely cost-effective for most use cases.

Security is built into every layer of this architecture. S3 bucket policies enforce least privilege access, CloudFront provides DDoS protection and WAF integration capabilities, and ACM provides automatic SSL/TLS certificate management with strong encryption standards. The solution also supports advanced security features like [AWS WAF integration](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/distribution-web-awswaf.html) for additional protection against common web exploits.

> **Warning**: Ensure your domain's DNS is properly configured in Route 53 before requesting SSL certificates, as validation failures can delay deployment.

> **Tip**: Enable CloudFront access logging to analyze visitor patterns and optimize caching strategies for better performance. See the [CloudFront logging documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/AccessLogs.html) for details.

## Challenge

Extend this solution by implementing these enhancements:

1. **Add CloudFront Functions for URL rewriting** - Implement client-side routing for single-page applications by redirecting all requests to index.html using [CloudFront Functions](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cloudfront-functions.html)
2. **Implement automated deployments with CodePipeline** - Create a CI/CD pipeline that automatically deploys changes from a Git repository to S3 and invalidates CloudFront cache using [AWS CodePipeline](https://docs.aws.amazon.com/codepipeline/latest/userguide/welcome.html)
3. **Add security headers with Lambda@Edge** - Implement security best practices by adding HTTP security headers like CSP, HSTS, and X-Frame-Options using [Lambda@Edge](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/lambda-at-the-edge.html)
4. **Set up monitoring and alerting** - Create CloudWatch dashboards and alarms for monitoring website performance, error rates, and costs using [CloudWatch](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)
5. **Implement multi-environment deployment** - Create separate staging and production environments with different S3 buckets and CloudFront distributions using [AWS Organizations](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_introduction.html) for account separation

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*