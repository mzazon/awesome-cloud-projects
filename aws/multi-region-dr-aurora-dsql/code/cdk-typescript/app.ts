#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as dsql from 'aws-cdk-lib/aws-dsql';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cw_actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as path from 'path';

export interface AuroraDsqlDrStackProps extends cdk.StackProps {
  readonly primaryRegion: string;
  readonly secondaryRegion: string;
  readonly witnessRegion: string;
  readonly alertEmail: string;
  readonly resourcePrefix?: string;
}

export class AuroraDsqlDrStack extends cdk.Stack {
  public readonly dsqlCluster: dsql.CfnCluster;
  public readonly monitoringFunction: lambda.Function;
  public readonly alertTopic: sns.Topic;
  public readonly healthCheckRule: events.Rule;

  constructor(scope: Construct, id: string, props: AuroraDsqlDrStackProps) {
    super(scope, id, props);

    const resourcePrefix = props.resourcePrefix || 'aurora-dsql-dr';
    const isPrimaryRegion = this.region === props.primaryRegion;
    const regionSuffix = isPrimaryRegion ? 'primary' : 'secondary';

    // Create Aurora DSQL Cluster
    this.dsqlCluster = new dsql.CfnCluster(this, 'DsqlCluster', {
      clusterIdentifier: `${resourcePrefix}-${regionSuffix}`,
      multiRegionProperties: {
        witnessRegion: props.witnessRegion,
        // Clusters array will be updated after both stacks are deployed
        clusters: []
      },
      tags: [
        { key: 'Project', value: 'DisasterRecovery' },
        { key: 'Environment', value: 'Production' },
        { key: 'CostCenter', value: 'Infrastructure' },
        { key: 'Region', value: regionSuffix }
      ]
    });

    // Create SNS Topic for alerts
    this.alertTopic = new sns.Topic(this, 'AlertTopic', {
      topicName: `${resourcePrefix}-alerts-${regionSuffix}`,
      displayName: `DR Alerts ${regionSuffix}`,
      masterKey: cdk.aws_kms.Alias.fromAliasName(this, 'SnsKmsKey', 'alias/aws/sns')
    });

    // Add email subscription to SNS topic
    this.alertTopic.addSubscription(
      new subscriptions.EmailSubscription(props.alertEmail)
    );

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'LambdaRole', {
      roleName: `${resourcePrefix}-lambda-role-${regionSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        DsqlAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dsql:GetCluster',
                'dsql:ListClusters'
              ],
              resources: ['*']
            })
          ]
        }),
        SnsAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sns:Publish'
              ],
              resources: [this.alertTopic.topicArn]
            })
          ]
        }),
        CloudWatchAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Create Lambda function for health monitoring
    this.monitoringFunction = new lambda.Function(this, 'MonitoringFunction', {
      functionName: `${resourcePrefix}-monitor-${regionSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromInline(this.getLambdaCode()),
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      role: lambdaRole,
      environment: {
        CLUSTER_ID: this.dsqlCluster.clusterIdentifier!,
        SNS_TOPIC_ARN: this.alertTopic.topicArn,
        REGION: this.region
      },
      reservedConcurrentExecutions: 10,
      description: `Aurora DSQL health monitoring for ${regionSuffix} region`
    });

    // Create EventBridge rule for scheduled monitoring
    this.healthCheckRule = new events.Rule(this, 'HealthCheckRule', {
      ruleName: `${resourcePrefix}-health-monitor-${regionSuffix}`,
      description: `Aurora DSQL health monitoring for ${regionSuffix} region`,
      schedule: events.Schedule.rate(cdk.Duration.minutes(2)),
      enabled: true
    });

    // Add Lambda function as target for EventBridge rule
    this.healthCheckRule.addTarget(
      new targets.LambdaFunction(this.monitoringFunction, {
        retryAttempts: 3,
        maxEventAge: cdk.Duration.hours(1)
      })
    );

    // Create CloudWatch alarms
    this.createCloudWatchAlarms(resourcePrefix, regionSuffix);

    // Create CloudWatch dashboard (only in primary region)
    if (isPrimaryRegion) {
      this.createCloudWatchDashboard(resourcePrefix, props);
    }

    // Output important values
    new cdk.CfnOutput(this, 'DsqlClusterIdentifier', {
      value: this.dsqlCluster.clusterIdentifier!,
      description: 'Aurora DSQL Cluster Identifier',
      exportName: `${this.stackName}-DsqlClusterIdentifier`
    });

    new cdk.CfnOutput(this, 'DsqlClusterArn', {
      value: this.dsqlCluster.attrArn,
      description: 'Aurora DSQL Cluster ARN',
      exportName: `${this.stackName}-DsqlClusterArn`
    });

    new cdk.CfnOutput(this, 'MonitoringFunctionArn', {
      value: this.monitoringFunction.functionArn,
      description: 'Lambda monitoring function ARN'
    });

    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'SNS alert topic ARN'
    });
  }

  private createCloudWatchAlarms(resourcePrefix: string, regionSuffix: string): void {
    // Lambda function error alarm
    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      alarmName: `${resourcePrefix}-lambda-errors-${regionSuffix}`,
      alarmDescription: `Alert when Lambda function errors occur in ${regionSuffix} region`,
      metric: this.monitoringFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.SUM
      }),
      threshold: 1,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
    });

    lambdaErrorAlarm.addAlarmAction(new cw_actions.SnsAction(this.alertTopic));

    // Aurora DSQL cluster health alarm
    const clusterHealthMetric = new cloudwatch.Metric({
      namespace: 'Aurora/DSQL/DisasterRecovery',
      metricName: 'ClusterHealth',
      dimensionsMap: {
        ClusterID: this.dsqlCluster.clusterIdentifier!,
        Region: this.region
      },
      period: cdk.Duration.minutes(5),
      statistic: cloudwatch.Statistic.AVERAGE
    });

    const clusterHealthAlarm = new cloudwatch.Alarm(this, 'ClusterHealthAlarm', {
      alarmName: `${resourcePrefix}-cluster-health-${regionSuffix}`,
      alarmDescription: `Alert when Aurora DSQL cluster health degrades in ${regionSuffix} region`,
      metric: clusterHealthMetric,
      threshold: 0.5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD
    });

    clusterHealthAlarm.addAlarmAction(new cw_actions.SnsAction(this.alertTopic));

    // EventBridge rule failure alarm
    const eventBridgeFailureAlarm = new cloudwatch.Alarm(this, 'EventBridgeFailureAlarm', {
      alarmName: `${resourcePrefix}-eventbridge-failures-${regionSuffix}`,
      alarmDescription: `Alert when EventBridge rules fail to execute in ${regionSuffix} region`,
      metric: this.healthCheckRule.metricFailedInvocations({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.SUM
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
    });

    eventBridgeFailureAlarm.addAlarmAction(new cw_actions.SnsAction(this.alertTopic));
  }

  private createCloudWatchDashboard(resourcePrefix: string, props: AuroraDsqlDrStackProps): void {
    const dashboard = new cloudwatch.Dashboard(this, 'DrDashboard', {
      dashboardName: `${resourcePrefix}-dashboard`,
      defaultInterval: cdk.Duration.minutes(5)
    });

    // Lambda invocations widget
    const lambdaInvocationsWidget = new cloudwatch.GraphWidget({
      title: 'Lambda Function Invocations',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/Lambda',
          metricName: 'Invocations',
          dimensionsMap: {
            FunctionName: `${resourcePrefix}-monitor-primary`
          },
          period: cdk.Duration.minutes(5),
          statistic: cloudwatch.Statistic.SUM,
          label: 'Primary Region'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/Lambda',
          metricName: 'Invocations',
          dimensionsMap: {
            FunctionName: `${resourcePrefix}-monitor-secondary`
          },
          period: cdk.Duration.minutes(5),
          statistic: cloudwatch.Statistic.SUM,
          label: 'Secondary Region',
          region: props.secondaryRegion
        })
      ],
      width: 12,
      height: 6
    });

    // Lambda errors and duration widget
    const lambdaErrorsWidget = new cloudwatch.GraphWidget({
      title: 'Lambda Function Errors and Duration',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/Lambda',
          metricName: 'Errors',
          dimensionsMap: {
            FunctionName: `${resourcePrefix}-monitor-primary`
          },
          period: cdk.Duration.minutes(5),
          statistic: cloudwatch.Statistic.AVERAGE,
          label: 'Primary Errors'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/Lambda',
          metricName: 'Errors',
          dimensionsMap: {
            FunctionName: `${resourcePrefix}-monitor-secondary`
          },
          period: cdk.Duration.minutes(5),
          statistic: cloudwatch.Statistic.AVERAGE,
          label: 'Secondary Errors',
          region: props.secondaryRegion
        })
      ],
      right: [
        new cloudwatch.Metric({
          namespace: 'AWS/Lambda',
          metricName: 'Duration',
          dimensionsMap: {
            FunctionName: `${resourcePrefix}-monitor-primary`
          },
          period: cdk.Duration.minutes(5),
          statistic: cloudwatch.Statistic.AVERAGE,
          label: 'Primary Duration'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/Lambda',
          metricName: 'Duration',
          dimensionsMap: {
            FunctionName: `${resourcePrefix}-monitor-secondary`
          },
          period: cdk.Duration.minutes(5),
          statistic: cloudwatch.Statistic.AVERAGE,
          label: 'Secondary Duration',
          region: props.secondaryRegion
        })
      ],
      width: 12,
      height: 6
    });

    // EventBridge widget
    const eventBridgeWidget = new cloudwatch.GraphWidget({
      title: 'EventBridge Rule Executions and Success Rate',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/Events',
          metricName: 'MatchedEvents',
          dimensionsMap: {
            RuleName: `${resourcePrefix}-health-monitor-primary`
          },
          period: cdk.Duration.minutes(5),
          statistic: cloudwatch.Statistic.SUM,
          label: 'Primary Matched Events'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/Events',
          metricName: 'MatchedEvents',
          dimensionsMap: {
            RuleName: `${resourcePrefix}-health-monitor-secondary`
          },
          period: cdk.Duration.minutes(5),
          statistic: cloudwatch.Statistic.SUM,
          label: 'Secondary Matched Events',
          region: props.secondaryRegion
        })
      ],
      right: [
        new cloudwatch.Metric({
          namespace: 'AWS/Events',
          metricName: 'SuccessfulInvocations',
          dimensionsMap: {
            RuleName: `${resourcePrefix}-health-monitor-primary`
          },
          period: cdk.Duration.minutes(5),
          statistic: cloudwatch.Statistic.SUM,
          label: 'Primary Successful'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/Events',
          metricName: 'SuccessfulInvocations',
          dimensionsMap: {
            RuleName: `${resourcePrefix}-health-monitor-secondary`
          },
          period: cdk.Duration.minutes(5),
          statistic: cloudwatch.Statistic.SUM,
          label: 'Secondary Successful',
          region: props.secondaryRegion
        })
      ],
      width: 24,
      height: 6
    });

    // Aurora DSQL health widget
    const dsqlHealthWidget = new cloudwatch.GraphWidget({
      title: 'Aurora DSQL Cluster Health Status',
      left: [
        new cloudwatch.Metric({
          namespace: 'Aurora/DSQL/DisasterRecovery',
          metricName: 'ClusterHealth',
          dimensionsMap: {
            ClusterID: `${resourcePrefix}-primary`,
            Region: props.primaryRegion
          },
          period: cdk.Duration.minutes(5),
          statistic: cloudwatch.Statistic.AVERAGE,
          label: 'Primary Cluster Health'
        }),
        new cloudwatch.Metric({
          namespace: 'Aurora/DSQL/DisasterRecovery',
          metricName: 'ClusterHealth',
          dimensionsMap: {
            ClusterID: `${resourcePrefix}-secondary`,
            Region: props.secondaryRegion
          },
          period: cdk.Duration.minutes(5),
          statistic: cloudwatch.Statistic.AVERAGE,
          label: 'Secondary Cluster Health',
          region: props.secondaryRegion
        })
      ],
      leftYAxis: {
        min: 0,
        max: 1
      },
      width: 24,
      height: 6
    });

    // Add widgets to dashboard
    dashboard.addWidgets(
      lambdaInvocationsWidget,
      lambdaErrorsWidget,
      eventBridgeWidget,
      dsqlHealthWidget
    );
  }

  private getLambdaCode(): string {
    return `
import json
import boto3
import os
import time
from datetime import datetime
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    """
    Monitor Aurora DSQL cluster health and send alerts
    """
    dsql_client = boto3.client('dsql')
    sns_client = boto3.client('sns')
    cloudwatch_client = boto3.client('cloudwatch')
    
    cluster_id = os.environ['CLUSTER_ID']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    region = os.environ['REGION']
    
    try:
        # Check cluster status with retry logic
        max_retries = 3
        for attempt in range(max_retries):
            try:
                response = dsql_client.get_cluster(identifier=cluster_id)
                break
            except ClientError as e:
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)  # Exponential backoff
                    continue
                raise e
        
        cluster_status = response['status']
        cluster_arn = response['arn']
        
        # Create comprehensive health report
        health_report = {
            'timestamp': datetime.now().isoformat(),
            'region': region,
            'cluster_id': cluster_id,
            'cluster_arn': cluster_arn,
            'status': cluster_status,
            'healthy': cluster_status == 'ACTIVE',
            'function_name': context.function_name,
            'request_id': context.aws_request_id
        }
        
        # Publish custom CloudWatch metric
        cloudwatch_client.put_metric_data(
            Namespace='Aurora/DSQL/DisasterRecovery',
            MetricData=[
                {
                    'MetricName': 'ClusterHealth',
                    'Value': 1.0 if cluster_status == 'ACTIVE' else 0.0,
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'ClusterID',
                            'Value': cluster_id
                        },
                        {
                            'Name': 'Region',
                            'Value': region
                        }
                    ]
                }
            ]
        )
        
        # Send alert if cluster is not healthy
        if cluster_status != 'ACTIVE':
            alert_message = f"""
ALERT: Aurora DSQL Cluster Health Issue

Region: {region}
Cluster ID: {cluster_id}
Cluster ARN: {cluster_arn}
Status: {cluster_status}
Timestamp: {health_report['timestamp']}
Function: {context.function_name}
Request ID: {context.aws_request_id}

Immediate investigation required.
Check Aurora DSQL console for detailed status information.
            """
            
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Subject=f'Aurora DSQL Alert - {region}',
                Message=alert_message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps(health_report),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        error_message = f"""
ERROR: Aurora DSQL Health Check Failed

Region: {region}
Cluster ID: {cluster_id}
Error: {str(e)}
Error Type: {type(e).__name__}
Timestamp: {datetime.now().isoformat()}
Function: {context.function_name}
Request ID: {context.aws_request_id}

This error indicates a potential issue with the monitoring infrastructure.
Verify Lambda function permissions and Aurora DSQL cluster accessibility.
        """
        
        try:
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Subject=f'Aurora DSQL Health Check Error - {region}',
                Message=error_message
            )
        except Exception as sns_error:
            print(f"Failed to send SNS alert: {sns_error}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'error_type': type(e).__name__,
                'timestamp': datetime.now().isoformat()
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
`.strip();
  }
}

// CDK App
const app = new cdk.App();

// Get configuration from context or environment variables
const primaryRegion = app.node.tryGetContext('primaryRegion') || process.env.PRIMARY_REGION || 'us-east-1';
const secondaryRegion = app.node.tryGetContext('secondaryRegion') || process.env.SECONDARY_REGION || 'us-west-2';
const witnessRegion = app.node.tryGetContext('witnessRegion') || process.env.WITNESS_REGION || 'us-west-1';
const alertEmail = app.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL || 'ops-team@company.com';
const resourcePrefix = app.node.tryGetContext('resourcePrefix') || process.env.RESOURCE_PREFIX || 'aurora-dsql-dr';

// Deploy primary region stack
const primaryStack = new AuroraDsqlDrStack(app, 'AuroraDsqlDrPrimary', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: primaryRegion
  },
  primaryRegion,
  secondaryRegion,
  witnessRegion,
  alertEmail,
  resourcePrefix,
  description: 'Aurora DSQL Disaster Recovery - Primary Region'
});

// Deploy secondary region stack
const secondaryStack = new AuroraDsqlDrStack(app, 'AuroraDsqlDrSecondary', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: secondaryRegion
  },
  primaryRegion,
  secondaryRegion,
  witnessRegion,
  alertEmail,
  resourcePrefix,
  description: 'Aurora DSQL Disaster Recovery - Secondary Region'
});

// Add tags to all resources
cdk.Tags.of(primaryStack).add('Project', 'AuroraDsqlDisasterRecovery');
cdk.Tags.of(primaryStack).add('Environment', 'Production');
cdk.Tags.of(primaryStack).add('ManagedBy', 'CDK');
cdk.Tags.of(primaryStack).add('Region', 'Primary');

cdk.Tags.of(secondaryStack).add('Project', 'AuroraDsqlDisasterRecovery');
cdk.Tags.of(secondaryStack).add('Environment', 'Production');
cdk.Tags.of(secondaryStack).add('ManagedBy', 'CDK');
cdk.Tags.of(secondaryStack).add('Region', 'Secondary');

app.synth();