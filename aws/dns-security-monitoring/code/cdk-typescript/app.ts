#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as route53resolver from 'aws-cdk-lib/aws-route53resolver';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as iam from 'aws-cdk-lib/aws-iam';
import { randomBytes } from 'crypto';

/**
 * Props for the DNS Security Monitoring Stack
 */
export interface DnsSecurityMonitoringStackProps extends cdk.StackProps {
  /**
   * VPC ID where DNS monitoring will be applied
   * If not provided, the default VPC will be used
   */
  readonly vpcId?: string;
  
  /**
   * Email address for security alerts
   */
  readonly alertEmail?: string;
  
  /**
   * List of malicious domains to block
   * Default includes common test domains for demonstration
   */
  readonly maliciousDomains?: string[];
  
  /**
   * CloudWatch alarm threshold for blocked DNS queries
   * @default 50
   */
  readonly blockedQueryThreshold?: number;
  
  /**
   * CloudWatch alarm threshold for unusual DNS query volume
   * @default 1000
   */
  readonly queryVolumeThreshold?: number;
  
  /**
   * Log group retention period in days
   * @default 30
   */
  readonly logRetentionDays?: number;
}

/**
 * CDK Stack for automated DNS security monitoring using Route 53 Resolver DNS Firewall
 * 
 * This stack creates:
 * - Route 53 Resolver DNS Firewall with domain lists and rule groups
 * - CloudWatch logging and monitoring for DNS queries
 * - Lambda function for automated threat response
 * - SNS notifications for security alerts
 * - CloudWatch alarms for threat detection
 */
export class DnsSecurityMonitoringStack extends cdk.Stack {
  public readonly dnsFirewallRuleGroup: route53resolver.CfnFirewallRuleGroup;
  public readonly securityAlertsTopic: sns.Topic;
  public readonly responseFunction: lambda.Function;
  public readonly queryLogGroup: logs.LogGroup;

  constructor(scope: Construct, id: string, props?: DnsSecurityMonitoringStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = randomBytes(3).toString('hex');
    
    // Configuration with defaults
    const maliciousDomains = props?.maliciousDomains || [
      'malware.example',
      'suspicious.tk', 
      'phishing.com',
      'badactor.ru',
      'cryptominer.xyz',
      'botnet.info'
    ];
    
    const blockedQueryThreshold = props?.blockedQueryThreshold || 50;
    const queryVolumeThreshold = props?.queryVolumeThreshold || 1000;
    const logRetentionDays = props?.logRetentionDays || 30;

    // Get VPC reference
    let vpc: ec2.IVpc;
    if (props?.vpcId) {
      vpc = ec2.Vpc.fromLookup(this, 'ExistingVpc', { vpcId: props.vpcId });
    } else {
      vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', { isDefault: true });
    }

    // Create SNS topic for security alerts
    this.securityAlertsTopic = new sns.Topic(this, 'DnsSecurityAlerts', {
      topicName: `dns-security-alerts-${uniqueSuffix}`,
      displayName: 'DNS Security Monitoring Alerts',
      description: 'SNS topic for DNS security monitoring alerts and automated responses'
    });

    // Add email subscription if provided
    if (props?.alertEmail) {
      this.securityAlertsTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.alertEmail)
      );
    }

    // Create CloudWatch log group for DNS query logging
    this.queryLogGroup = new logs.LogGroup(this, 'DnsQueryLogGroup', {
      logGroupName: `/aws/route53resolver/dns-security-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create DNS Firewall domain list for malicious domains
    const domainList = new route53resolver.CfnFirewallDomainList(this, 'MaliciousDomainList', {
      name: `malicious-domains-${uniqueSuffix}`,
      domains: maliciousDomains,
      tags: [
        {
          key: 'Purpose',
          value: 'DNS Security Monitoring'
        },
        {
          key: 'ManagedBy',
          value: 'CDK'
        }
      ]
    });

    // Create DNS Firewall rule group
    this.dnsFirewallRuleGroup = new route53resolver.CfnFirewallRuleGroup(this, 'DnsSecurityRuleGroup', {
      name: `dns-security-rules-${uniqueSuffix}`,
      firewallRules: [
        {
          firewallDomainListId: domainList.attrId,
          priority: 100,
          action: 'BLOCK',
          blockResponse: 'NXDOMAIN',
          name: 'block-malicious-domains'
        }
      ],
      tags: [
        {
          key: 'Purpose',
          value: 'DNS Security Monitoring'
        },
        {
          key: 'ManagedBy',
          value: 'CDK'
        }
      ]
    });

    // Associate DNS Firewall rule group with VPC
    const firewallAssociation = new route53resolver.CfnFirewallRuleGroupAssociation(this, 'VpcFirewallAssociation', {
      name: `vpc-dns-security-${uniqueSuffix}`,
      firewallRuleGroupId: this.dnsFirewallRuleGroup.attrId,
      vpcId: vpc.vpcId,
      priority: 101,
      tags: [
        {
          key: 'Purpose',
          value: 'DNS Security Monitoring'
        },
        {
          key: 'ManagedBy',
          value: 'CDK'
        }
      ]
    });

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'DnsSecurityLambdaRole', {
      roleName: `dns-security-lambda-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        CloudWatchMetrics: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:GetMetricStatistics',
                'cloudwatch:ListMetrics'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Create Lambda function for automated threat response
    this.responseFunction = new lambda.Function(this, 'DnsSecurityResponseFunction', {
      functionName: `dns-security-response-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      description: 'Automated response function for DNS security events',
      environment: {
        SNS_TOPIC_ARN: this.securityAlertsTopic.topicArn
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Parse CloudWatch alarm data
        message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = message['AlarmName']
        alarm_description = message['AlarmDescription']
        metric_name = message['Trigger']['MetricName']
        
        # Create detailed alert message
        alert_message = f"""
DNS Security Alert Triggered

Alarm: {alarm_name}
Description: {alarm_description}
Metric: {metric_name}
Timestamp: {datetime.now().isoformat()}
Account: {context.invoked_function_arn.split(':')[4]}
Region: {context.invoked_function_arn.split(':')[3]}

Recommended Actions:
1. Review DNS query logs for suspicious patterns
2. Investigate source IP addresses and instances
3. Update DNS Firewall rules if needed
4. Consider blocking additional domains or IP ranges

This alert was generated automatically by the DNS Security Monitoring system.
"""
        
        # Log the event for audit trail
        logger.info(f"DNS security event processed: {alarm_name}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'DNS security alert processed successfully',
                'alarm': alarm_name
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing DNS security alert: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
`)
    });

    // Grant SNS permissions to Lambda function
    this.securityAlertsTopic.grantPublish(this.responseFunction);

    // Add Lambda function as SNS subscriber
    this.securityAlertsTopic.addSubscription(
      new snsSubscriptions.LambdaSubscription(this.responseFunction)
    );

    // Create CloudWatch alarm for blocked DNS queries
    const blockedQueriesAlarm = new cloudwatch.Alarm(this, 'DnsHighBlockRateAlarm', {
      alarmName: `DNS-High-Block-Rate-${uniqueSuffix}`,
      alarmDescription: 'High rate of blocked DNS queries detected - potential security threat',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Route53Resolver',
        metricName: 'QueryCount',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
        dimensionsMap: {
          FirewallRuleGroupId: this.dnsFirewallRuleGroup.attrId
        }
      }),
      threshold: blockedQueryThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Create CloudWatch alarm for unusual query volume
    const queryVolumeAlarm = new cloudwatch.Alarm(this, 'DnsUnusualVolumeAlarm', {
      alarmName: `DNS-Unusual-Volume-${uniqueSuffix}`,
      alarmDescription: 'Unusual DNS query volume detected - investigate for potential DGA or tunneling',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Route53Resolver',
        metricName: 'QueryCount',
        statistic: 'Sum',
        period: cdk.Duration.minutes(15),
        dimensionsMap: {
          VpcId: vpc.vpcId
        }
      }),
      threshold: queryVolumeThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS action to alarms
    const snsAction = new cloudwatchActions.SnsAction(this.securityAlertsTopic);
    blockedQueriesAlarm.addAlarmAction(snsAction);
    queryVolumeAlarm.addAlarmAction(snsAction);

    // Create DNS query logging configuration
    const queryLogConfig = new route53resolver.CfnResolverQueryLogConfig(this, 'DnsQueryLogConfig', {
      name: `dns-security-logs-${uniqueSuffix}`,
      destinationArn: this.queryLogGroup.logGroupArn
    });

    // Associate query logging with VPC
    new route53resolver.CfnResolverQueryLogConfigAssociation(this, 'QueryLogAssociation', {
      resolverQueryLogConfigId: queryLogConfig.attrId,
      resourceId: vpc.vpcId
    });

    // Stack outputs for reference
    new cdk.CfnOutput(this, 'DnsFirewallRuleGroupId', {
      value: this.dnsFirewallRuleGroup.attrId,
      description: 'DNS Firewall Rule Group ID',
      exportName: `${this.stackName}-DnsFirewallRuleGroupId`
    });

    new cdk.CfnOutput(this, 'SecurityAlertsTopicArn', {
      value: this.securityAlertsTopic.topicArn,
      description: 'SNS Topic ARN for security alerts',
      exportName: `${this.stackName}-SecurityAlertsTopicArn`
    });

    new cdk.CfnOutput(this, 'ResponseFunctionArn', {
      value: this.responseFunction.functionArn,
      description: 'Lambda function ARN for automated response',
      exportName: `${this.stackName}-ResponseFunctionArn`
    });

    new cdk.CfnOutput(this, 'QueryLogGroupName', {
      value: this.queryLogGroup.logGroupName,
      description: 'CloudWatch log group for DNS queries',
      exportName: `${this.stackName}-QueryLogGroupName`
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: vpc.vpcId,
      description: 'VPC ID where DNS monitoring is configured',
      exportName: `${this.stackName}-VpcId`
    });

    new cdk.CfnOutput(this, 'BlockedQueryAlarmName', {
      value: blockedQueriesAlarm.alarmName,
      description: 'CloudWatch alarm for blocked DNS queries',
      exportName: `${this.stackName}-BlockedQueryAlarmName`
    });

    new cdk.CfnOutput(this, 'QueryVolumeAlarmName', {
      value: queryVolumeAlarm.alarmName,
      description: 'CloudWatch alarm for unusual query volume',
      exportName: `${this.stackName}-QueryVolumeAlarmName`
    });
  }
}

/**
 * Main CDK Application
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const alertEmail = app.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL;
const vpcId = app.node.tryGetContext('vpcId') || process.env.VPC_ID;
const blockedQueryThreshold = Number(app.node.tryGetContext('blockedQueryThreshold')) || Number(process.env.BLOCKED_QUERY_THRESHOLD) || 50;
const queryVolumeThreshold = Number(app.node.tryGetContext('queryVolumeThreshold')) || Number(process.env.QUERY_VOLUME_THRESHOLD) || 1000;

// Custom malicious domains (can be overridden via context)
const customDomains = app.node.tryGetContext('maliciousDomains');
const maliciousDomains = customDomains ? customDomains.split(',') : undefined;

// Create the DNS Security Monitoring stack
new DnsSecurityMonitoringStack(app, 'DnsSecurityMonitoringStack', {
  description: 'Automated DNS security monitoring with Route 53 Resolver DNS Firewall and CloudWatch',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  alertEmail,
  vpcId,
  maliciousDomains,
  blockedQueryThreshold,
  queryVolumeThreshold,
  tags: {
    Project: 'DNS Security Monitoring',
    Environment: 'Production',
    ManagedBy: 'AWS CDK',
    CostCenter: 'Security',
    Owner: 'Security Team'
  }
});

app.synth();