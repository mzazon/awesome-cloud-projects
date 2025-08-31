---
title: Automated Data Archiving with S3 Glacier
id: a7b3c8e2
category: storage
difficulty: 200
subject: aws
services: S3, Glacier, SNS
estimated-time: 60 minutes
recipe-version: 1.3
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: storage, s3, glacier, archiving, lifecycle, cost-optimization
recipe-generator-version: 1.3
---

# Automated Data Archiving with S3 Glacier

## Problem

Your organization has accumulated a large amount of data that is rarely accessed but must be retained for regulatory compliance. This data is currently stored in Amazon S3 Standard storage, which is cost-inefficient for long-term retention of infrequently accessed data. You need an automated solution to identify and archive this data to reduce storage costs while maintaining compliance.

## Solution

Implement an automated data archiving solution using Amazon S3 Lifecycle policies and S3 Glacier storage classes. You'll set up a tiered archiving strategy that automatically transitions objects from S3 Standard to S3 Glacier Flexible Retrieval based on age, and eventually to S3 Glacier Deep Archive for extremely low-cost long-term storage. This approach optimizes storage costs while ensuring data remains accessible when needed.

## Architecture Diagram

```mermaid
flowchart TD
    subgraph "Amazon S3"
        S3Standard("S3 Standard\n(Active Data)")
        S3GlacierFlexible("S3 Glacier Flexible Retrieval\n(90+ days old)")
        S3GlacierDeep("S3 Glacier Deep Archive\n(1+ year old)")
    end
    
    S3Standard -->|After 90 days| S3GlacierFlexible
    S3GlacierFlexible -->|After 365 days| S3GlacierDeep
    
    User[User/Application] -->|Upload Data| S3Standard
    User -->|Restore Request| S3GlacierFlexible
    User -->|Restore Request| S3GlacierDeep
    
    AWS_LifecycleRules[S3 Lifecycle Rules] -->|Manage Transitions| S3Standard
    AWS_LifecycleRules -->|Manage Transitions| S3GlacierFlexible
    AWS_LifecycleRules -->|Manage Transitions| S3GlacierDeep
    
    SNS[Amazon SNS] -->|Notifications| User
    S3Standard -.->|Event Notifications| SNS
```

## Prerequisites

1. AWS account with administrator access or IAM permissions for S3, SNS, and Glacier operations
2. AWS CLI installed and configured (version 2.0 or later)
3. Basic knowledge of Amazon S3 storage classes and their cost implications
4. Understanding of your organization's data retention requirements and access patterns
5. Estimated cost: $0.01-$5 per month for this demonstration (varies by region and data volume)

> **Note**: The cost savings of using S3 Glacier storage classes come with trade-offs in data retrieval speed and potential retrieval fees. Make sure you understand these trade-offs before implementing this solution in a production environment.

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

export BUCKET_NAME="data-archive-${AWS_ACCOUNT_ID:0:8}-${RANDOM_SUFFIX}"

echo "✅ Environment variables set successfully"
echo "Region: $AWS_REGION"
echo "Account ID: $AWS_ACCOUNT_ID"
echo "Bucket Name: $BUCKET_NAME"
```

## Steps

1. **Create S3 bucket for data archiving**:

   Amazon S3 provides the foundation for our automated archiving solution with its 99.999999999% (11 9's) durability and virtually unlimited storage capacity. Creating a dedicated bucket establishes the secure, scalable repository that will handle your organization's long-term data retention requirements while supporting automated lifecycle management.

   ```bash
   # Create the S3 bucket for our archiving demonstration
   if [ "$AWS_REGION" = "us-east-1" ]; then
       aws s3api create-bucket --bucket $BUCKET_NAME
   else
       aws s3api create-bucket --bucket $BUCKET_NAME \
           --region $AWS_REGION \
           --create-bucket-configuration \
           LocationConstraint=$AWS_REGION
   fi
   
   echo "✅ Created S3 bucket: $BUCKET_NAME"
   ```

   The bucket is now established as your data archive foundation, ready to receive objects and apply automated lifecycle policies. The region-specific configuration ensures compliance with data residency requirements and optimizes performance for your geographic location.

2. **Upload sample data to demonstrate the archiving process**:

   S3's object-based storage model allows for flexible data organization using prefixes (logical folders) that enable targeted lifecycle management. By uploading sample data with consistent prefixes, we establish the organizational structure that allows lifecycle policies to intelligently identify and manage different data categories based on business requirements.

   ```bash
   # Create sample files for demonstration
   echo "This is a sample file for S3 Glacier archiving demonstration" \
       > sample-data.txt
   
   # Upload the primary sample file
   aws s3 cp sample-data.txt s3://$BUCKET_NAME/data/
   
   # Create additional test files with timestamps for easy identification
   for i in {1..5}; do
       echo "Test file $i created on $(date)" > test-file-$i.txt
       aws s3 cp test-file-$i.txt s3://$BUCKET_NAME/data/
   done
   
   echo "✅ Uploaded sample data files to s3://$BUCKET_NAME/data/"
   ```

   The data is now stored in S3 Standard storage class with immediate availability and high performance. The `data/` prefix creates a logical namespace that enables granular lifecycle policy application, allowing different retention policies for different types of organizational data.

   > **Note**: S3 lifecycle policies work based on object modification time, not creation time. This means objects are evaluated for transition based on when they were last modified, which is important for understanding [S3 lifecycle policy behavior](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html).

3. **Create and configure the lifecycle policy for automated archiving**:

   S3 Lifecycle policies provide automated data management that can reduce storage costs by up to 90% through intelligent tiering. This policy implements a three-tier archiving strategy that balances cost optimization with data accessibility, automatically moving data through progressively cheaper storage classes based on age and access patterns.

   ```bash
   # Create the lifecycle policy JSON configuration
   cat > lifecycle-policy.json << 'EOF'
   {
       "Rules": [
           {
               "ID": "ArchiveRule",
               "Status": "Enabled",
               "Filter": {
                   "Prefix": "data/"
               },
               "Transitions": [
                   {
                       "Days": 90,
                       "StorageClass": "GLACIER"
                   },
                   {
                       "Days": 365,
                       "StorageClass": "DEEP_ARCHIVE"
                   }
               ]
           }
       ]
   }
   EOF
   
   echo "✅ Created lifecycle policy configuration"
   ```

   This configuration establishes automatic cost optimization without manual intervention. The 90-day transition to Glacier Flexible Retrieval reduces storage costs by approximately 68%, while the 365-day transition to Deep Archive can reduce costs by up to 95% compared to S3 Standard storage.

   > **Tip**: You can create more sophisticated lifecycle rules using object tagging instead of just prefix-based filtering. This allows for more granular control over which objects are archived when. For example, you could tag objects with different retention periods based on data type or department. Learn more about [S3 object lifecycle management](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html).

4. **Apply the lifecycle policy to your S3 bucket**:

   Activating the lifecycle policy transforms your S3 bucket into an intelligent, self-managing archive system. S3's lifecycle engine runs daily evaluations of all objects, automatically executing transitions without requiring any manual intervention or operational overhead, ensuring consistent cost optimization across your entire data estate.

   ```bash
   # Apply the lifecycle configuration to the bucket
   aws s3api put-bucket-lifecycle-configuration \
       --bucket $BUCKET_NAME \
       --lifecycle-configuration file://lifecycle-policy.json
   
   echo "✅ Applied lifecycle policy to bucket $BUCKET_NAME"
   ```

   The bucket now operates with automated data lifecycle management, providing immediate operational benefits through reduced manual processes and long-term financial benefits through optimized storage costs. This automation eliminates the risk of human error in data management decisions.

5. **Verify the lifecycle policy configuration**:

   Verification ensures the lifecycle policy is correctly configured and active, providing confidence that your data archiving strategy will execute as planned. This step is critical for validating that the automated cost optimization and compliance features are properly enabled before relying on them for production data management.

   ```bash
   # Verify that the lifecycle policy has been applied correctly
   aws s3api get-bucket-lifecycle-configuration \
       --bucket $BUCKET_NAME
   
   echo "✅ Lifecycle policy verification completed"
   ```

   The response confirms that S3 has registered your lifecycle rules and will begin evaluating objects according to your defined schedule. This establishes the foundation for ongoing automated data management that operates transparently in the background.

6. **Set up object restoration capability for archived data**:

   Object restoration capabilities are essential for accessing data moved to Glacier storage classes, providing the flexibility to retrieve archived information when business or compliance requirements demand it. The restore process temporary makes archived objects available in S3 Standard storage class for a specified duration.

   ```bash
   # Create a restore request configuration for demonstration
   cat > restore-request.json << 'EOF'
   {
       "Days": 7,
       "GlacierJobParameters": {
           "Tier": "Standard"
       }
   }
   EOF
   
   echo "✅ Created restore request configuration"
   ```

   This configuration defines how archived objects can be restored when needed. The Standard tier provides balanced cost and retrieval time (3-5 hours for Glacier Flexible Retrieval, 12 hours for Deep Archive). This is essential for understanding how to access your archived data when compliance or business needs require it.

7. **Configure SNS topic for archiving notifications**:

   Amazon SNS provides the messaging infrastructure for real-time visibility into your data lifecycle operations. By establishing notification channels, you create operational transparency that enables proactive monitoring of archive activities, ensuring business stakeholders stay informed about data availability and compliance status changes.

   ```bash
   # Create SNS topic for archive notifications
   SNS_TOPIC_ARN=$(aws sns create-topic \
       --name archive-notification-${RANDOM_SUFFIX} \
       --output text --query 'TopicArn')
   
   echo "✅ Created SNS topic: $SNS_TOPIC_ARN"
   
   # Store the topic ARN for later use
   export SNS_TOPIC_ARN
   ```

   The SNS topic is now ready to deliver notifications across multiple channels (email, SMS, HTTP endpoints, SQS queues), providing flexible integration with existing operational workflows and monitoring systems.

8. **Subscribe to notifications (replace with your email)**:

   Email notifications provide immediate visibility into restore operations and lifecycle events, enabling rapid response to data access requests or operational issues. This integration ensures that data stewards and compliance officers receive timely updates about archiving activities without requiring manual monitoring.

   ```bash
   # Replace with your actual email address
   EMAIL="your-email@example.com"
   
   # Subscribe to the SNS topic for notifications
   aws sns subscribe \
       --topic-arn $SNS_TOPIC_ARN \
       --protocol email \
       --notification-endpoint $EMAIL
   
   echo "✅ Subscribed $EMAIL to archive notifications"
   echo "Check your email to confirm the subscription"
   ```

   Email notifications provide real-time updates about restore operations and other important lifecycle events. In production, you might also integrate with systems like Slack or PagerDuty for operational alerts.

9. **Configure S3 event notifications for restore operations**:

   S3 event notifications provide automated alerting for critical data lifecycle events, ensuring stakeholders receive immediate notification when restore operations complete. This integration creates a comprehensive monitoring system that tracks data availability changes and enables proactive operational management.

   ```bash
   # Create notification configuration for S3 events
   cat > notification-config.json << EOF
   {
       "TopicConfigurations": [
           {
               "TopicArn": "$SNS_TOPIC_ARN",
               "Events": ["s3:ObjectRestore:Completed"],
               "Filter": {
                   "Key": {
                       "FilterRules": [
                           {
                               "Name": "prefix",
                               "Value": "data/"
                           }
                       ]
                   }
               }
           }
       ]
   }
   EOF
   
   # Apply the notification configuration
   aws s3api put-bucket-notification-configuration \
       --bucket $BUCKET_NAME \
       --notification-configuration file://notification-config.json
   
   echo "✅ Configured S3 event notifications"
   ```

   This completes the notification chain, ensuring you're alerted when restore operations complete. This integration between S3 and SNS provides operational visibility into your data lifecycle management processes.

   > **Warning**: In a production environment, transitions to Glacier storage classes are not immediate. They occur as background processes that can take hours to complete after an object becomes eligible. Don't rely on transitions happening exactly at the time threshold you've set. For more details, see [S3 lifecycle transition considerations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-transition-general-considerations.html).

## Validation & Testing

1. **Verify lifecycle policy is correctly applied**:

   ```bash
   aws s3api get-bucket-lifecycle-configuration \
       --bucket $BUCKET_NAME
   ```

   Expected output: You should see the policy rules you defined with the correct transition days and storage classes.

2. **Check current storage class of uploaded objects**:

   ```bash
   aws s3api head-object \
       --bucket $BUCKET_NAME \
       --key data/sample-data.txt
   ```

   Expected output: In the response, look for the `StorageClass` field. Initially, it should be `STANDARD`.

3. **Verify bucket notification configuration**:

   ```bash
   aws s3api get-bucket-notification-configuration \
       --bucket $BUCKET_NAME
   ```

   Expected output: You should see the SNS topic configuration you set up for restore notifications.

4. **Test restore functionality (demonstration)**:

   ```bash
   # Note: This command demonstrates how to restore an object
   # In a real scenario, your object would already be in Glacier
   aws s3api restore-object \
       --bucket $BUCKET_NAME \
       --key data/sample-data.txt \
       --restore-request file://restore-request.json
   
   echo "Restore request submitted (demonstration only)"
   ```

   Expected behavior: In a real scenario with archived objects, this would initiate a restore process and you would receive notifications when completed.

5. **List objects to verify upload success**:

   ```bash
   # List all objects in the bucket
   aws s3api list-objects-v2 \
       --bucket $BUCKET_NAME \
       --prefix data/
   ```

   Expected output: You should see all 6 uploaded files (sample-data.txt and test-file-1.txt through test-file-5.txt) with their metadata.

## Cleanup

1. **Remove lifecycle configuration from bucket**:

   ```bash
   aws s3api delete-bucket-lifecycle \
       --bucket $BUCKET_NAME
   
   echo "✅ Removed lifecycle configuration"
   ```

2. **Delete all objects in the bucket**:

   ```bash
   aws s3 rm s3://$BUCKET_NAME --recursive
   
   echo "✅ Deleted all objects from bucket"
   ```

3. **Delete the S3 bucket**:

   ```bash
   aws s3api delete-bucket --bucket $BUCKET_NAME
   
   echo "✅ Deleted S3 bucket"
   ```

4. **Delete SNS topic and clean up local files**:

   ```bash
   # Delete the SNS topic
   aws sns delete-topic --topic-arn $SNS_TOPIC_ARN
   
   # Delete local files created for this recipe
   rm -f lifecycle-policy.json restore-request.json \
       notification-config.json
   rm -f sample-data.txt test-file-*.txt
   
   echo "✅ Cleanup completed"
   ```

## Discussion

Amazon S3 Glacier provides a cost-effective solution for long-term data archiving, but it's important to understand the trade-offs involved. The S3 Glacier storage classes offer different cost and retrieval characteristics optimized for specific access patterns, following the [AWS Well-Architected Framework's cost optimization pillar](https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar/welcome.html):

**S3 Glacier Instant Retrieval**: Offers millisecond retrieval for data accessed about once per quarter. It costs more than other Glacier options but provides immediate access, making it ideal for backup data that might need quick restoration. This storage class is perfect for compliance data that requires occasional but immediate access.

**S3 Glacier Flexible Retrieval** (formerly S3 Glacier): Designed for data accessed once or twice per year with retrieval times ranging from minutes to hours depending on the tier selected (Expedited, Standard, or Bulk). This balance of cost and accessibility works well for compliance archives where retrieval time is less critical than storage cost.

**S3 Glacier Deep Archive**: The lowest-cost storage option, designed for data accessed less than once per year with retrieval times of 9-12 hours for Standard retrievals or up to 48 hours for Bulk retrievals. Perfect for regulatory archives with minimal access requirements, offering up to 95% cost reduction compared to S3 Standard.

Lifecycle policies automate the transition between storage classes, allowing you to optimize costs based on data access patterns without operational overhead. When designing your archiving strategy, consider these critical factors: retrieval needs determine which Glacier class is most appropriate and affects business continuity planning; data access patterns vary by department and data type, suggesting the use of tags or prefixes for different lifecycle rules; and costs beyond storage include retrieval operations that incur additional fees factored into total cost of ownership calculations.

For more complex archiving needs, consider implementing advanced solutions using AWS Lambda to automate restoration processes or perform additional data processing before archiving. The [S3 storage classes documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html) and [lifecycle management guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html) provide comprehensive information on optimizing your archiving strategy.

> **Tip**: Use AWS Cost Explorer to monitor the cost savings achieved through S3 lifecycle policies. You can create custom reports to track storage cost reductions and retrieval fees, helping justify the business value of your archiving strategy.

## Challenge

Extend this solution by implementing these enhancements:

1. **Advanced Tagging Strategy**: Modify the solution to use different lifecycle rules for different types of data by implementing a tagging strategy. Create a Lambda function that automatically tags new objects based on their attributes (such as file type, size, or content), and adjust the lifecycle rules to use these tags instead of prefix-based filtering.

2. **Cost Analysis Dashboard**: Implement a solution that automatically tracks and reports on the cost savings achieved by moving data to Glacier storage classes. Use Amazon CloudWatch and AWS Cost Explorer APIs to collect and analyze this data, creating automated reports for stakeholders.

3. **Intelligent Restoration**: Create an automated system that intelligently restores data based on access patterns or business rules, potentially using Amazon Bedrock or other ML services to predict when archived data might be needed based on historical access patterns.

4. **Cross-Region Archiving**: Extend the solution to include cross-region replication for disaster recovery, ensuring archived data is protected against regional failures using S3 Cross-Region Replication (CRR) with appropriate lifecycle policies.

5. **Compliance Reporting**: Build a comprehensive reporting system that tracks all lifecycle transitions and provides audit trails for compliance purposes, including integration with AWS CloudTrail and Config to create detailed governance reports.

## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [AWS CDK (Python)](code/cdk-python/) - AWS CDK Python implementation
- [AWS CDK (TypeScript)](code/cdk-typescript/) - AWS CDK TypeScript implementation
- [CloudFormation](code/cloudformation.yaml) - AWS CloudFormation template
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using AWS CLI commands to deploy infrastructure
- [Terraform](code/terraform/) - Terraform configuration files