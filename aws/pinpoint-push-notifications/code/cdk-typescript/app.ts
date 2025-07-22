#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as pinpoint from 'aws-cdk-lib/aws-pinpoint';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the MobilePushNotificationsStack
 */
interface MobilePushNotificationsStackProps extends cdk.StackProps {
  /**
   * Name of the Pinpoint application
   * @default 'ecommerce-mobile-app'
   */
  readonly appName?: string;

  /**
   * Enable APNs (Apple Push Notification Service) channel
   * @default true
   */
  readonly enableApns?: boolean;

  /**
   * Enable FCM (Firebase Cloud Messaging) channel
   * @default true
   */
  readonly enableFcm?: boolean;

  /**
   * Enable event streaming to Kinesis
   * @default true
   */
  readonly enableEventStreaming?: boolean;

  /**
   * Enable CloudWatch monitoring and alarms
   * @default true
   */
  readonly enableMonitoring?: boolean;

  /**
   * APNs certificate for iOS push notifications
   * Note: This should be provided securely, not hardcoded
   */
  readonly apnsCertificate?: string;

  /**
   * FCM server key for Android push notifications
   * Note: This should be provided securely, not hardcoded
   */
  readonly fcmServerKey?: string;
}

/**
 * CDK Stack for Mobile Push Notifications with Amazon Pinpoint
 * 
 * This stack creates:
 * - Amazon Pinpoint application for mobile engagement
 * - APNs channel for iOS push notifications
 * - FCM channel for Android push notifications
 * - User segments for targeted messaging
 * - Push notification templates
 * - Event streaming to Kinesis for analytics
 * - CloudWatch monitoring and alarms
 */
export class MobilePushNotificationsStack extends cdk.Stack {
  /**
   * The Pinpoint application
   */
  public readonly pinpointApp: pinpoint.CfnApp;

  /**
   * The APNs channel (if enabled)
   */
  public readonly apnsChannel?: pinpoint.CfnAPNSChannel;

  /**
   * The FCM channel (if enabled)
   */
  public readonly fcmChannel?: pinpoint.CfnGCMChannel;

  /**
   * The Kinesis stream for event streaming (if enabled)
   */
  public readonly eventStream?: kinesis.Stream;

  /**
   * The IAM role for Pinpoint services
   */
  public readonly pinpointServiceRole: iam.Role;

  constructor(scope: Construct, id: string, props: MobilePushNotificationsStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const appName = props.appName || 'ecommerce-mobile-app';
    const enableApns = props.enableApns !== false;
    const enableFcm = props.enableFcm !== false;
    const enableEventStreaming = props.enableEventStreaming !== false;
    const enableMonitoring = props.enableMonitoring !== false;

    // Create IAM role for Pinpoint services
    this.pinpointServiceRole = new iam.Role(this, 'PinpointServiceRole', {
      assumedBy: new iam.ServicePrincipal('pinpoint.amazonaws.com'),
      description: 'IAM role for Amazon Pinpoint services',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonPinpointServiceRole'),
      ],
    });

    // Create the main Pinpoint application
    this.pinpointApp = new pinpoint.CfnApp(this, 'PinpointApp', {
      name: appName,
      tags: {
        Project: 'MobilePushNotifications',
        Environment: 'Development',
        Purpose: 'Mobile engagement and push notifications',
      },
    });

    // Configure APNs channel for iOS if enabled
    if (enableApns) {
      this.apnsChannel = this.createApnsChannel(props.apnsCertificate);
    }

    // Configure FCM channel for Android if enabled
    if (enableFcm) {
      this.fcmChannel = this.createFcmChannel(props.fcmServerKey);
    }

    // Create user segments for targeted messaging
    this.createUserSegments();

    // Create push notification templates
    this.createPushTemplates();

    // Set up event streaming if enabled
    if (enableEventStreaming) {
      this.eventStream = this.createEventStreaming();
    }

    // Set up CloudWatch monitoring if enabled
    if (enableMonitoring) {
      this.createMonitoring();
    }

    // Output important values
    this.createOutputs();
  }

  /**
   * Creates the APNs channel for iOS push notifications
   */
  private createApnsChannel(certificate?: string): pinpoint.CfnAPNSChannel {
    const apnsChannel = new pinpoint.CfnAPNSChannel(this, 'ApnsChannel', {
      applicationId: this.pinpointApp.ref,
      enabled: true,
      defaultAuthenticationMethod: 'CERTIFICATE',
      // Note: In production, certificate should be provided securely
      // This is just a placeholder for the structure
      ...(certificate && { certificate }),
    });

    apnsChannel.addDependency(this.pinpointApp);

    return apnsChannel;
  }

  /**
   * Creates the FCM channel for Android push notifications
   */
  private createFcmChannel(serverKey?: string): pinpoint.CfnGCMChannel {
    const fcmChannel = new pinpoint.CfnGCMChannel(this, 'FcmChannel', {
      applicationId: this.pinpointApp.ref,
      enabled: true,
      // Note: In production, API key should be provided securely
      // This is just a placeholder for the structure
      ...(serverKey && { apiKey: serverKey }),
    });

    fcmChannel.addDependency(this.pinpointApp);

    return fcmChannel;
  }

  /**
   * Creates user segments for targeted messaging
   */
  private createUserSegments(): void {
    // High-value customers segment
    new pinpoint.CfnSegment(this, 'HighValueCustomersSegment', {
      applicationId: this.pinpointApp.ref,
      name: 'high-value-customers',
      dimensions: {
        userAttributes: {
          PurchaseHistory: {
            attributeType: 'INCLUSIVE',
            values: ['high-value'],
          },
        },
        demographic: {
          platform: {
            dimensionType: 'INCLUSIVE',
            values: ['iOS', 'Android'],
          },
        },
      },
      tags: {
        Purpose: 'Targeting high-value customers for premium campaigns',
      },
    });

    // Location-based segment for regional campaigns
    new pinpoint.CfnSegment(this, 'USWestCoastSegment', {
      applicationId: this.pinpointApp.ref,
      name: 'us-west-coast-users',
      dimensions: {
        location: {
          country: {
            dimensionType: 'INCLUSIVE',
            values: ['US'],
          },
        },
        attributes: {
          Region: {
            attributeType: 'INCLUSIVE',
            values: ['West Coast', 'California', 'Washington', 'Oregon'],
          },
        },
      },
      tags: {
        Purpose: 'Regional targeting for location-specific campaigns',
      },
    });

    // Behavioral segment based on app usage
    new pinpoint.CfnSegment(this, 'ActiveUsersSegment', {
      applicationId: this.pinpointApp.ref,
      name: 'active-users',
      dimensions: {
        behavior: {
          recency: {
            duration: 'DAY_7',
            recencyType: 'ACTIVE',
          },
        },
        userAttributes: {
          AppUsage: {
            attributeType: 'INCLUSIVE',
            values: ['daily', 'frequent'],
          },
        },
      },
      tags: {
        Purpose: 'Targeting actively engaged users',
      },
    });
  }

  /**
   * Creates reusable push notification templates
   */
  private createPushTemplates(): void {
    // Flash sale notification template
    new pinpoint.CfnPushTemplate(this, 'FlashSaleTemplate', {
      templateName: 'flash-sale-template',
      templateDescription: 'Template for flash sale notifications',
      adm: {
        action: 'OPEN_APP',
        body: "Don't miss out! {{User.FirstName}}, exclusive flash sale ends in 2 hours!",
        title: '🔥 Flash Sale Alert',
        sound: 'default',
      },
      apns: {
        action: 'OPEN_APP',
        body: "Don't miss out! {{User.FirstName}}, exclusive flash sale ends in 2 hours!",
        title: '🔥 Flash Sale Alert',
        sound: 'default',
      },
      gcm: {
        action: 'OPEN_APP',
        body: "Don't miss out! {{User.FirstName}}, exclusive flash sale ends in 2 hours!",
        title: '🔥 Flash Sale Alert',
        sound: 'default',
      },
      default: {
        action: 'OPEN_APP',
        body: "Don't miss out! Exclusive flash sale ends in 2 hours!",
        title: '🔥 Flash Sale Alert',
      },
      tags: {
        Category: 'Sales',
        Priority: 'High',
      },
    });

    // Abandoned cart reminder template
    new pinpoint.CfnPushTemplate(this, 'AbandonedCartTemplate', {
      templateName: 'abandoned-cart-template',
      templateDescription: 'Template for abandoned cart reminders',
      adm: {
        action: 'DEEP_LINK',
        body: 'Hi {{User.FirstName}}, you left {{Custom.ItemCount}} items in your cart. Complete your purchase now!',
        title: '🛒 Items waiting for you',
        sound: 'default',
        url: 'myapp://cart',
      },
      apns: {
        action: 'DEEP_LINK',
        body: 'Hi {{User.FirstName}}, you left {{Custom.ItemCount}} items in your cart. Complete your purchase now!',
        title: '🛒 Items waiting for you',
        sound: 'default',
        url: 'myapp://cart',
      },
      gcm: {
        action: 'DEEP_LINK',
        body: 'Hi {{User.FirstName}}, you left {{Custom.ItemCount}} items in your cart. Complete your purchase now!',
        title: '🛒 Items waiting for you',
        sound: 'default',
        url: 'myapp://cart',
      },
      default: {
        action: 'DEEP_LINK',
        body: 'You have items waiting in your cart. Complete your purchase now!',
        title: '🛒 Items waiting for you',
        url: 'myapp://cart',
      },
      tags: {
        Category: 'Retention',
        Priority: 'Medium',
      },
    });

    // Personalized product recommendation template
    new pinpoint.CfnPushTemplate(this, 'ProductRecommendationTemplate', {
      templateName: 'product-recommendation-template',
      templateDescription: 'Template for personalized product recommendations',
      adm: {
        action: 'DEEP_LINK',
        body: 'New arrivals in {{Custom.Category}} that you might love, {{User.FirstName}}!',
        title: '✨ Picked just for you',
        sound: 'default',
        url: 'myapp://recommendations',
      },
      apns: {
        action: 'DEEP_LINK',
        body: 'New arrivals in {{Custom.Category}} that you might love, {{User.FirstName}}!',
        title: '✨ Picked just for you',
        sound: 'default',
        url: 'myapp://recommendations',
      },
      gcm: {
        action: 'DEEP_LINK',
        body: 'New arrivals in {{Custom.Category}} that you might love, {{User.FirstName}}!',
        title: '✨ Picked just for you',
        sound: 'default',
        url: 'myapp://recommendations',
      },
      default: {
        action: 'DEEP_LINK',
        body: 'Check out our new personalized recommendations for you!',
        title: '✨ Picked just for you',
        url: 'myapp://recommendations',
      },
      tags: {
        Category: 'Personalization',
        Priority: 'Low',
      },
    });
  }

  /**
   * Creates event streaming to Kinesis for analytics
   */
  private createEventStreaming(): kinesis.Stream {
    // Create Kinesis stream for Pinpoint events
    const eventStream = new kinesis.Stream(this, 'PinpointEventStream', {
      streamName: `pinpoint-events-${this.pinpointApp.ref}`,
      shardCount: 1,
      retentionPeriod: cdk.Duration.days(7),
      encryption: kinesis.StreamEncryption.MANAGED,
    });

    // Grant Pinpoint permission to write to the stream
    eventStream.grantWrite(this.pinpointServiceRole);

    // Configure event streaming in Pinpoint
    new pinpoint.CfnEventStream(this, 'EventStreamConfig', {
      applicationId: this.pinpointApp.ref,
      destinationStreamArn: eventStream.streamArn,
      roleArn: this.pinpointServiceRole.roleArn,
    });

    return eventStream;
  }

  /**
   * Creates CloudWatch monitoring and alarms
   */
  private createMonitoring(): void {
    // Create CloudWatch alarm for failed push notifications
    new cloudwatch.Alarm(this, 'PushNotificationFailuresAlarm', {
      alarmName: `PinpointPushFailures-${this.pinpointApp.ref}`,
      alarmDescription: 'Alert when push notification failures exceed threshold',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Pinpoint',
        metricName: 'DirectSendMessagePermanentFailure',
        dimensionsMap: {
          ApplicationId: this.pinpointApp.ref,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create alarm for delivery rate
    new cloudwatch.Alarm(this, 'PushDeliveryRateAlarm', {
      alarmName: `PinpointDeliveryRate-${this.pinpointApp.ref}`,
      alarmDescription: 'Alert when delivery rate falls below 90%',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Pinpoint',
        metricName: 'DirectSendMessageDeliveryRate',
        dimensionsMap: {
          ApplicationId: this.pinpointApp.ref,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 0.9,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create alarm for high number of endpoint failures
    new cloudwatch.Alarm(this, 'EndpointFailuresAlarm', {
      alarmName: `PinpointEndpointFailures-${this.pinpointApp.ref}`,
      alarmDescription: 'Alert when endpoint registration failures exceed threshold',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Pinpoint',
        metricName: 'EndpointRegistrationFailures',
        dimensionsMap: {
          ApplicationId: this.pinpointApp.ref,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 10,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create a custom dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'PinpointDashboard', {
      dashboardName: `Pinpoint-${this.pinpointApp.ref}-Dashboard`,
    });

    // Add widgets to the dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Push Notification Delivery Rate',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Pinpoint',
            metricName: 'DirectSendMessageDeliveryRate',
            dimensionsMap: {
              ApplicationId: this.pinpointApp.ref,
            },
            statistic: 'Average',
          }),
        ],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Push Notification Failures',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Pinpoint',
            metricName: 'DirectSendMessagePermanentFailure',
            dimensionsMap: {
              ApplicationId: this.pinpointApp.ref,
            },
            statistic: 'Sum',
          }),
        ],
        width: 12,
        height: 6,
      })
    );
  }

  /**
   * Creates stack outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'PinpointApplicationId', {
      value: this.pinpointApp.ref,
      description: 'Amazon Pinpoint Application ID',
      exportName: `${this.stackName}-PinpointAppId`,
    });

    new cdk.CfnOutput(this, 'PinpointApplicationName', {
      value: this.pinpointApp.name || 'Unknown',
      description: 'Amazon Pinpoint Application Name',
    });

    new cdk.CfnOutput(this, 'PinpointServiceRoleArn', {
      value: this.pinpointServiceRole.roleArn,
      description: 'IAM Role ARN for Pinpoint services',
    });

    if (this.eventStream) {
      new cdk.CfnOutput(this, 'EventStreamArn', {
        value: this.eventStream.streamArn,
        description: 'Kinesis Event Stream ARN for Pinpoint analytics',
      });

      new cdk.CfnOutput(this, 'EventStreamName', {
        value: this.eventStream.streamName,
        description: 'Kinesis Event Stream Name',
      });
    }

    // Output console links for easy access
    new cdk.CfnOutput(this, 'PinpointConsoleUrl', {
      value: `https://${this.region}.console.aws.amazon.com/pinpoint/home/?region=${this.region}#/apps/${this.pinpointApp.ref}/analytics/overview`,
      description: 'Amazon Pinpoint Console URL',
    });
  }
}

/**
 * CDK App
 */
const app = new cdk.App();

// Create the stack with customizable properties
new MobilePushNotificationsStack(app, 'MobilePushNotificationsStack', {
  description: 'Mobile Push Notifications with Amazon Pinpoint - CDK TypeScript Implementation',
  
  // Environment configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },

  // Stack configuration
  terminationProtection: false,

  // Custom properties
  appName: process.env.PINPOINT_APP_NAME || 'ecommerce-mobile-app',
  enableApns: process.env.ENABLE_APNS !== 'false',
  enableFcm: process.env.ENABLE_FCM !== 'false',
  enableEventStreaming: process.env.ENABLE_EVENT_STREAMING !== 'false',
  enableMonitoring: process.env.ENABLE_MONITORING !== 'false',
  
  // Security credentials (should be provided via environment variables or AWS Secrets Manager)
  apnsCertificate: process.env.APNS_CERTIFICATE,
  fcmServerKey: process.env.FCM_SERVER_KEY,

  // Stack tags
  tags: {
    Project: 'MobilePushNotifications',
    Environment: process.env.ENVIRONMENT || 'Development',
    CostCenter: 'Marketing',
    Owner: 'MobileTeam',
  },
});

app.synth();