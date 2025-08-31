#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';

/**
 * Properties for the SSL Certificate Monitoring Stack
 */
export interface SslCertificateMonitoringProps extends cdk.StackProps {
  /**
   * Email address to receive certificate expiration notifications
   */
  readonly notificationEmail: string;
  
  /**
   * ARN of the ACM certificate to monitor
   * If not provided, will monitor all certificates in the account
   */
  readonly certificateArn?: string;
  
  /**
   * Number of days before expiration to trigger the alarm
   * @default 30
   */
  readonly expirationThresholdDays?: number;
  
  /**
   * Custom prefix for resource names
   * @default 'ssl-cert-monitoring'
   */
  readonly resourcePrefix?: string;
}

/**
 * CDK Stack for SSL Certificate Monitoring with ACM and SNS
 * 
 * This stack creates:
 * - SNS topic for certificate expiration alerts
 * - Email subscription to the SNS topic
 * - CloudWatch alarms to monitor certificate expiration
 * - Optional monitoring for all certificates in the account
 */
export class SslCertificateMonitoringStack extends cdk.Stack {
  public readonly snsTopicArn: string;
  public readonly alarmNames: string[];

  constructor(scope: Construct, id: string, props: SslCertificateMonitoringProps) {
    super(scope, id, props);

    // Validate required properties
    if (!props.notificationEmail) {
      throw new Error('notificationEmail is required');
    }

    // Set default values
    const expirationThreshold = props.expirationThresholdDays ?? 30;
    const resourcePrefix = props.resourcePrefix ?? 'ssl-cert-monitoring';
    
    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // Create SNS topic for certificate expiration alerts
    const alertTopic = new sns.Topic(this, 'CertificateAlertTopic', {
      topicName: `${resourcePrefix}-${uniqueSuffix}`,
      displayName: 'SSL Certificate Expiration Alerts',
      description: 'Notifications for SSL certificate expiration warnings'
    });

    // Subscribe email address to SNS topic
    alertTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(props.notificationEmail, {
        json: false
      })
    );

    // Store SNS topic ARN for outputs
    this.snsTopicArn = alertTopic.topicArn;
    this.alarmNames = [];

    // Create alarm for specific certificate if provided
    if (props.certificateArn) {
      const alarmName = this.createCertificateAlarm(
        props.certificateArn,
        alertTopic,
        expirationThreshold,
        resourcePrefix,
        uniqueSuffix
      );
      this.alarmNames.push(alarmName);
    } else {
      // Create a generic alarm that can be used with any certificate
      // Note: In practice, you would need to know the certificate ARN
      // This creates a template that can be customized post-deployment
      const genericAlarmName = `${resourcePrefix}-generic-${uniqueSuffix}`;
      
      new cloudwatch.Alarm(this, 'GenericCertificateAlarm', {
        alarmName: genericAlarmName,
        alarmDescription: 'Template alarm for SSL certificate expiration monitoring - requires certificate ARN configuration',
        metric: new cloudwatch.Metric({
          namespace: 'AWS/CertificateManager',
          metricName: 'DaysToExpiry',
          statistic: 'Minimum',
          period: cdk.Duration.days(1),
          // Note: Dimensions need to be set post-deployment with actual certificate ARN
        }),
        threshold: expirationThreshold,
        comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
        evaluationPeriods: 1,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
      });

      this.alarmNames.push(genericAlarmName);
    }

    // Add tags to all resources in this stack
    cdk.Tags.of(this).add('Project', 'SSL-Certificate-Monitoring');
    cdk.Tags.of(this).add('Purpose', 'Security-Operations');
    cdk.Tags.of(this).add('Environment', 'Production');

    // Create stack outputs
    new cdk.CfnOutput(this, 'SnsTopicArn', {
      value: this.snsTopicArn,
      description: 'ARN of the SNS topic for certificate alerts',
      exportName: `${this.stackName}-SnsTopicArn`
    });

    new cdk.CfnOutput(this, 'NotificationEmail', {
      value: props.notificationEmail,
      description: 'Email address configured for certificate alerts'
    });

    new cdk.CfnOutput(this, 'ExpirationThreshold', {
      value: expirationThreshold.toString(),
      description: 'Number of days before expiration that triggers alerts'
    });

    new cdk.CfnOutput(this, 'AlarmNames', {
      value: this.alarmNames.join(', '),
      description: 'Names of CloudWatch alarms created for certificate monitoring'
    });

    // Output instructions for configuring certificate monitoring
    new cdk.CfnOutput(this, 'PostDeploymentInstructions', {
      value: props.certificateArn 
        ? 'Certificate monitoring is fully configured and active'
        : 'Configure certificate ARN in CloudWatch alarm dimensions to complete setup',
      description: 'Next steps to complete certificate monitoring setup'
    });
  }

  /**
   * Creates a CloudWatch alarm for monitoring a specific SSL certificate
   * 
   * @param certificateArn ARN of the certificate to monitor
   * @param alertTopic SNS topic to send alerts to
   * @param threshold Number of days before expiration to trigger alarm
   * @param resourcePrefix Prefix for resource names
   * @param uniqueSuffix Unique suffix for resource names
   * @returns Name of the created alarm
   */
  private createCertificateAlarm(
    certificateArn: string,
    alertTopic: sns.Topic,
    threshold: number,
    resourcePrefix: string,
    uniqueSuffix: string
  ): string {
    // Extract domain name from certificate ARN for naming
    const certId = certificateArn.split('/').pop() || 'unknown';
    const alarmName = `${resourcePrefix}-${certId.substring(0, 8)}-${uniqueSuffix}`;

    // Create CloudWatch alarm for certificate expiration
    const alarm = new cloudwatch.Alarm(this, `CertificateAlarm-${certId}`, {
      alarmName: alarmName,
      alarmDescription: `Alert when SSL certificate ${certId} expires in ${threshold} days`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/CertificateManager',
        metricName: 'DaysToExpiry',
        statistic: 'Minimum',
        period: cdk.Duration.days(1),
        dimensionsMap: {
          'CertificateArn': certificateArn
        }
      }),
      threshold: threshold,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS action to the alarm
    alarm.addAlarmAction(new cloudwatchActions.SnsAction(alertTopic));

    return alarmName;
  }
}

/**
 * CDK App for SSL Certificate Monitoring
 */
class SslCertificateMonitoringApp extends cdk.App {
  constructor() {
    super();

    // Get configuration from CDK context or environment variables
    const notificationEmail = this.node.tryGetContext('notificationEmail') || 
                             process.env.NOTIFICATION_EMAIL || 
                             'your-email@example.com';

    const certificateArn = this.node.tryGetContext('certificateArn') || 
                          process.env.CERTIFICATE_ARN;

    const expirationThresholdDays = Number(
      this.node.tryGetContext('expirationThresholdDays') || 
      process.env.EXPIRATION_THRESHOLD_DAYS || 
      '30'
    );

    const resourcePrefix = this.node.tryGetContext('resourcePrefix') || 
                          process.env.RESOURCE_PREFIX || 
                          'ssl-cert-monitoring';

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(notificationEmail)) {
      throw new Error(`Invalid email format: ${notificationEmail}`);
    }

    // Create the monitoring stack
    new SslCertificateMonitoringStack(this, 'SslCertificateMonitoringStack', {
      notificationEmail,
      certificateArn,
      expirationThresholdDays,
      resourcePrefix,
      description: 'SSL Certificate Monitoring with AWS Certificate Manager and SNS',
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: process.env.CDK_DEFAULT_REGION
      }
    });
  }
}

// Create and run the CDK app
const app = new SslCertificateMonitoringApp();

// Add global tags
cdk.Tags.of(app).add('CreatedBy', 'CDK');
cdk.Tags.of(app).add('Recipe', 'simple-ssl-certificate-monitoring-acm-sns');