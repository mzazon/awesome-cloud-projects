#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cw_actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';

/**
 * Configuration interface for the State Manager stack
 */
interface SSMStateManagerStackProps extends cdk.StackProps {
  /**
   * Email address for SNS notifications
   */
  readonly notificationEmail: string;
  
  /**
   * Environment tag for targeting instances
   */
  readonly environmentTag?: string;
  
  /**
   * Custom name prefix for resources
   */
  readonly namePrefix?: string;
  
  /**
   * CloudWatch log retention period in days
   */
  readonly logRetentionDays?: logs.RetentionDays;
  
  /**
   * Schedule expression for security configuration checks
   */
  readonly securityCheckSchedule?: string;
  
  /**
   * Schedule expression for SSM Agent updates
   */
  readonly agentUpdateSchedule?: string;
}

/**
 * AWS CDK Stack for Configuration Management with Systems Manager
 * 
 * This stack creates:
 * - IAM roles and policies for State Manager operations
 * - Custom SSM documents for security configuration
 * - State Manager associations for configuration enforcement
 * - CloudWatch monitoring and alerting
 * - SNS notifications for drift detection
 * - Automation documents for remediation
 * - CloudWatch dashboard for compliance monitoring
 */
export class SSMStateManagerStack extends cdk.Stack {
  // Public properties for accessing created resources
  public readonly stateManagerRole: iam.Role;
  public readonly snsTopicArn: string;
  public readonly securityDocument: ssm.CfnDocument;
  public readonly cloudWatchLogGroup: logs.LogGroup;
  public readonly complianceDashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: SSMStateManagerStackProps) {
    super(scope, id, props);

    // Extract configuration with defaults
    const namePrefix = props.namePrefix || 'SSMStateManager';
    const environmentTag = props.environmentTag || 'Demo';
    const logRetentionDays = props.logRetentionDays || logs.RetentionDays.ONE_MONTH;
    const securityCheckSchedule = props.securityCheckSchedule || 'rate(1 day)';
    const agentUpdateSchedule = props.agentUpdateSchedule || 'rate(7 days)';

    // Create CloudWatch log group for State Manager operations
    this.cloudWatchLogGroup = new logs.LogGroup(this, 'StateManagerLogGroup', {
      logGroupName: `/aws/ssm/state-manager-${namePrefix.toLowerCase()}`,
      retention: logRetentionDays,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create SNS topic for configuration drift alerts
    const driftAlertsTopic = new sns.Topic(this, 'ConfigDriftAlerts', {
      topicName: `config-drift-alerts-${namePrefix.toLowerCase()}`,
      displayName: 'Configuration Drift Alerts',
    });

    // Store SNS topic ARN for external access
    this.snsTopicArn = driftAlertsTopic.topicArn;

    // Subscribe email to SNS topic for notifications
    driftAlertsTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(props.notificationEmail)
    );

    // Create IAM role for State Manager operations
    this.stateManagerRole = new iam.Role(this, 'StateManagerRole', {
      roleName: `${namePrefix}-StateManagerRole`,
      description: 'Role for Systems Manager State Manager operations',
      assumedBy: new iam.ServicePrincipal('ssm.amazonaws.com'),
    });

    // Create custom IAM policy for State Manager operations
    const stateManagerPolicy = new iam.Policy(this, 'StateManagerPolicy', {
      policyName: `${namePrefix}-StateManagerPolicy`,
      statements: [
        // Systems Manager permissions
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'ssm:CreateAssociation',
            'ssm:DescribeAssociation*',
            'ssm:GetAutomationExecution',
            'ssm:ListAssociations',
            'ssm:ListDocuments',
            'ssm:SendCommand',
            'ssm:StartAutomationExecution',
            'ssm:DescribeInstanceInformation',
            'ssm:DescribeDocumentParameters',
            'ssm:ListCommandInvocations',
            'ssm:StartAssociationsOnce',
            'ssm:ListComplianceItems',
            'ssm:ListComplianceSummaries',
          ],
          resources: ['*'],
        }),
        // EC2 permissions for instance management
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'ec2:DescribeInstances',
            'ec2:DescribeInstanceAttribute',
            'ec2:DescribeImages',
            'ec2:DescribeSnapshots',
            'ec2:DescribeVolumes',
          ],
          resources: ['*'],
        }),
        // CloudWatch permissions for monitoring
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'cloudwatch:PutMetricData',
            'logs:CreateLogGroup',
            'logs:CreateLogStream',
            'logs:PutLogEvents',
          ],
          resources: ['*'],
        }),
        // SNS permissions for notifications
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['sns:Publish'],
          resources: [driftAlertsTopic.topicArn],
        }),
      ],
    });

    // Attach custom policy to role
    this.stateManagerRole.attachInlinePolicy(stateManagerPolicy);

    // Attach AWS managed policy for SSM managed instance core functionality
    this.stateManagerRole.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore')
    );

    // Create custom SSM document for security configuration
    this.securityDocument = new ssm.CfnDocument(this, 'SecurityConfigDocument', {
      documentType: 'Command',
      documentFormat: 'JSON',
      name: `Custom-SecurityConfiguration-${namePrefix}`,
      content: {
        schemaVersion: '2.2',
        description: 'Configure security settings on Linux instances',
        parameters: {
          enableFirewall: {
            type: 'String',
            description: 'Enable firewall',
            default: 'true',
            allowedValues: ['true', 'false'],
          },
          disableRootLogin: {
            type: 'String',
            description: 'Disable root SSH login',
            default: 'true',
            allowedValues: ['true', 'false'],
          },
        },
        mainSteps: [
          {
            action: 'aws:runShellScript',
            name: 'configureFirewall',
            precondition: {
              StringEquals: ['platformType', 'Linux'],
            },
            inputs: {
              runCommand: [
                '#!/bin/bash',
                "if [ '{{ enableFirewall }}' == 'true' ]; then",
                '  if command -v ufw &> /dev/null; then',
                '    ufw --force enable',
                "    echo 'UFW firewall enabled'",
                '  elif command -v firewall-cmd &> /dev/null; then',
                '    systemctl enable firewalld',
                '    systemctl start firewalld',
                "    echo 'Firewalld enabled'",
                '  fi',
                'fi',
              ],
            },
          },
          {
            action: 'aws:runShellScript',
            name: 'configureSshSecurity',
            precondition: {
              StringEquals: ['platformType', 'Linux'],
            },
            inputs: {
              runCommand: [
                '#!/bin/bash',
                "if [ '{{ disableRootLogin }}' == 'true' ]; then",
                "  sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
                '  if systemctl is-active --quiet sshd; then',
                '    systemctl reload sshd',
                '  fi',
                "  echo 'Root SSH login disabled'",
                'fi',
              ],
            },
          },
        ],
      },
      tags: [
        {
          key: 'Purpose',
          value: 'StateManagerDemo',
        },
        {
          key: 'Environment',
          value: environmentTag,
        },
      ],
    });

    // Create State Manager association for SSM Agent updates
    const agentUpdateAssociation = new ssm.CfnAssociation(this, 'SSMAgentUpdateAssociation', {
      name: 'AWS-UpdateSSMAgent',
      associationName: `${namePrefix}-SSMAgent-Update`,
      scheduleExpression: agentUpdateSchedule,
      targets: [
        {
          key: 'tag:Environment',
          values: [environmentTag],
        },
      ],
      outputLocation: {
        s3Location: {
          outputS3Region: this.region,
          outputS3BucketName: `aws-ssm-${this.region}-${this.account}`,
        },
      },
    });

    // Create State Manager association for security configuration
    const securityConfigAssociation = new ssm.CfnAssociation(this, 'SecurityConfigAssociation', {
      name: this.securityDocument.ref,
      associationName: `${namePrefix}-Security-Config`,
      scheduleExpression: securityCheckSchedule,
      targets: [
        {
          key: 'tag:Environment',
          values: [environmentTag],
        },
      ],
      parameters: {
        enableFirewall: ['true'],
        disableRootLogin: ['true'],
      },
      complianceSeverity: 'CRITICAL',
      outputLocation: {
        s3Location: {
          outputS3Region: this.region,
          outputS3BucketName: `aws-ssm-${this.region}-${this.account}`,
        },
      },
    });

    // Ensure security association depends on the document
    securityConfigAssociation.addDependency(this.securityDocument);

    // Create CloudWatch alarm for association failures
    const associationFailureAlarm = new cloudwatch.Alarm(this, 'AssociationFailureAlarm', {
      alarmName: `SSM-Association-Failures-${namePrefix}`,
      alarmDescription: 'Monitor SSM association failures',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/SSM',
        metricName: 'AssociationExecutionsFailed',
        dimensionsMap: {
          AssociationName: `${namePrefix}-Security-Config`,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS action to association failure alarm
    associationFailureAlarm.addAlarmAction(new cw_actions.SnsAction(driftAlertsTopic));

    // Create CloudWatch alarm for compliance violations
    const complianceViolationAlarm = new cloudwatch.Alarm(this, 'ComplianceViolationAlarm', {
      alarmName: `SSM-Compliance-Violations-${namePrefix}`,
      alarmDescription: 'Monitor compliance violations',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/SSM',
        metricName: 'ComplianceByConfigRule',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS action to compliance violation alarm
    complianceViolationAlarm.addAlarmAction(new cw_actions.SnsAction(driftAlertsTopic));

    // Create automation document for remediation
    const remediationDocument = new ssm.CfnDocument(this, 'RemediationDocument', {
      documentType: 'Automation',
      documentFormat: 'JSON',
      name: `AutoRemediation-${namePrefix}`,
      content: {
        schemaVersion: '0.3',
        description: 'Automated remediation for configuration drift',
        assumeRole: '{{ AutomationAssumeRole }}',
        parameters: {
          AutomationAssumeRole: {
            type: 'String',
            description: 'The ARN of the role for automation',
          },
          InstanceId: {
            type: 'String',
            description: 'The ID of the non-compliant instance',
          },
          AssociationId: {
            type: 'String',
            description: 'The ID of the failed association',
          },
        },
        mainSteps: [
          {
            name: 'RerunAssociation',
            action: 'aws:executeAwsApi',
            inputs: {
              Service: 'ssm',
              Api: 'StartAssociationsOnce',
              AssociationIds: ['{{ AssociationId }}'],
            },
          },
          {
            name: 'WaitForCompletion',
            action: 'aws:waitForAwsResourceProperty',
            inputs: {
              Service: 'ssm',
              Api: 'DescribeAssociationExecutions',
              AssociationId: '{{ AssociationId }}',
              PropertySelector: '$.AssociationExecutions[0].Status',
              DesiredValues: ['Success'],
            },
            timeoutSeconds: 300,
          },
          {
            name: 'SendNotification',
            action: 'aws:executeAwsApi',
            inputs: {
              Service: 'sns',
              Api: 'Publish',
              TopicArn: driftAlertsTopic.topicArn,
              Message: 'Configuration drift remediation completed for instance {{ InstanceId }}',
            },
          },
        ],
      },
      tags: [
        {
          key: 'Purpose',
          value: 'StateManagerDemo',
        },
        {
          key: 'Environment',
          value: environmentTag,
        },
      ],
    });

    // Create compliance reporting document
    const complianceReportDocument = new ssm.CfnDocument(this, 'ComplianceReportDocument', {
      documentType: 'Automation',
      documentFormat: 'JSON',
      name: `ComplianceReport-${namePrefix}`,
      content: {
        schemaVersion: '0.3',
        description: 'Generate compliance report',
        mainSteps: [
          {
            name: 'GenerateReport',
            action: 'aws:executeAwsApi',
            inputs: {
              Service: 'ssm',
              Api: 'ListComplianceItems',
              ResourceTypes: ['ManagedInstance'],
              Filters: [
                {
                  Key: 'ComplianceType',
                  Values: ['Association'],
                },
              ],
            },
          },
        ],
      },
      tags: [
        {
          key: 'Purpose',
          value: 'StateManagerDemo',
        },
        {
          key: 'Environment',
          value: environmentTag,
        },
      ],
    });

    // Create CloudWatch dashboard for monitoring
    this.complianceDashboard = new cloudwatch.Dashboard(this, 'ComplianceDashboard', {
      dashboardName: `SSM-StateManager-${namePrefix}`,
      widgets: [
        [
          // Association execution status widget
          new cloudwatch.GraphWidget({
            title: 'Association Execution Status',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/SSM',
                metricName: 'AssociationExecutionsSucceeded',
                dimensionsMap: {
                  AssociationName: `${namePrefix}-Security-Config`,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/SSM',
                metricName: 'AssociationExecutionsFailed',
                dimensionsMap: {
                  AssociationName: `${namePrefix}-Security-Config`,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
          // Compliance status widget
          new cloudwatch.GraphWidget({
            title: 'Compliance Status',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/SSM',
                metricName: 'ComplianceByConfigRule',
                dimensionsMap: {
                  RuleName: `${namePrefix}-Security-Config`,
                  ComplianceType: 'Association',
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // CloudFormation outputs for important resources
    new cdk.CfnOutput(this, 'StateManagerRoleArn', {
      value: this.stateManagerRole.roleArn,
      description: 'ARN of the IAM role for State Manager operations',
      exportName: `${namePrefix}-StateManagerRoleArn`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: driftAlertsTopic.topicArn,
      description: 'ARN of the SNS topic for configuration drift alerts',
      exportName: `${namePrefix}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'SecurityDocumentName', {
      value: this.securityDocument.ref,
      description: 'Name of the custom security configuration document',
      exportName: `${namePrefix}-SecurityDocumentName`,
    });

    new cdk.CfnOutput(this, 'SecurityAssociationId', {
      value: securityConfigAssociation.attrAssociationId,
      description: 'ID of the security configuration association',
      exportName: `${namePrefix}-SecurityAssociationId`,
    });

    new cdk.CfnOutput(this, 'AgentUpdateAssociationId', {
      value: agentUpdateAssociation.attrAssociationId,
      description: 'ID of the SSM Agent update association',
      exportName: `${namePrefix}-AgentUpdateAssociationId`,
    });

    new cdk.CfnOutput(this, 'RemediationDocumentName', {
      value: remediationDocument.ref,
      description: 'Name of the automated remediation document',
      exportName: `${namePrefix}-RemediationDocumentName`,
    });

    new cdk.CfnOutput(this, 'ComplianceReportDocumentName', {
      value: complianceReportDocument.ref,
      description: 'Name of the compliance reporting document',
      exportName: `${namePrefix}-ComplianceReportDocumentName`,
    });

    new cdk.CfnOutput(this, 'CloudWatchLogGroupName', {
      value: this.cloudWatchLogGroup.logGroupName,
      description: 'Name of the CloudWatch log group for State Manager',
      exportName: `${namePrefix}-CloudWatchLogGroupName`,
    });

    new cdk.CfnOutput(this, 'DashboardName', {
      value: this.complianceDashboard.dashboardName,
      description: 'Name of the CloudWatch dashboard for compliance monitoring',
      exportName: `${namePrefix}-DashboardName`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.complianceDashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for compliance monitoring',
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or use defaults
const notificationEmail = app.node.tryGetContext('notificationEmail') || 'admin@example.com';
const environmentTag = app.node.tryGetContext('environmentTag') || 'Demo';
const namePrefix = app.node.tryGetContext('namePrefix') || 'SSMStateManager';

// Create the State Manager stack
const stateManagerStack = new SSMStateManagerStack(app, 'SSMStateManagerStack', {
  description: 'AWS Systems Manager State Manager configuration management solution',
  notificationEmail,
  environmentTag,
  namePrefix,
  logRetentionDays: logs.RetentionDays.ONE_MONTH,
  securityCheckSchedule: 'rate(1 day)',
  agentUpdateSchedule: 'rate(7 days)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Purpose: 'StateManagerDemo',
    Environment: environmentTag,
    ManagedBy: 'CDK',
  },
});

// Add stack-level tags
cdk.Tags.of(stateManagerStack).add('Purpose', 'StateManagerDemo');
cdk.Tags.of(stateManagerStack).add('Environment', environmentTag);
cdk.Tags.of(stateManagerStack).add('ManagedBy', 'CDK');

app.synth();