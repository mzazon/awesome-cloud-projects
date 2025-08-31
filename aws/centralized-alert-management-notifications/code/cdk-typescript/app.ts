#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as cr from 'aws-cdk-lib/custom-resources';

/**
 * Properties for the CentralizedAlertManagementStack
 */
interface CentralizedAlertManagementStackProps extends cdk.StackProps {
  /**
   * Email address for receiving notifications
   */
  readonly notificationEmail?: string;
  
  /**
   * S3 bucket size threshold in bytes for triggering alarms
   * @default 5000000 (5MB)
   */
  readonly bucketSizeThreshold?: number;
  
  /**
   * Custom suffix for resource naming
   */
  readonly resourceSuffix?: string;
}

/**
 * CDK Stack for Centralized Alert Management with User Notifications and CloudWatch
 * 
 * This stack creates a comprehensive monitoring solution that consolidates CloudWatch alarms
 * and AWS service alerts into a unified notification system using AWS User Notifications.
 * The solution monitors S3 storage metrics and demonstrates centralized alert management
 * with configurable delivery channels.
 */
export class CentralizedAlertManagementStack extends cdk.Stack {
  /**
   * The S3 bucket being monitored
   */
  public readonly monitoringBucket: s3.Bucket;
  
  /**
   * CloudWatch alarm for bucket size monitoring
   */
  public readonly bucketSizeAlarm: cloudwatch.Alarm;
  
  /**
   * SNS topic for notifications (fallback mechanism)
   */
  public readonly notificationTopic: sns.Topic;
  
  /**
   * Custom resource for User Notifications setup
   */
  public readonly userNotificationsSetup: cdk.CustomResource;

  constructor(scope: Construct, id: string, props: CentralizedAlertManagementStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resources
    const suffix = props.resourceSuffix || this.generateRandomSuffix();
    const bucketName = `monitoring-demo-${suffix}`;
    const alarmName = `s3-bucket-size-alarm-${suffix}`;
    const configName = `s3-monitoring-config-${suffix}`;

    // Create S3 bucket with CloudWatch metrics enabled
    this.monitoringBucket = this.createMonitoringBucket(bucketName);

    // Create CloudWatch alarm for bucket size monitoring
    this.bucketSizeAlarm = this.createBucketSizeAlarm(
      alarmName,
      this.monitoringBucket,
      props.bucketSizeThreshold || 5000000
    );

    // Create SNS topic for notifications (fallback mechanism)
    this.notificationTopic = this.createNotificationTopic(suffix);

    // Subscribe email to SNS topic if provided
    if (props.notificationEmail) {
      this.subscribeEmailToTopic(props.notificationEmail);
    }

    // Create EventBridge rule to capture CloudWatch alarm state changes
    this.createAlarmStateChangeRule();

    // Create User Notifications setup using custom resource
    this.userNotificationsSetup = this.createUserNotificationsSetup(
      configName,
      props.notificationEmail
    );

    // Add sample files to demonstrate metrics generation
    this.addSampleFiles();

    // Create outputs for important resource information
    this.createOutputs();

    // Add tags to all resources for better organization
    this.addResourceTags();
  }

  /**
   * Creates an S3 bucket with CloudWatch metrics enabled for monitoring
   */
  private createMonitoringBucket(bucketName: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'MonitoringBucket', {
      bucketName: bucketName,
      versioned: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      // Enable CloudWatch request metrics
      metricsConfigurations: [
        {
          id: 'EntireBucket',
          prefix: undefined, // Monitor entire bucket
        },
      ],
    });

    // Add lifecycle rules for cost optimization
    bucket.addLifecycleRule({
      id: 'MonitoringDataLifecycle',
      enabled: true,
      transitions: [
        {
          storageClass: s3.StorageClass.INFREQUENT_ACCESS,
          transitionAfter: cdk.Duration.days(30),
        },
        {
          storageClass: s3.StorageClass.GLACIER,
          transitionAfter: cdk.Duration.days(90),
        },
      ],
    });

    return bucket;
  }

  /**
   * Creates a CloudWatch alarm to monitor S3 bucket size
   */
  private createBucketSizeAlarm(
    alarmName: string,
    bucket: s3.Bucket,
    threshold: number
  ): cloudwatch.Alarm {
    // Create custom metric for bucket size monitoring
    const bucketSizeMetric = new cloudwatch.Metric({
      namespace: 'AWS/S3',
      metricName: 'BucketSizeBytes',
      dimensionsMap: {
        BucketName: bucket.bucketName,
        StorageType: 'StandardStorage',
      },
      statistic: 'Average',
      period: cdk.Duration.days(1),
    });

    const alarm = new cloudwatch.Alarm(this, 'BucketSizeAlarm', {
      alarmName: alarmName,
      alarmDescription: 'Monitor S3 bucket size growth for centralized notification testing',
      metric: bucketSizeMetric,
      threshold: threshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      actionsEnabled: true,
    });

    return alarm;
  }

  /**
   * Creates an SNS topic for notifications
   */
  private createNotificationTopic(suffix: string): sns.Topic {
    const topic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `s3-monitoring-notifications-${suffix}`,
      displayName: 'S3 Monitoring Notifications',
      // Enable encryption for security
      masterKey: cdk.aws_kms.Alias.fromAliasName(this, 'SnsKmsKey', 'alias/aws/sns'),
    });

    // Add the alarm as an action to the SNS topic
    this.bucketSizeAlarm.addAlarmAction(
      new cdk.aws_cloudwatch_actions.SnsAction(topic)
    );
    this.bucketSizeAlarm.addOkAction(
      new cdk.aws_cloudwatch_actions.SnsAction(topic)
    );

    return topic;
  }

  /**
   * Subscribes an email address to the SNS topic
   */
  private subscribeEmailToTopic(email: string): void {
    this.notificationTopic.addSubscription(
      new subscriptions.EmailSubscription(email, {
        json: false,
      })
    );
  }

  /**
   * Creates EventBridge rule to capture CloudWatch alarm state changes
   */
  private createAlarmStateChangeRule(): void {
    // Create EventBridge rule for CloudWatch alarm state changes
    const alarmStateRule = new events.Rule(this, 'AlarmStateChangeRule', {
      ruleName: `${this.stackName}-alarm-state-changes`,
      description: 'Capture CloudWatch alarm state changes for centralized notifications',
      eventPattern: {
        source: ['aws.cloudwatch'],
        detailType: ['CloudWatch Alarm State Change'],
        detail: {
          alarmName: [this.bucketSizeAlarm.alarmName],
          state: {
            value: ['ALARM', 'OK'],
          },
        },
      },
    });

    // Add SNS topic as target for the rule
    alarmStateRule.addTarget(new targets.SnsTopic(this.notificationTopic));
  }

  /**
   * Creates User Notifications setup using custom resource
   * Note: User Notifications may not be fully supported in CDK yet,
   * so we use a custom resource with Lambda function
   */
  private createUserNotificationsSetup(
    configName: string,
    email?: string
  ): cdk.CustomResource {
    // Create IAM role for the custom resource Lambda
    const customResourceRole = new iam.Role(this, 'UserNotificationsCustomResourceRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        UserNotificationsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'notifications:*',
                'notificationscontacts:*',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for User Notifications setup
    const userNotificationsFunction = new lambda.Function(this, 'UserNotificationsFunction', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.handler',
      role: customResourceRole,
      timeout: cdk.Duration.minutes(5),
      code: lambda.Code.fromInline(`
import boto3
import json
import logging
import cfnresponse

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Custom resource handler for AWS User Notifications setup
    """
    try:
        request_type = event['RequestType']
        properties = event['ResourceProperties']
        
        config_name = properties.get('ConfigName', 'default-config')
        email = properties.get('Email')
        region = properties.get('Region', 'us-east-1')
        
        notifications_client = boto3.client('notifications', region_name=region)
        contacts_client = boto3.client('notificationscontacts', region_name=region)
        
        if request_type == 'Create':
            response_data = create_notification_setup(
                notifications_client, contacts_client, config_name, email, region
            )
        elif request_type == 'Update':
            response_data = update_notification_setup(
                notifications_client, contacts_client, config_name, email, region
            )
        elif request_type == 'Delete':
            response_data = delete_notification_setup(
                notifications_client, contacts_client, config_name, email, region
            )
        
        cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data)
        
    except Exception as e:
        logger.error(f"Error in User Notifications setup: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {
            'Error': str(e)
        })

def create_notification_setup(notifications_client, contacts_client, config_name, email, region):
    """Create User Notifications configuration"""
    response_data = {}
    
    try:
        # Register notification hub
        try:
            hub_response = notifications_client.register_notification_hub(
                notificationHubRegion=region
            )
            response_data['HubRegistered'] = True
            logger.info(f"Notification hub registered: {hub_response}")
        except Exception as e:
            if 'AlreadyExistsException' in str(e) or 'already registered' in str(e).lower():
                response_data['HubRegistered'] = True
                logger.info("Notification hub already exists")
            else:
                raise e
        
        # Create email contact if email is provided
        if email:
            try:
                contact_response = contacts_client.create_email_contact(
                    name=f"{config_name}-contact",
                    emailAddress=email
                )
                response_data['EmailContactArn'] = contact_response.get('arn', '')
                logger.info(f"Email contact created: {contact_response}")
            except Exception as e:
                logger.warning(f"Could not create email contact: {str(e)}")
                response_data['EmailContactArn'] = ''
        
        # Create notification configuration
        try:
            config_response = notifications_client.create_notification_configuration(
                name=config_name,
                description="S3 monitoring notification configuration created by CDK",
                aggregationDuration="PT5M"
            )
            response_data['ConfigurationArn'] = config_response.get('arn', '')
            logger.info(f"Notification configuration created: {config_response}")
        except Exception as e:
            logger.warning(f"Could not create notification configuration: {str(e)}")
            response_data['ConfigurationArn'] = ''
        
        return response_data
        
    except Exception as e:
        logger.error(f"Error creating notification setup: {str(e)}")
        return {'Error': str(e)}

def update_notification_setup(notifications_client, contacts_client, config_name, email, region):
    """Update User Notifications configuration"""
    # For simplicity, we'll delete and recreate
    delete_notification_setup(notifications_client, contacts_client, config_name, email, region)
    return create_notification_setup(notifications_client, contacts_client, config_name, email, region)

def delete_notification_setup(notifications_client, contacts_client, config_name, email, region):
    """Delete User Notifications configuration"""
    response_data = {}
    
    try:
        # List and delete notification configurations
        try:
            configs = notifications_client.list_notification_configurations()
            for config in configs.get('notificationConfigurations', []):
                if config.get('name') == config_name:
                    notifications_client.delete_notification_configuration(
                        arn=config['arn']
                    )
                    logger.info(f"Deleted notification configuration: {config['name']}")
        except Exception as e:
            logger.warning(f"Could not delete notification configuration: {str(e)}")
        
        # List and delete email contacts
        try:
            contacts = contacts_client.list_email_contacts()
            for contact in contacts.get('emailContacts', []):
                if contact.get('name') == f"{config_name}-contact":
                    contacts_client.delete_email_contact(
                        arn=contact['arn']
                    )
                    logger.info(f"Deleted email contact: {contact['name']}")
        except Exception as e:
            logger.warning(f"Could not delete email contact: {str(e)}")
        
        # Note: We don't deregister the notification hub as it may be used by other resources
        
        response_data['Deleted'] = True
        return response_data
        
    except Exception as e:
        logger.error(f"Error deleting notification setup: {str(e)}")
        return {'Error': str(e)}
`),
    });

    // Create the custom resource
    const userNotificationsProvider = new cr.Provider(this, 'UserNotificationsProvider', {
      onEventHandler: userNotificationsFunction,
      logRetention: cdk.aws_logs.RetentionDays.ONE_WEEK,
    });

    const customResource = new cdk.CustomResource(this, 'UserNotificationsCustomResource', {
      serviceToken: userNotificationsProvider.serviceToken,
      properties: {
        ConfigName: configName,
        Email: email || '',
        Region: this.region,
      },
    });

    // Ensure the custom resource is created after the alarm
    customResource.node.addDependency(this.bucketSizeAlarm);

    return customResource;
  }

  /**
   * Adds sample files to the S3 bucket to generate metrics
   */
  private addSampleFiles(): void {
    // Create sample deployment for demonstration
    new s3.BucketDeployment(this, 'SampleFiles', {
      sources: [
        s3.Source.data('data/sample1.txt', 'Sample monitoring data for metrics generation'),
        s3.Source.data('logs/sample2.txt', 'Additional test content for CloudWatch metrics'),
        s3.Source.data('archive/readme.txt', 'Archive folder for larger files and testing'),
      ],
      destinationBucket: this.monitoringBucket,
      retainOnDelete: false,
    });
  }

  /**
   * Creates CloudFormation outputs for important resource information
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'BucketName', {
      value: this.monitoringBucket.bucketName,
      description: 'S3 bucket being monitored for size alerts',
      exportName: `${this.stackName}-BucketName`,
    });

    new cdk.CfnOutput(this, 'BucketArn', {
      value: this.monitoringBucket.bucketArn,
      description: 'ARN of the S3 bucket being monitored',
      exportName: `${this.stackName}-BucketArn`,
    });

    new cdk.CfnOutput(this, 'AlarmName', {
      value: this.bucketSizeAlarm.alarmName,
      description: 'CloudWatch alarm monitoring bucket size',
      exportName: `${this.stackName}-AlarmName`,
    });

    new cdk.CfnOutput(this, 'AlarmArn', {
      value: this.bucketSizeAlarm.alarmArn,
      description: 'ARN of the CloudWatch alarm',
      exportName: `${this.stackName}-AlarmArn`,
    });

    new cdk.CfnOutput(this, 'SnsTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'SNS topic ARN for notifications',
      exportName: `${this.stackName}-SnsTopicArn`,
    });

    new cdk.CfnOutput(this, 'NotificationHubRegion', {
      value: this.region,
      description: 'AWS region where the notification hub is registered',
      exportName: `${this.stackName}-NotificationHubRegion`,
    });
  }

  /**
   * Adds resource tags for better organization and cost tracking
   */
  private addResourceTags(): void {
    const tags = {
      'Project': 'CentralizedAlertManagement',
      'Recipe': 'centralized-alert-management-notifications',
      'Environment': 'Demo',
      'ManagedBy': 'CDK',
    };

    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });
  }

  /**
   * Generates a random suffix for resource naming
   */
  private generateRandomSuffix(): string {
    return Math.random().toString(36).substring(2, 8);
  }
}

/**
 * Main CDK application
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const bucketSizeThreshold = app.node.tryGetContext('bucketSizeThreshold') || 
  parseInt(process.env.BUCKET_SIZE_THRESHOLD || '5000000');
const resourceSuffix = app.node.tryGetContext('resourceSuffix') || process.env.RESOURCE_SUFFIX;

// Create the stack
new CentralizedAlertManagementStack(app, 'CentralizedAlertManagementStack', {
  description: 'Centralized Alert Management with AWS User Notifications and CloudWatch monitoring for S3 storage metrics',
  notificationEmail: notificationEmail,
  bucketSizeThreshold: bucketSizeThreshold,
  resourceSuffix: resourceSuffix,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  tags: {
    'Recipe': 'centralized-alert-management-notifications',
    'Generator': 'CDK-TypeScript',
  },
});

// Synthesize the app
app.synth();