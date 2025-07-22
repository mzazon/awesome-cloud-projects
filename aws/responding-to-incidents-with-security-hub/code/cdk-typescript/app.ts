#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import {
  Duration,
  RemovalPolicy,
  Stack,
  StackProps,
  aws_events as events,
  aws_events_targets as targets,
  aws_iam as iam,
  aws_lambda as lambda,
  aws_logs as logs,
  aws_securityhub as securityhub,
  aws_sns as sns,
  aws_sns_subscriptions as subscriptions,
  aws_sqs as sqs,
  aws_cloudwatch as cloudwatch,
} from 'aws-cdk-lib';
import { Construct } from 'constructs';

/**
 * Properties for the SecurityIncidentResponseStack
 */
interface SecurityIncidentResponseStackProps extends StackProps {
  /**
   * Email address for security incident notifications
   * @default - No email notifications configured
   */
  readonly notificationEmail?: string;

  /**
   * Prefix for resource naming
   * @default 'SecurityHub'
   */
  readonly resourcePrefix?: string;

  /**
   * Whether to enable Security Hub (set to false if already enabled)
   * @default true
   */
  readonly enableSecurityHub?: boolean;

  /**
   * SNS topic retention period in days
   * @default 14
   */
  readonly snsRetentionDays?: number;
}

/**
 * CDK Stack for AWS Security Hub Incident Response Automation
 * 
 * This stack creates a comprehensive security incident response system using:
 * - AWS Security Hub as the central hub for security findings
 * - EventBridge for event-driven automation
 * - Lambda for custom incident processing logic
 * - SNS for notifications to ticketing systems
 * - SQS for reliable message buffering
 * - CloudWatch for monitoring and alerting
 */
export class SecurityIncidentResponseStack extends Stack {
  public readonly snsTopicArn: string;
  public readonly lambdaFunctionArn: string;
  public readonly customActionArn: string;

  constructor(scope: Construct, id: string, props: SecurityIncidentResponseStackProps = {}) {
    super(scope, id, props);

    const resourcePrefix = props.resourcePrefix || 'SecurityHub';
    const enableSecurityHub = props.enableSecurityHub ?? true;
    const snsRetentionDays = props.snsRetentionDays || 14;

    // Generate a unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 6);

    // Create IAM role for Lambda incident processor
    const lambdaRole = new iam.Role(this, 'IncidentProcessorRole', {
      roleName: `${resourcePrefix}LambdaRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Security Hub incident processing Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        SecurityHubAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'securityhub:BatchUpdateFindings',
                'securityhub:GetFindings',
                'sns:Publish',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create SNS topic for incident notifications
    const incidentTopic = new sns.Topic(this, 'IncidentNotificationTopic', {
      topicName: `${resourcePrefix.toLowerCase()}-incident-alerts-${uniqueSuffix}`,
      displayName: 'Security Incident Alerts',
      description: 'SNS topic for security incident notifications and integrations',
    });

    // Configure SNS topic delivery policy for robust message delivery
    const deliveryPolicy = {
      http: {
        defaultHealthyRetryPolicy: {
          numRetries: 3,
          minDelayTarget: 20,
          maxDelayTarget: 20,
          numMinDelayRetries: 0,
          numMaxDelayRetries: 0,
          numNoDelayRetries: 0,
          backoffFunction: 'linear',
        },
        disableSubscriptionOverrides: false,
      },
    };

    // Add resource policy to allow Lambda to publish messages
    incidentTopic.addToResourcePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('lambda.amazonaws.com')],
        actions: ['SNS:Publish'],
        resources: [incidentTopic.topicArn],
      })
    );

    // Create SQS queue for buffering incident notifications
    const incidentQueue = new sqs.Queue(this, 'IncidentNotificationQueue', {
      queueName: `${resourcePrefix.toLowerCase()}-incident-queue-${uniqueSuffix}`,
      description: 'SQS queue for buffering security incident notifications',
      messageRetentionPeriod: Duration.days(snsRetentionDays),
      receiveMessageWaitTime: Duration.seconds(20),
      visibilityTimeout: Duration.minutes(5),
    });

    // Subscribe SQS queue to SNS topic for reliable message delivery
    incidentTopic.addSubscription(new subscriptions.SqsSubscription(incidentQueue));

    // Subscribe email endpoint if provided
    if (props.notificationEmail) {
      incidentTopic.addSubscription(
        new subscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create Lambda function for incident processing
    const incidentProcessorFunction = new lambda.Function(this, 'IncidentProcessorFunction', {
      functionName: `${resourcePrefix.toLowerCase()}-incident-processor-${uniqueSuffix}`,
      description: 'Processes Security Hub findings and manages incident response workflows',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: Duration.seconds(60),
      memorySize: 256,
      environment: {
        SNS_TOPIC_ARN: incidentTopic.topicArn,
        AWS_REGION: this.region,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Process Security Hub findings and orchestrate incident response
    """
    # Initialize AWS clients
    sns = boto3.client('sns')
    securityhub = boto3.client('securityhub')
    
    try:
        # Process Security Hub finding
        finding = event['detail']['findings'][0]
        
        # Extract key information
        severity = finding.get('Severity', {}).get('Label', 'UNKNOWN')
        title = finding.get('Title', 'Unknown Security Finding')
        description = finding.get('Description', 'No description available')
        account_id = finding.get('AwsAccountId', 'Unknown')
        region = finding.get('Region', 'Unknown')
        finding_id = finding.get('Id', 'Unknown')
        
        # Determine response based on severity
        response_action = determine_response_action(severity)
        
        # Create incident ticket payload
        incident_payload = {
            'finding_id': finding_id,
            'severity': severity,
            'title': title,
            'description': description,
            'account_id': account_id,
            'region': region,
            'timestamp': datetime.utcnow().isoformat(),
            'response_action': response_action,
            'source': 'AWS Security Hub'
        }
        
        # Send notification to SNS
        message = create_incident_message(incident_payload)
        
        response = sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=json.dumps(message, indent=2),
            Subject=f"Security Incident: {severity} - {title[:50]}",
            MessageAttributes={
                'severity': {
                    'DataType': 'String',
                    'StringValue': severity
                },
                'account_id': {
                    'DataType': 'String',
                    'StringValue': account_id
                }
            }
        )
        
        # Update finding with response action
        update_finding_workflow(securityhub, finding_id, response_action)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Incident processed successfully',
                'finding_id': finding_id,
                'severity': severity,
                'response_action': response_action
            })
        }
        
    except Exception as e:
        print(f"Error processing incident: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'finding_id': finding.get('Id', 'Unknown') if 'finding' in locals() else 'Unknown'
            })
        }

def determine_response_action(severity):
    """Determine appropriate response action based on severity"""
    if severity == 'CRITICAL':
        return 'immediate_response'
    elif severity == 'HIGH':
        return 'escalated_response'
    elif severity == 'MEDIUM':
        return 'standard_response'
    else:
        return 'low_priority_response'

def create_incident_message(payload):
    """Create formatted incident message"""
    return {
        'incident_details': {
            'id': payload['finding_id'],
            'severity': payload['severity'],
            'title': payload['title'],
            'description': payload['description'],
            'account': payload['account_id'],
            'region': payload['region'],
            'timestamp': payload['timestamp']
        },
        'response_plan': {
            'action': payload['response_action'],
            'priority': get_priority_level(payload['severity']),
            'sla': get_sla_minutes(payload['severity'])
        },
        'integration': {
            'jira_project': 'SEC',
            'slack_channel': '#security-incidents',
            'pagerduty_service': 'security-team'
        }
    }

def get_priority_level(severity):
    """Map severity to priority level"""
    priority_map = {
        'CRITICAL': 'P1',
        'HIGH': 'P2',
        'MEDIUM': 'P3',
        'LOW': 'P4',
        'INFORMATIONAL': 'P5'
    }
    return priority_map.get(severity, 'P4')

def get_sla_minutes(severity):
    """Get SLA response time in minutes"""
    sla_map = {
        'CRITICAL': 15,
        'HIGH': 60,
        'MEDIUM': 240,
        'LOW': 1440,
        'INFORMATIONAL': 2880
    }
    return sla_map.get(severity, 1440)

def update_finding_workflow(securityhub, finding_id, response_action):
    """Update finding workflow status"""
    try:
        securityhub.batch_update_findings(
            FindingIdentifiers=[{
                'Id': finding_id,
                'ProductArn': f'arn:aws:securityhub:{os.environ["AWS_REGION"]}::product/aws/securityhub'
            }],
            Note={
                'Text': f'Automated incident response initiated: {response_action}',
                'UpdatedBy': 'SecurityHubAutomation'
            },
            Workflow={
                'Status': 'NOTIFIED'
            }
        )
    except Exception as e:
        print(f"Error updating finding workflow: {str(e)}")
`),
      logRetention: logs.RetentionDays.TWO_WEEKS,
    });

    // Create threat intelligence Lambda function
    const threatIntelFunction = new lambda.Function(this, 'ThreatIntelligenceFunction', {
      functionName: `${resourcePrefix.toLowerCase()}-threat-intel-${uniqueSuffix}`,
      description: 'Enriches security findings with threat intelligence data',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: Duration.seconds(60),
      memorySize: 256,
      code: lambda.Code.fromInline(`
import json
import boto3
import re
import os

def lambda_handler(event, context):
    """
    Enrich security findings with threat intelligence data
    """
    try:
        finding = event['detail']['findings'][0]
        
        # Extract IP addresses, domains, hashes from finding
        resources = finding.get('Resources', [])
        threat_indicators = extract_threat_indicators(resources)
        
        # Calculate threat score based on indicators
        threat_score = calculate_threat_score(threat_indicators)
        
        # Update finding with threat intelligence
        securityhub = boto3.client('securityhub')
        
        securityhub.batch_update_findings(
            FindingIdentifiers=[{
                'Id': finding['Id'],
                'ProductArn': finding['ProductArn']
            }],
            Note={
                'Text': f'Threat Intelligence Score: {threat_score}/100. Indicators: {len(threat_indicators)}',
                'UpdatedBy': 'ThreatIntelligence'
            },
            UserDefinedFields={
                'ThreatScore': str(threat_score),
                'ThreatIndicators': str(len(threat_indicators))
            }
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'threat_score': threat_score,
                'indicators_found': len(threat_indicators)
            })
        }
        
    except Exception as e:
        print(f"Error updating finding with threat intelligence: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def extract_threat_indicators(resources):
    """Extract potential threat indicators from resources"""
    indicators = []
    
    for resource in resources:
        resource_id = resource.get('Id', '')
        
        # Look for IP addresses
        ip_pattern = r'\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\\b'
        ips = re.findall(ip_pattern, resource_id)
        indicators.extend(ips)
        
        # Look for domains
        domain_pattern = r'\\b[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}\\b'
        domains = re.findall(domain_pattern, resource_id)
        indicators.extend(domains)
    
    return indicators

def calculate_threat_score(indicators):
    """Calculate threat score based on indicators"""
    base_score = 10
    indicator_bonus = len(indicators) * 5
    
    return min(base_score + indicator_bonus, 100)
`),
      logRetention: logs.RetentionDays.TWO_WEEKS,
    });

    // Create EventBridge rule for high severity findings
    const highSeverityRule = new events.Rule(this, 'HighSeverityFindingsRule', {
      ruleName: `${resourcePrefix.toLowerCase()}-high-severity`,
      description: 'Process high and critical severity Security Hub findings',
      enabled: true,
      eventPattern: {
        source: ['aws.securityhub'],
        detailType: ['Security Hub Findings - Imported'],
        detail: {
          findings: {
            Severity: {
              Label: ['HIGH', 'CRITICAL'],
            },
            Workflow: {
              Status: ['NEW'],
            },
          },
        },
      },
    });

    // Add Lambda function as target for high severity rule
    highSeverityRule.addTarget(new targets.LambdaFunction(incidentProcessorFunction));

    // Create Security Hub custom action for manual escalation
    const customAction = new securityhub.CfnActionTarget(this, 'EscalateToSOCAction', {
      name: 'Escalate to SOC',
      description: 'Escalate this finding to the Security Operations Center',
      id: `escalate-to-soc-${uniqueSuffix}`,
    });

    // Create EventBridge rule for custom action
    const customActionRule = new events.Rule(this, 'CustomEscalationRule', {
      ruleName: `${resourcePrefix.toLowerCase()}-custom-escalation`,
      description: 'Process manual escalation from Security Hub',
      enabled: true,
      eventPattern: {
        source: ['aws.securityhub'],
        detailType: ['Security Hub Findings - Custom Action'],
        detail: {
          actionName: ['Escalate to SOC'],
          actionDescription: ['Escalate this finding to the Security Operations Center'],
        },
      },
    });

    // Add Lambda function as target for custom action rule
    customActionRule.addTarget(new targets.LambdaFunction(incidentProcessorFunction));

    // Create Security Hub automation rules
    const suppressionRule = new securityhub.CfnAutomationRule(this, 'SuppressionRule', {
      ruleName: 'Suppress Low Priority Findings',
      description: 'Automatically suppress informational findings from specific controls',
      ruleOrder: 1,
      ruleStatus: 'ENABLED',
      criteria: {
        severityLabel: [{ value: 'INFORMATIONAL', comparison: 'EQUALS' }],
        generatorId: [{ value: 'aws-foundational-security-best-practices', comparison: 'PREFIX' }],
      },
      actions: [
        {
          type: 'FINDING_FIELDS_UPDATE',
          findingFieldsUpdate: {
            note: {
              text: 'Low priority finding automatically suppressed by automation rule',
              updatedBy: 'SecurityHubAutomation',
            },
            workflow: {
              status: 'SUPPRESSED',
            },
          },
        },
      ],
    });

    const escalationRule = new securityhub.CfnAutomationRule(this, 'EscalationRule', {
      ruleName: 'Escalate Critical Findings',
      description: 'Automatically escalate critical findings and add priority notes',
      ruleOrder: 2,
      ruleStatus: 'ENABLED',
      criteria: {
        severityLabel: [{ value: 'CRITICAL', comparison: 'EQUALS' }],
        workflow: {
          status: [{ value: 'NEW', comparison: 'EQUALS' }],
        },
      },
      actions: [
        {
          type: 'FINDING_FIELDS_UPDATE',
          findingFieldsUpdate: {
            note: {
              text: 'CRITICAL: Immediate attention required. Escalated to SOC automatically.',
              updatedBy: 'SecurityHubAutomation',
            },
            workflow: {
              status: 'NOTIFIED',
            },
          },
        },
      ],
    });

    // Create CloudWatch dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'SecurityHubDashboard', {
      dashboardName: `${resourcePrefix}IncidentResponse`,
    });

    // Add Lambda metrics widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Security Incident Processing Metrics',
        left: [
          incidentProcessorFunction.metricInvocations(),
          incidentProcessorFunction.metricErrors(),
        ],
        right: [incidentProcessorFunction.metricDuration()],
        period: Duration.minutes(5),
        statistic: cloudwatch.Statistic.SUM,
      })
    );

    // Add SNS metrics widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Notification Delivery Metrics',
        left: [
          incidentTopic.metricNumberOfMessagesPublished(),
          incidentTopic.metricNumberOfNotificationsFailed(),
        ],
        period: Duration.minutes(5),
        statistic: cloudwatch.Statistic.SUM,
      })
    );

    // Create CloudWatch alarm for failed incident processing
    const processingFailureAlarm = new cloudwatch.Alarm(this, 'IncidentProcessingFailureAlarm', {
      alarmName: `${resourcePrefix}IncidentProcessingFailures`,
      alarmDescription: 'Alert when Security Hub incident processing fails',
      metric: incidentProcessorFunction.metricErrors(),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
    });

    // Send alarm notifications to SNS topic
    processingFailureAlarm.addAlarmAction(new cloudwatch.SnsAction(incidentTopic));

    // Enable Security Hub if requested
    if (enableSecurityHub) {
      const securityHubHub = new securityhub.CfnHub(this, 'SecurityHub', {
        tags: [
          { key: 'Project', value: 'IncidentResponse' },
          { key: 'Environment', value: 'Production' },
        ],
      });

      // Enable AWS Foundational Security Standard
      new securityhub.CfnStandardsSubscription(this, 'FoundationalStandard', {
        standardsArn: `arn:aws:securityhub:${this.region}::standards/aws-foundational-security-best-practices/v/1.0.0`,
        dependsOn: [securityHubHub],
      });

      // Enable CIS AWS Foundations Benchmark
      new securityhub.CfnStandardsSubscription(this, 'CISStandard', {
        standardsArn: `arn:aws:securityhub:${this.region}::standards/cis-aws-foundations-benchmark/v/1.2.0`,
        dependsOn: [securityHubHub],
      });
    }

    // Store important ARNs as stack outputs
    this.snsTopicArn = incidentTopic.topicArn;
    this.lambdaFunctionArn = incidentProcessorFunction.functionArn;
    this.customActionArn = customAction.attrActionTargetArn;

    // CDK Outputs for integration with other systems
    new cdk.CfnOutput(this, 'SNSTopicArnOutput', {
      value: incidentTopic.topicArn,
      description: 'ARN of the SNS topic for security incident notifications',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArnOutput', {
      value: incidentProcessorFunction.functionArn,
      description: 'ARN of the Lambda function for incident processing',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'CustomActionArnOutput', {
      value: customAction.attrActionTargetArn,
      description: 'ARN of the Security Hub custom action for manual escalation',
      exportName: `${this.stackName}-CustomActionArn`,
    });

    new cdk.CfnOutput(this, 'SQSQueueUrlOutput', {
      value: incidentQueue.queueUrl,
      description: 'URL of the SQS queue for incident notification buffering',
      exportName: `${this.stackName}-SQSQueueUrl`,
    });

    new cdk.CfnOutput(this, 'DashboardUrlOutput', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'URL of the CloudWatch dashboard for monitoring',
    });
  }
}

// CDK App
const app = new cdk.App();

// Get context values for stack configuration
const resourcePrefix = app.node.tryGetContext('resourcePrefix') || 'SecurityHub';
const notificationEmail = app.node.tryGetContext('notificationEmail');
const enableSecurityHub = app.node.tryGetContext('enableSecurityHub') ?? true;

new SecurityIncidentResponseStack(app, 'SecurityIncidentResponseStack', {
  description: 'AWS Security Hub Incident Response Automation Stack',
  resourcePrefix,
  notificationEmail,
  enableSecurityHub,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'SecurityIncidentResponse',
    Environment: 'Production',
    Stack: 'SecurityHub',
  },
});

app.synth();