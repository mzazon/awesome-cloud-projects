---
title: Sharing Files Securely with Web Portals
id: a7b8c9d0
category: storage
difficulty: 200
subject: aws
services: AWS Transfer Family, S3, IAM Identity Center, CloudTrail
estimated-time: 60 minutes
recipe-version: 1.0
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: null
passed-qa: null
tags: file-sharing, web-portal, identity-management, secure-access, zero-trust
recipe-generator-version: 1.3
---

# Sharing Files Securely with Web Portals

## Problem

Organizations need to provide secure file sharing capabilities for external partners, vendors, and non-technical users without requiring specialized FTP clients or AWS console access. Traditional file sharing solutions often lack granular access controls, proper audit trails, and integration with corporate identity systems, creating security risks, compliance gaps, and operational overhead when managing file access across diverse user populations.

## Solution

AWS Transfer Family Web Apps provide a fully managed, browser-based file sharing portal that integrates seamlessly with your existing identity infrastructure. This solution combines S3's secure object storage with IAM Identity Center's authentication and fine-grained authorization to create a zero-trust file sharing environment with comprehensive audit logging through CloudTrail.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Identity Layer"
        IDC[IAM Identity Center]
        IDP[Corporate Identity Provider]
    end
    
    subgraph "Application Layer"
        WEBAPP[Transfer Family Web App]
        ACCESS[S3 Access Grants]
    end
    
    subgraph "Storage Layer"
        S3[S3 Buckets]
        LIFECYCLE[Lifecycle Policies]
    end
    
    subgraph "Monitoring Layer"
        TRAIL[CloudTrail]
        LOGS[CloudWatch Logs]
    end
    
    IDP --> IDC
    IDC --> WEBAPP
    WEBAPP --> ACCESS
    ACCESS --> S3
    S3 --> LIFECYCLE
    WEBAPP --> TRAIL
    TRAIL --> LOGS
    
    style WEBAPP fill:#FF9900
    style ACCESS fill:#3F8624
    style S3 fill:#569A31
    style TRAIL fill:#FF4B4B
```

## Prerequisites

1. AWS account with administrative permissions for IAM Identity Center, Transfer Family, S3, and CloudTrail
2. AWS CLI v2 installed and configured (or AWS CloudShell)
3. Basic understanding of AWS identity services and S3 storage concepts
4. Corporate identity provider (optional for enhanced security)
5. Estimated cost: $10-25 per month for development/testing workloads

> **Note**: This recipe follows AWS Well-Architected Framework principles for security, reliability, and operational excellence. See [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html) for additional guidance.

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

# Set resource names
export BUCKET_NAME="secure-files-${RANDOM_SUFFIX}"
export WEBAPP_NAME="secure-file-portal-${RANDOM_SUFFIX}"
export TRAIL_NAME="file-sharing-audit-${RANDOM_SUFFIX}"

# Create S3 bucket for file storage
aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}

# Enable versioning and encryption
aws s3api put-bucket-versioning \
    --bucket ${BUCKET_NAME} \
    --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
    --bucket ${BUCKET_NAME} \
    --server-side-encryption-configuration \
    'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'

# Enable public access block for security
aws s3api put-public-access-block \
    --bucket ${BUCKET_NAME} \
    --public-access-block-configuration \
    'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'

echo "✅ AWS environment configured with secure S3 bucket"
```

## Steps

1. **Enable IAM Identity Center**:

   IAM Identity Center serves as the central identity provider for your Transfer Family web app, providing secure authentication and user management capabilities. This AWS managed service eliminates the need for separate user databases while supporting integration with existing corporate identity systems like Active Directory, Azure AD, or external SAML/OIDC providers for seamless single sign-on experiences.

   ```bash
   # Check if Identity Center is already enabled
   EXISTING_INSTANCE=$(aws sso-admin list-instances \
       --query 'Instances[0].InstanceArn' --output text 2>/dev/null)
   
   if [ "$EXISTING_INSTANCE" != "None" ] && [ -n "$EXISTING_INSTANCE" ]; then
       echo "Identity Center already enabled"
       IDENTITY_CENTER_ARN=$EXISTING_INSTANCE
   else
       # Enable IAM Identity Center
       aws sso-admin create-instance \
           --name "SecureFileSharing" \
           --description "Identity Center for secure file sharing portal"
       
       # Get the newly created instance ARN
       IDENTITY_CENTER_ARN=$(aws sso-admin list-instances \
           --query 'Instances[0].InstanceArn' --output text)
   fi
   
   # Get the Identity Store ID
   IDENTITY_STORE_ID=$(aws sso-admin list-instances \
       --query 'Instances[0].IdentityStoreId' --output text)
   
   echo "✅ IAM Identity Center enabled with ARN: ${IDENTITY_CENTER_ARN}"
   ```

   The Identity Center instance now provides the foundation for secure user authentication and authorization, supporting both internal users and external partners through a unified identity management system that integrates with your existing corporate directory services.

2. **Create Test User in Identity Center**:

   Creating a test user demonstrates the user onboarding process and provides a way to validate the complete authentication flow. This user will represent the typical end-user experience when accessing the file sharing portal through the web interface.

   ```bash
   # Create a test user in Identity Center
   aws identitystore create-user \
       --identity-store-id ${IDENTITY_STORE_ID} \
       --user-name "testuser" \
       --display-name "Test User" \
       --name '{"FamilyName":"User","GivenName":"Test"}' \
       --emails '[{"Value":"testuser@example.com","Type":"Work","Primary":true}]'
   
   # Get the user ID
   USER_ID=$(aws identitystore list-users \
       --identity-store-id ${IDENTITY_STORE_ID} \
       --query 'Users[?UserName==`testuser`].UserId' --output text)
   
   echo "✅ Test user created with ID: ${USER_ID}"
   ```

   The test user is now available in the Identity Center directory and can be assigned specific permissions through IAM policies and roles, enabling fine-grained access control for different user roles within your organization.

3. **Create IAM Role for Transfer Family**:

   The Transfer Family service requires an IAM role to access S3 resources on behalf of authenticated users. This role implements the principle of least privilege while providing necessary permissions for file operations within the designated S3 bucket.

   ```bash
   # Create trust policy for Transfer Family
   cat > transfer-trust-policy.json << EOF
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Effect": "Allow",
               "Principal": {
                   "Service": "transfer.amazonaws.com"
               },
               "Action": "sts:AssumeRole"
           }
       ]
   }
   EOF
   
   # Create IAM role
   aws iam create-role \
       --role-name TransferFamilyRole-${RANDOM_SUFFIX} \
       --assume-role-policy-document file://transfer-trust-policy.json
   
   # Create S3 access policy
   cat > s3-access-policy.json << EOF
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Effect": "Allow",
               "Action": [
                   "s3:GetObject",
                   "s3:PutObject",
                   "s3:DeleteObject",
                   "s3:ListBucket"
               ],
               "Resource": [
                   "arn:aws:s3:::${BUCKET_NAME}",
                   "arn:aws:s3:::${BUCKET_NAME}/*"
               ]
           }
       ]
   }
   EOF
   
   # Attach policy to role
   aws iam put-role-policy \
       --role-name TransferFamilyRole-${RANDOM_SUFFIX} \
       --policy-name S3AccessPolicy \
       --policy-document file://s3-access-policy.json
   
   # Get role ARN
   ROLE_ARN=$(aws iam get-role \
       --role-name TransferFamilyRole-${RANDOM_SUFFIX} \
       --query 'Role.Arn' --output text)
   
   echo "✅ IAM role created: ${ROLE_ARN}"
   ```

   The IAM role now provides Transfer Family with the necessary permissions to manage S3 objects while maintaining security boundaries and enabling proper access control for file operations.

4. **Create CloudTrail for Audit Logging**:

   CloudTrail provides comprehensive audit logging for all file sharing activities, enabling compliance monitoring, security analysis, and operational troubleshooting. This creates an immutable record of all user actions and system events for regulatory compliance and security analysis.

   ```bash
   # Create CloudTrail for audit logging
   aws cloudtrail create-trail \
       --name ${TRAIL_NAME} \
       --s3-bucket-name ${BUCKET_NAME} \
       --s3-key-prefix "audit-logs/" \
       --include-global-service-events \
       --is-multi-region-trail \
       --enable-log-file-validation
   
   # Enable data events for S3 bucket
   aws cloudtrail put-event-selectors \
       --trail-name ${TRAIL_NAME} \
       --event-selectors \
       'ReadWriteType=All,IncludeManagementEvents=true,DataResources=[{Type=AWS::S3::Object,Values=["arn:aws:s3:::'${BUCKET_NAME}'/*"]}]'
   
   # Start logging
   aws cloudtrail start-logging --name ${TRAIL_NAME}
   
   echo "✅ CloudTrail configured for comprehensive audit logging"
   ```

   CloudTrail now captures all file access events and API calls, providing detailed audit trails for compliance requirements and security monitoring while supporting forensic analysis of user activities and system behavior.

5. **Create Transfer Family Server**:

   The Transfer Family server provides the underlying infrastructure for secure file transfer operations with support for multiple protocols and authentication methods. This managed service handles the complexity of secure file transfer while integrating with AWS identity and storage services.

   ```bash
   # Create Transfer Family server
   aws transfer create-server \
       --identity-provider-type SERVICE_MANAGED \
       --logging-role ${ROLE_ARN} \
       --protocols SFTP \
       --endpoint-type PUBLIC
   
   # Get server ID
   SERVER_ID=$(aws transfer list-servers \
       --query 'Servers[0].ServerId' --output text)
   
   # Wait for server to be online
   aws transfer wait server-online --server-id ${SERVER_ID}
   
   echo "✅ Transfer Family server created with ID: ${SERVER_ID}"
   ```

   The Transfer Family server is now available with secure SFTP protocol support, providing the foundation for secure file transfer operations while maintaining enterprise-grade security controls and audit logging capabilities.

6. **Create Web App Configuration**:

   The Transfer Family web app provides a secure, browser-based interface for file sharing operations without requiring specialized client software or technical expertise. This fully managed service handles authentication, authorization, and file transfer operations through a user-friendly web interface.

   ```bash
   # Create web app configuration
   aws transfer create-web-app \
       --identity-provider-type SERVICE_MANAGED \
       --access-endpoint-type PUBLIC \
       --web-app-units 1 \
       --tags Key=Environment,Value=Development \
       Key=Purpose,Value=SecureFileSharing
   
   # Get web app ID
   WEBAPP_ID=$(aws transfer list-web-apps \
       --query 'WebApps[0].WebAppId' --output text)
   
   # Wait for web app to be available
   aws transfer wait web-app-available --web-app-id ${WEBAPP_ID}
   
   # Get web app endpoint
   WEBAPP_ENDPOINT=$(aws transfer describe-web-app \
       --web-app-id ${WEBAPP_ID} \
       --query 'WebApp.AccessEndpoint' --output text)
   
   echo "✅ Transfer Family web app created with endpoint: ${WEBAPP_ENDPOINT}"
   ```

   The web app is now available with secure authentication and provides a user-friendly interface for file sharing operations while maintaining enterprise security and compliance requirements through integrated audit logging and access controls.

7. **Create User for Web App Access**:

   Creating a user account specifically for the web app demonstrates the user management capabilities and provides authentication credentials for accessing the secure file sharing portal. This user will have defined permissions and access restrictions based on business requirements.

   ```bash
   # Create user for web app access
   aws transfer create-user \
       --server-id ${SERVER_ID} \
       --user-name testuser \
       --role ${ROLE_ARN} \
       --home-directory /${BUCKET_NAME} \
       --home-directory-type LOGICAL \
       --home-directory-mappings \
       'Entry="/",Target="/'${BUCKET_NAME}'"' \
       --tags Key=Department,Value=IT Key=AccessLevel,Value=Standard
   
   # Set password for user
   aws transfer import-ssh-public-key \
       --server-id ${SERVER_ID} \
       --user-name testuser \
       --ssh-public-key-body "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7..." 2>/dev/null || echo "SSH key not provided - password authentication will be used"
   
   echo "✅ User account created for web app access"
   ```

   The user account is now configured with appropriate S3 access permissions and home directory mappings, enabling secure file operations through the web interface while maintaining proper access controls and audit logging.

8. **Create Sample Files and Directory Structure**:

   Creating a sample file structure demonstrates the organizational capabilities and provides test data for validation. This structure shows how different file types and organizational patterns can be implemented within the secure file sharing environment.

   ```bash
   # Create sample directory structure
   mkdir -p test-files/{uploads,shared,archive}
   
   # Create sample files
   echo "Welcome to Secure File Sharing Portal" > test-files/welcome.txt
   echo "Sample document for testing upload functionality" > test-files/uploads/sample.txt
   echo "Shared resource document for collaboration" > test-files/shared/resource.txt
   echo "Archived document for long-term storage" > test-files/archive/archive.txt
   
   # Upload sample files to S3
   aws s3 cp test-files/ s3://${BUCKET_NAME}/ --recursive
   
   # Set lifecycle policy for archive folder
   cat > lifecycle-policy.json << EOF
   {
       "Rules": [
           {
               "ID": "ArchiveRule",
               "Status": "Enabled",
               "Filter": {
                   "Prefix": "archive/"
               },
               "Transitions": [
                   {
                       "Days": 30,
                       "StorageClass": "STANDARD_IA"
                   },
                   {
                       "Days": 90,
                       "StorageClass": "GLACIER"
                   }
               ]
           }
       ]
   }
   EOF
   
   aws s3api put-bucket-lifecycle-configuration \
       --bucket ${BUCKET_NAME} \
       --lifecycle-configuration file://lifecycle-policy.json
   
   echo "✅ Sample files uploaded with lifecycle policies configured"
   ```

   The sample file structure now demonstrates different access patterns and organizational approaches while showcasing cost optimization through automated lifecycle management that transitions files to lower-cost storage classes over time.

## Validation & Testing

1. **Verify Transfer Family Server Configuration**:

   ```bash
   # Check server status
   aws transfer describe-server \
       --server-id ${SERVER_ID} \
       --query 'Server.{State:State,EndpointType:EndpointType,Protocols:Protocols}'
   
   # Verify user configuration
   aws transfer describe-user \
       --server-id ${SERVER_ID} \
       --user-name testuser \
       --query 'User.{UserName:UserName,HomeDirectory:HomeDirectory,Role:Role}'
   ```

   Expected output: Server should show "ONLINE" state with PUBLIC endpoint type and SFTP protocol. User should have proper home directory and role configuration.

2. **Test Web App Accessibility**:

   ```bash
   # Get web app status
   aws transfer describe-web-app \
       --web-app-id ${WEBAPP_ID} \
       --query 'WebApp.{State:State,AccessEndpoint:AccessEndpoint}'
   
   # Test endpoint accessibility
   curl -I ${WEBAPP_ENDPOINT} 2>/dev/null | head -n 1
   ```

   Expected output: Web app should show "AVAILABLE" state and endpoint should respond with HTTP 200 or redirect status.

3. **Verify CloudTrail Logging**:

   ```bash
   # Check CloudTrail status
   aws cloudtrail get-trail-status \
       --name ${TRAIL_NAME} \
       --query 'IsLogging'
   
   # Verify recent log delivery
   aws cloudtrail lookup-events \
       --lookup-attributes AttributeKey=EventName,AttributeValue=CreateUser \
       --max-items 1 \
       --query 'Events[0].{EventName:EventName,EventTime:EventTime}'
   ```

   Expected output: CloudTrail should show "true" for IsLogging and recent events should be captured in the audit logs.

4. **Test S3 Bucket Security**:

   ```bash
   # Verify bucket encryption
   aws s3api get-bucket-encryption \
       --bucket ${BUCKET_NAME} \
       --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm'
   
   # Check public access block
   aws s3api get-public-access-block \
       --bucket ${BUCKET_NAME} \
       --query 'PublicAccessBlockConfiguration.{BlockPublicAcls:BlockPublicAcls,RestrictPublicBuckets:RestrictPublicBuckets}'
   ```

   Expected output: Bucket should have AES256 encryption enabled and public access should be blocked for security.

## Cleanup

1. **Delete Transfer Family Resources**:

   ```bash
   # Delete user
   aws transfer delete-user \
       --server-id ${SERVER_ID} \
       --user-name testuser
   
   # Delete web app
   aws transfer delete-web-app --web-app-id ${WEBAPP_ID}
   
   # Wait for web app deletion
   aws transfer wait web-app-deleted --web-app-id ${WEBAPP_ID}
   
   # Delete server
   aws transfer delete-server --server-id ${SERVER_ID}
   
   echo "✅ Transfer Family resources deleted"
   ```

2. **Stop CloudTrail and Clean Up**:

   ```bash
   # Stop CloudTrail logging
   aws cloudtrail stop-logging --name ${TRAIL_NAME}
   
   # Delete CloudTrail
   aws cloudtrail delete-trail --name ${TRAIL_NAME}
   
   echo "✅ CloudTrail resources cleaned up"
   ```

3. **Remove IAM Role and Policies**:

   ```bash
   # Delete inline policy
   aws iam delete-role-policy \
       --role-name TransferFamilyRole-${RANDOM_SUFFIX} \
       --policy-name S3AccessPolicy
   
   # Delete IAM role
   aws iam delete-role --role-name TransferFamilyRole-${RANDOM_SUFFIX}
   
   echo "✅ IAM role and policies removed"
   ```

4. **Remove S3 Bucket and Contents**:

   ```bash
   # Delete all objects in bucket
   aws s3 rm s3://${BUCKET_NAME} --recursive
   
   # Delete bucket lifecycle configuration
   aws s3api delete-bucket-lifecycle --bucket ${BUCKET_NAME}
   
   # Delete bucket
   aws s3 rb s3://${BUCKET_NAME}
   
   # Clean up local files
   rm -rf test-files/
   rm -f transfer-trust-policy.json s3-access-policy.json lifecycle-policy.json
   
   echo "✅ S3 bucket and local files removed"
   ```

## Discussion

AWS Transfer Family Web Apps represent a significant advancement in secure file sharing capabilities, combining enterprise-grade security with user-friendly interfaces that require no specialized client software. The integration with IAM Identity Center provides centralized identity management while S3's robust security features enable fine-grained access controls that follow zero-trust principles. This architecture eliminates the need for traditional FTP servers or complex VPN configurations while maintaining comprehensive audit trails through CloudTrail.

The solution leverages AWS's principle of least privilege by granting users only the minimum permissions necessary for their specific roles and responsibilities. The Transfer Family service automatically manages secure connections and file transfer operations, reducing the risk of security vulnerabilities while supporting various authentication methods including SSH keys, passwords, and integration with corporate identity providers. The web-based interface makes file sharing accessible to non-technical users while maintaining enterprise security standards.

Performance and scalability are inherent benefits of this fully managed architecture. The Transfer Family web app automatically scales to handle varying loads without manual intervention, while S3 provides virtually unlimited storage capacity with multiple durability and availability options. CloudTrail ensures comprehensive logging for compliance requirements while supporting advanced analytics through integration with CloudWatch, AWS Config, and third-party SIEM solutions for enhanced security monitoring.

> **Tip**: Enable S3 Cross-Region Replication for critical files to ensure business continuity and disaster recovery capabilities. The [S3 Cross-Region Replication documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html) provides detailed configuration guidance for implementing multi-region data protection strategies.

The architecture supports various compliance frameworks including SOC 2, HIPAA, PCI DSS, and FedRAMP through AWS's comprehensive security controls and audit capabilities. Organizations can implement additional security measures such as IP allowlists, custom branding, and integration with existing monitoring systems to meet specific regulatory or business requirements. For detailed security guidance, refer to the [AWS Transfer Family Security documentation](https://docs.aws.amazon.com/transfer/latest/userguide/security.html), [S3 Security Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html), and [IAM Identity Center implementation guidance](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html).

## Challenge

Extend this solution by implementing these enhancements:

1. **Implement Custom Branding and Domain**: Configure custom logos, colors, and a custom domain name for the web app to match your corporate identity using Transfer Family's branding features and Route 53 DNS management.

2. **Add Multi-Factor Authentication**: Integrate MFA requirements through IAM Identity Center or external identity providers to strengthen authentication security for sensitive file operations and administrative access.

3. **Create Automated File Processing Workflows**: Use S3 Event Notifications with Lambda functions to automatically process uploaded files through workflows such as virus scanning, format conversion, metadata extraction, or content classification.

4. **Implement Advanced Access Controls**: Configure IP-based access restrictions, time-based access controls, and conditional permissions using IAM policies and bucket policies for enhanced security and compliance requirements.

5. **Add Comprehensive Monitoring and Alerting**: Create CloudWatch dashboards, custom metrics, and automated alerts to monitor file sharing activities, detect anomalous behavior, track usage patterns, and alert administrators to potential security incidents or capacity issues.

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*