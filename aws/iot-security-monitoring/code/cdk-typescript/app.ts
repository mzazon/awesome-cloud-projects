#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';

/**
 * AWS IoT Device Defender Security Stack
 * 
 * This stack implements comprehensive IoT security monitoring using AWS IoT Device Defender,
 * including behavioral analysis, automated audits, and security violation alerting.
 */
export class IoTDeviceDefenderSecurityStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // SNS Topic for security alerts
    const securityAlertsTopic = new cdk.aws_sns.Topic(this, 'SecurityAlertsTopic', {
      topicName: `iot-security-alerts-${uniqueSuffix}`,
      displayName: 'IoT Device Security Alerts',
      description: 'SNS topic for IoT Device Defender security alerts and notifications'
    });

    // Email subscription parameter for alerts
    const emailParameter = new cdk.CfnParameter(this, 'AlertEmailAddress', {
      type: 'String',
      description: 'Email address to receive security alerts',
      constraintDescription: 'Must be a valid email address',
      allowedPattern: '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$'
    });

    // Email subscription to SNS topic
    new cdk.aws_sns.Subscription(this, 'EmailSubscription', {
      topic: securityAlertsTopic,
      protocol: cdk.aws_sns.SubscriptionProtocol.EMAIL,
      endpoint: emailParameter.valueAsString
    });

    // IAM Role for Device Defender with necessary permissions
    const deviceDefenderRole = new cdk.aws_iam.Role(this, 'DeviceDefenderRole', {
      roleName: `IoTDeviceDefenderRole-${uniqueSuffix}`,
      description: 'Role for AWS IoT Device Defender to perform audits and send notifications',
      assumedBy: new cdk.aws_iam.ServicePrincipal('iot.amazonaws.com'),
      managedPolicies: [
        cdk.aws_iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSIoTDeviceDefenderAudit')
      ]
    });

    // Additional policy for SNS publishing
    deviceDefenderRole.addToPolicy(new cdk.aws_iam.PolicyStatement({
      effect: cdk.aws_iam.Effect.ALLOW,
      actions: [
        'sns:Publish'
      ],
      resources: [securityAlertsTopic.topicArn]
    }));

    // Security Profile with behavioral rules for threat detection
    const securityProfile = new cdk.aws_iot.CfnSecurityProfile(this, 'SecurityProfile', {
      securityProfileName: `IoTSecurityProfile-${uniqueSuffix}`,
      securityProfileDescription: 'Comprehensive IoT security monitoring profile with behavioral rules',
      behaviors: [
        {
          name: 'ExcessiveMessages',
          metric: 'aws:num-messages-sent',
          criteria: {
            comparisonOperator: 'greater-than',
            value: { count: 100 },
            durationSeconds: 300,
            consecutiveDatapointsToAlarm: 1,
            consecutiveDatapointsToClear: 1
          }
        },
        {
          name: 'AuthorizationFailures',
          metric: 'aws:num-authorization-failures',
          criteria: {
            comparisonOperator: 'greater-than',
            value: { count: 5 },
            durationSeconds: 300,
            consecutiveDatapointsToAlarm: 1,
            consecutiveDatapointsToClear: 1
          }
        },
        {
          name: 'LargeMessageSize',
          metric: 'aws:message-byte-size',
          criteria: {
            comparisonOperator: 'greater-than',
            value: { count: 1024 },
            consecutiveDatapointsToAlarm: 1,
            consecutiveDatapointsToClear: 1
          }
        },
        {
          name: 'UnusualConnectionAttempts',
          metric: 'aws:num-connection-attempts',
          criteria: {
            comparisonOperator: 'greater-than',
            value: { count: 20 },
            durationSeconds: 300,
            consecutiveDatapointsToAlarm: 1,
            consecutiveDatapointsToClear: 1
          }
        }
      ],
      alertTargets: {
        'SNS': {
          alertTargetArn: securityAlertsTopic.topicArn,
          roleArn: deviceDefenderRole.roleArn
        }
      }
    });

    // ML-based Security Profile for advanced threat detection
    const mlSecurityProfile = new cdk.aws_iot.CfnSecurityProfile(this, 'MLSecurityProfile', {
      securityProfileName: `IoTSecurityProfile-ML-${uniqueSuffix}`,
      securityProfileDescription: 'Machine learning based threat detection profile',
      behaviors: [
        {
          name: 'MLMessagesReceived',
          metric: 'aws:num-messages-received'
        },
        {
          name: 'MLMessagesSent',
          metric: 'aws:num-messages-sent'
        },
        {
          name: 'MLConnectionAttempts',
          metric: 'aws:num-connection-attempts'
        },
        {
          name: 'MLDisconnects',
          metric: 'aws:num-disconnects'
        }
      ],
      alertTargets: {
        'SNS': {
          alertTargetArn: securityAlertsTopic.topicArn,
          roleArn: deviceDefenderRole.roleArn
        }
      }
    });

    // Scheduled Audit for regular compliance checks
    const scheduledAudit = new cdk.aws_iot.CfnScheduledAudit(this, 'WeeklySecurityAudit', {
      scheduledAuditName: `WeeklySecurityAudit-${uniqueSuffix}`,
      frequency: 'WEEKLY',
      dayOfWeek: 'MON',
      targetCheckNames: [
        'CA_CERTIFICATE_EXPIRING_CHECK',
        'DEVICE_CERTIFICATE_EXPIRING_CHECK',
        'DEVICE_CERTIFICATE_SHARED_CHECK',
        'IOT_POLICY_OVERLY_PERMISSIVE_CHECK',
        'CONFLICTING_CLIENT_IDS_CHECK'
      ]
    });

    // CloudWatch Alarm for security violations
    const securityViolationsAlarm = new cdk.aws_cloudwatch.Alarm(this, 'SecurityViolationsAlarm', {
      alarmName: `IoT-SecurityViolations-${uniqueSuffix}`,
      alarmDescription: 'Alert on IoT Device Defender security violations',
      metric: new cdk.aws_cloudwatch.Metric({
        namespace: 'AWS/IoT/DeviceDefender',
        metricName: 'Violations',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1,
      comparisonOperator: cdk.aws_cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cdk.aws_cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS action to the alarm
    securityViolationsAlarm.addAlarmAction(
      new cdk.aws_cloudwatch_actions.SnsAction(securityAlertsTopic)
    );

    // Custom resource to configure IoT Account Audit Configuration
    // This enables audit checks and configures notification targets
    const auditConfigFunction = new cdk.aws_lambda.Function(this, 'AuditConfigFunction', {
      runtime: cdk.aws_lambda.Runtime.PYTHON_3_11,
      handler: 'index.handler',
      timeout: cdk.Duration.minutes(5),
      description: 'Configure IoT Device Defender audit settings',
      code: cdk.aws_lambda.Code.fromInline(`
import json
import boto3
import cfnresponse

def handler(event, context):
    try:
        iot_client = boto3.client('iot')
        
        if event['RequestType'] == 'Create' or event['RequestType'] == 'Update':
            # Configure audit settings
            response = iot_client.update_account_audit_configuration(
                roleArn=event['ResourceProperties']['RoleArn'],
                auditNotificationTargetConfigurations={
                    'SNS': {
                        'targetArn': event['ResourceProperties']['SnsTopicArn'],
                        'roleArn': event['ResourceProperties']['RoleArn'],
                        'enabled': True
                    }
                },
                auditCheckConfigurations={
                    'AUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK': {'enabled': True},
                    'CA_CERTIFICATE_EXPIRING_CHECK': {'enabled': True},
                    'CONFLICTING_CLIENT_IDS_CHECK': {'enabled': True},
                    'DEVICE_CERTIFICATE_EXPIRING_CHECK': {'enabled': True},
                    'DEVICE_CERTIFICATE_SHARED_CHECK': {'enabled': True},
                    'IOT_POLICY_OVERLY_PERMISSIVE_CHECK': {'enabled': True},
                    'LOGGING_DISABLED_CHECK': {'enabled': True},
                    'REVOKED_CA_CERTIFICATE_STILL_ACTIVE_CHECK': {'enabled': True},
                    'REVOKED_DEVICE_CERTIFICATE_STILL_ACTIVE_CHECK': {'enabled': True},
                    'UNAUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK': {'enabled': True}
                }
            )
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
        
        elif event['RequestType'] == 'Delete':
            # Disable audit checks on deletion
            try:
                iot_client.update_account_audit_configuration(
                    auditCheckConfigurations={
                        'AUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK': {'enabled': False},
                        'CA_CERTIFICATE_EXPIRING_CHECK': {'enabled': False},
                        'CONFLICTING_CLIENT_IDS_CHECK': {'enabled': False},
                        'DEVICE_CERTIFICATE_EXPIRING_CHECK': {'enabled': False},
                        'DEVICE_CERTIFICATE_SHARED_CHECK': {'enabled': False},
                        'IOT_POLICY_OVERLY_PERMISSIVE_CHECK': {'enabled': False},
                        'LOGGING_DISABLED_CHECK': {'enabled': False},
                        'REVOKED_CA_CERTIFICATE_STILL_ACTIVE_CHECK': {'enabled': False},
                        'REVOKED_DEVICE_CERTIFICATE_STILL_ACTIVE_CHECK': {'enabled': False},
                        'UNAUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK': {'enabled': False}
                    }
                )
            except:
                pass  # Ignore errors during cleanup
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            
    except Exception as e:
        print(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
      `)
    });

    // Grant permissions to the Lambda function
    auditConfigFunction.addToRolePolicy(new cdk.aws_iam.PolicyStatement({
      effect: cdk.aws_iam.Effect.ALLOW,
      actions: [
        'iot:UpdateAccountAuditConfiguration',
        'iot:DescribeAccountAuditConfiguration'
      ],
      resources: ['*']
    }));

    // Custom resource to invoke the audit configuration function
    const auditConfigCustomResource = new cdk.CustomResource(this, 'AuditConfigCustomResource', {
      serviceToken: auditConfigFunction.functionArn,
      properties: {
        RoleArn: deviceDefenderRole.roleArn,
        SnsTopicArn: securityAlertsTopic.topicArn
      }
    });

    // Ensure the custom resource depends on the role and topic
    auditConfigCustomResource.node.addDependency(deviceDefenderRole);
    auditConfigCustomResource.node.addDependency(securityAlertsTopic);

    // Outputs
    new cdk.CfnOutput(this, 'SecurityAlertsTopicArn', {
      value: securityAlertsTopic.topicArn,
      description: 'ARN of the SNS topic for security alerts',
      exportName: `${this.stackName}-SecurityAlertsTopicArn`
    });

    new cdk.CfnOutput(this, 'DeviceDefenderRoleArn', {
      value: deviceDefenderRole.roleArn,
      description: 'ARN of the Device Defender IAM role',
      exportName: `${this.stackName}-DeviceDefenderRoleArn`
    });

    new cdk.CfnOutput(this, 'SecurityProfileName', {
      value: securityProfile.securityProfileName!,
      description: 'Name of the IoT Device Defender security profile',
      exportName: `${this.stackName}-SecurityProfileName`
    });

    new cdk.CfnOutput(this, 'MLSecurityProfileName', {
      value: mlSecurityProfile.securityProfileName!,
      description: 'Name of the ML-based security profile',
      exportName: `${this.stackName}-MLSecurityProfileName`
    });

    new cdk.CfnOutput(this, 'ScheduledAuditName', {
      value: scheduledAudit.scheduledAuditName!,
      description: 'Name of the scheduled audit task',
      exportName: `${this.stackName}-ScheduledAuditName`
    });

    new cdk.CfnOutput(this, 'SecurityViolationsAlarmName', {
      value: securityViolationsAlarm.alarmName,
      description: 'Name of the CloudWatch alarm for security violations',
      exportName: `${this.stackName}-SecurityViolationsAlarmName`
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Application', 'IoT-Device-Defender');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'Security-Team');
    cdk.Tags.of(this).add('CostCenter', 'IoT-Security');
  }
}

// CDK App
const app = new cdk.App();

// Get context values with defaults
const stackName = app.node.tryGetContext('stackName') || 'IoTDeviceDefenderSecurityStack';
const environment = app.node.tryGetContext('environment') || 'prod';

new IoTDeviceDefenderSecurityStack(app, stackName, {
  description: 'AWS IoT Device Defender Security Monitoring Stack - Implements comprehensive IoT security with behavioral analysis and automated audits',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  tags: {
    Application: 'IoT-Device-Defender',
    Environment: environment,
    ManagedBy: 'CDK'
  }
});

app.synth();