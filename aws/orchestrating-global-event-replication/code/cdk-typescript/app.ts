#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as path from 'path';

/**
 * Properties for the MultiRegionEventReplicationStack
 */
interface MultiRegionEventReplicationStackProps extends cdk.StackProps {
  readonly isPrimaryRegion: boolean;
  readonly otherRegions: string[];
  readonly eventBusName: string;
  readonly lambdaFunctionName: string;
  readonly globalEndpointName?: string;
  readonly snsTopicArn?: string;
}

/**
 * Stack for multi-region EventBridge event replication
 * Implements disaster recovery and high availability for event-driven architectures
 */
class MultiRegionEventReplicationStack extends cdk.Stack {
  public readonly eventBus: events.EventBus;
  public readonly processorFunction: lambda.Function;
  public readonly globalEndpoint?: events.CfnEndpoint;
  public readonly healthCheck?: route53.CfnHealthCheck;

  constructor(scope: Construct, id: string, props: MultiRegionEventReplicationStackProps) {
    super(scope, id, props);

    const { isPrimaryRegion, otherRegions, eventBusName, lambdaFunctionName, globalEndpointName, snsTopicArn } = props;

    // Create custom event bus with KMS encryption
    this.eventBus = new events.EventBus(this, 'GlobalEventBus', {
      eventBusName: eventBusName,
      kmsKey: this.createKmsKey(),
      description: 'Custom event bus for multi-region event replication',
    });

    // Add tags to the event bus
    cdk.Tags.of(this.eventBus).add('Environment', 'Production');
    cdk.Tags.of(this.eventBus).add('Purpose', 'MultiRegionReplication');

    // Create IAM role for Lambda function
    const lambdaRole = this.createLambdaExecutionRole();

    // Create Lambda function for event processing
    this.processorFunction = new lambda.Function(this, 'EventProcessorFunction', {
      functionName: lambdaFunctionName,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromInline(this.getLambdaCode()),
      timeout: cdk.Duration.seconds(30),
      role: lambdaRole,
      environment: {
        REGION: this.region,
        EVENT_BUS_NAME: eventBusName,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      description: 'Processes events from EventBridge with region-aware logic',
    });

    // Add tags to Lambda function
    cdk.Tags.of(this.processorFunction).add('Purpose', 'EventProcessing');
    cdk.Tags.of(this.processorFunction).add('Environment', 'Production');

    // Create EventBridge rules and targets
    this.createEventRules(isPrimaryRegion, otherRegions);

    // Create CloudWatch monitoring
    this.createCloudWatchMonitoring(snsTopicArn);

    // Create global endpoint and health check for primary region
    if (isPrimaryRegion && globalEndpointName) {
      this.createGlobalEndpoint(globalEndpointName, otherRegions);
    }

    // Create cross-region IAM role for EventBridge
    if (isPrimaryRegion) {
      this.createCrossRegionRole(otherRegions);
    }

    // Set up event bus permissions for cross-region access
    this.configureCrossRegionPermissions();

    // Output important resource ARNs
    this.createOutputs();
  }

  /**
   * Creates a KMS key for EventBridge encryption
   */
  private createKmsKey(): cdk.aws_kms.Key {
    return new cdk.aws_kms.Key(this, 'EventBridgeKmsKey', {
      description: 'KMS key for EventBridge encryption',
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
  }

  /**
   * Creates IAM role for Lambda execution
   */
  private createLambdaExecutionRole(): iam.Role {
    const role = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for EventBridge processor Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add additional permissions for EventBridge and CloudWatch
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'events:PutEvents',
        'events:DescribeRule',
        'events:ListTargetsByRule',
        'cloudwatch:PutMetricData',
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
      ],
      resources: ['*'],
    }));

    return role;
  }

  /**
   * Creates EventBridge rules for event processing and cross-region replication
   */
  private createEventRules(isPrimaryRegion: boolean, otherRegions: string[]): void {
    if (isPrimaryRegion) {
      // Primary region: Cross-region replication rule
      const crossRegionRule = new events.Rule(this, 'CrossRegionReplicationRule', {
        ruleName: 'cross-region-replication-rule',
        eventBus: this.eventBus,
        description: 'Replicates high priority events across regions',
        eventPattern: {
          source: ['finance.transactions', 'user.management'],
          detailType: ['Transaction Created', 'User Action'],
          detail: {
            priority: ['high', 'critical'],
          },
        },
        enabled: true,
      });

      // Add cross-region targets
      const crossRegionRole = this.createCrossRegionEventBridgeRole(otherRegions);
      
      // Add targets for other regions
      otherRegions.forEach((region, index) => {
        crossRegionRule.addTarget(new targets.EventBridgeDestination(
          events.EventBus.fromEventBusArn(this, `TargetEventBus${index}`, 
            `arn:aws:events:${region}:${this.account}:event-bus/${this.eventBus.eventBusName}`
          ),
          {
            role: crossRegionRole,
          }
        ));
      });

      // Add Lambda target for local processing
      crossRegionRule.addTarget(new targets.LambdaFunction(this.processorFunction));

      // Create additional specialized rules for different event types
      this.createSpecializedRules();
    } else {
      // Secondary/Tertiary regions: Local processing rule
      const localProcessingRule = new events.Rule(this, 'LocalProcessingRule', {
        ruleName: 'local-processing-rule',
        eventBus: this.eventBus,
        description: 'Processes events locally in secondary/tertiary regions',
        eventPattern: {
          source: ['finance.transactions', 'user.management'],
          detailType: ['Transaction Created', 'User Action'],
        },
        enabled: true,
      });

      // Add Lambda target for local processing
      localProcessingRule.addTarget(new targets.LambdaFunction(this.processorFunction));
    }
  }

  /**
   * Creates specialized EventBridge rules for different event types
   */
  private createSpecializedRules(): void {
    // Financial events rule
    const financialRule = new events.Rule(this, 'FinancialEventsRule', {
      ruleName: 'financial-events-rule',
      eventBus: this.eventBus,
      description: 'Handles financial transaction events',
      eventPattern: {
        source: ['finance.transactions', 'finance.payments'],
        detailType: ['Transaction Created', 'Payment Processed', 'Fraud Detected'],
        detail: {
          priority: ['high', 'critical'],
          amount: [{ numeric: ['>=', 1000] }],
        },
      },
      enabled: true,
    });

    financialRule.addTarget(new targets.LambdaFunction(this.processorFunction));

    // User events rule
    const userRule = new events.Rule(this, 'UserEventsRule', {
      ruleName: 'user-events-rule',
      eventBus: this.eventBus,
      description: 'Handles user management events',
      eventPattern: {
        source: ['user.management', 'user.authentication'],
        detailType: ['User Login', 'User Logout', 'Password Reset'],
        detail: {
          risk_level: ['medium', 'high'],
          region: ['us-east-1', 'us-west-2', 'eu-west-1'],
        },
      },
      enabled: true,
    });

    userRule.addTarget(new targets.LambdaFunction(this.processorFunction));

    // System events rule
    const systemRule = new events.Rule(this, 'SystemEventsRule', {
      ruleName: 'system-events-rule',
      eventBus: this.eventBus,
      description: 'Handles system monitoring events',
      eventPattern: {
        source: ['system.monitoring', 'system.alerts'],
        detailType: ['System Error', 'Performance Alert', 'Security Incident'],
        detail: {
          severity: ['warning', 'error', 'critical'],
        },
      },
      enabled: true,
    });

    systemRule.addTarget(new targets.LambdaFunction(this.processorFunction));
  }

  /**
   * Creates IAM role for cross-region EventBridge access
   */
  private createCrossRegionEventBridgeRole(otherRegions: string[]): iam.Role {
    const role = new iam.Role(this, 'CrossRegionEventBridgeRole', {
      assumedBy: new iam.ServicePrincipal('events.amazonaws.com'),
      description: 'Role for EventBridge cross-region event delivery',
    });

    // Add permissions to put events to other regions
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['events:PutEvents'],
      resources: otherRegions.map(region => 
        `arn:aws:events:${region}:${this.account}:event-bus/${this.eventBus.eventBusName}`
      ),
    }));

    return role;
  }

  /**
   * Creates cross-region role for EventBridge service
   */
  private createCrossRegionRole(otherRegions: string[]): void {
    const crossRegionRole = new iam.Role(this, 'EventBridgeCrossRegionRole', {
      roleName: 'eventbridge-cross-region-role',
      assumedBy: new iam.ServicePrincipal('events.amazonaws.com'),
      description: 'Role for EventBridge cross-region event delivery',
    });

    crossRegionRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['events:PutEvents'],
      resources: ['arn:aws:events:*:*:event-bus/*'],
    }));
  }

  /**
   * Configures cross-region permissions for event bus
   */
  private configureCrossRegionPermissions(): void {
    const eventBusPolicy = new events.CfnEventBusPolicy(this, 'EventBusCrossRegionPolicy', {
      eventBusName: this.eventBus.eventBusName,
      statementId: 'AllowCrossRegionAccess',
      statement: {
        Sid: 'AllowCrossRegionAccess',
        Effect: 'Allow',
        Principal: {
          AWS: `arn:aws:iam::${this.account}:root`,
        },
        Action: 'events:PutEvents',
        Resource: `arn:aws:events:*:${this.account}:event-bus/${this.eventBus.eventBusName}`,
      },
    });

    // Add service principal permissions
    new events.CfnEventBusPolicy(this, 'EventBusServicePolicy', {
      eventBusName: this.eventBus.eventBusName,
      statementId: 'AllowEventBridgeService',
      statement: {
        Sid: 'AllowEventBridgeService',
        Effect: 'Allow',
        Principal: {
          Service: 'events.amazonaws.com',
        },
        Action: 'events:PutEvents',
        Resource: `arn:aws:events:*:${this.account}:event-bus/${this.eventBus.eventBusName}`,
      },
    });
  }

  /**
   * Creates global endpoint with Route 53 health check
   */
  private createGlobalEndpoint(globalEndpointName: string, otherRegions: string[]): void {
    // Create Route 53 health check
    this.healthCheck = new route53.CfnHealthCheck(this, 'EventBridgeHealthCheck', {
      type: 'HTTPS',
      resourcePath: '/',
      fullyQualifiedDomainName: `events.${this.region}.amazonaws.com`,
      port: 443,
      requestInterval: 30,
      failureThreshold: 3,
      tags: [
        {
          key: 'Name',
          value: `eventbridge-health-check-${globalEndpointName}`,
        },
      ],
    });

    // Create global endpoint
    this.globalEndpoint = new events.CfnEndpoint(this, 'GlobalEndpoint', {
      name: globalEndpointName,
      description: 'Global endpoint for multi-region EventBridge',
      routingConfig: {
        failoverConfig: {
          primary: {
            healthCheck: this.healthCheck.attrHealthCheckId,
          },
          secondary: {
            route: otherRegions[0], // Use first other region as secondary
          },
        },
      },
      replicationConfig: {
        state: 'ENABLED',
      },
      eventBuses: [
        {
          eventBusArn: this.eventBus.eventBusArn,
        },
        {
          eventBusArn: `arn:aws:events:${otherRegions[0]}:${this.account}:event-bus/${this.eventBus.eventBusName}`,
        },
      ],
    });
  }

  /**
   * Creates CloudWatch monitoring and alarms
   */
  private createCloudWatchMonitoring(snsTopicArn?: string): void {
    // Create CloudWatch alarm for failed EventBridge invocations
    const failedInvocationsAlarm = new cloudwatch.Alarm(this, 'FailedInvocationsAlarm', {
      alarmName: `EventBridge-FailedInvocations-${this.stackName}`,
      alarmDescription: 'Alert when EventBridge rule fails',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Events',
        metricName: 'FailedInvocations',
        dimensionsMap: {
          RuleName: 'cross-region-replication-rule',
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    // Create CloudWatch alarm for Lambda errors
    const lambdaErrorsAlarm = new cloudwatch.Alarm(this, 'LambdaErrorsAlarm', {
      alarmName: `Lambda-Errors-${this.stackName}`,
      alarmDescription: 'Alert when Lambda function errors occur',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Lambda',
        metricName: 'Errors',
        dimensionsMap: {
          FunctionName: this.processorFunction.functionName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 3,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    // Add SNS topic actions if provided
    if (snsTopicArn) {
      const snsTopic = sns.Topic.fromTopicArn(this, 'AlertsTopic', snsTopicArn);
      failedInvocationsAlarm.addAlarmAction(new cdk.aws_cloudwatch_actions.SnsAction(snsTopic));
      lambdaErrorsAlarm.addAlarmAction(new cdk.aws_cloudwatch_actions.SnsAction(snsTopic));
    }

    // Create CloudWatch dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'EventBridgeDashboard', {
      dashboardName: `EventBridge-MultiRegion-${this.stackName}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'EventBridge Rule Performance',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Events',
                metricName: 'SuccessfulInvocations',
                dimensionsMap: {
                  RuleName: 'cross-region-replication-rule',
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/Events',
                metricName: 'FailedInvocations',
                dimensionsMap: {
                  RuleName: 'cross-region-replication-rule',
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Performance',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Lambda',
                metricName: 'Invocations',
                dimensionsMap: {
                  FunctionName: this.processorFunction.functionName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/Lambda',
                metricName: 'Errors',
                dimensionsMap: {
                  FunctionName: this.processorFunction.functionName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/Lambda',
                metricName: 'Duration',
                dimensionsMap: {
                  FunctionName: this.processorFunction.functionName,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
          }),
        ],
      ],
    });
  }

  /**
   * Creates CloudFormation outputs for important resources
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'EventBusArn', {
      value: this.eventBus.eventBusArn,
      description: 'ARN of the custom event bus',
      exportName: `${this.stackName}-EventBusArn`,
    });

    new cdk.CfnOutput(this, 'EventBusName', {
      value: this.eventBus.eventBusName,
      description: 'Name of the custom event bus',
      exportName: `${this.stackName}-EventBusName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.processorFunction.functionArn,
      description: 'ARN of the Lambda processor function',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.processorFunction.functionName,
      description: 'Name of the Lambda processor function',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    if (this.globalEndpoint) {
      new cdk.CfnOutput(this, 'GlobalEndpointArn', {
        value: this.globalEndpoint.attrArn,
        description: 'ARN of the global endpoint',
        exportName: `${this.stackName}-GlobalEndpointArn`,
      });
    }

    if (this.healthCheck) {
      new cdk.CfnOutput(this, 'HealthCheckId', {
        value: this.healthCheck.attrHealthCheckId,
        description: 'ID of the Route 53 health check',
        exportName: `${this.stackName}-HealthCheckId`,
      });
    }
  }

  /**
   * Returns the Lambda function code as a string
   */
  private getLambdaCode(): string {
    return `
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    region = os.environ.get('AWS_REGION', 'unknown')
    
    # Log the received event
    print(f"Processing event in region {region}")
    print(f"Event: {json.dumps(event, indent=2)}")
    
    # Extract event details
    for record in event.get('Records', []):
        event_source = record.get('source', 'unknown')
        event_detail_type = record.get('detail-type', 'unknown')
        event_detail = record.get('detail', {})
        
        # Process the event (implement your business logic here)
        process_business_event(event_source, event_detail_type, event_detail, region)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Events processed successfully in {region}',
            'timestamp': datetime.utcnow().isoformat(),
            'region': region
        })
    }

def process_business_event(source, detail_type, detail, region):
    """Process business events with region-specific logic"""
    
    # Example: Handle financial transaction events
    if source == 'finance.transactions' and detail_type == 'Transaction Created':
        transaction_id = detail.get('transactionId')
        amount = detail.get('amount')
        
        print(f"Processing transaction {transaction_id} "
              f"for amount {amount} in region {region}")
        
        # Implement your business logic here
        # Examples: update databases, send notifications, etc.
        
    # Example: Handle user events
    elif source == 'user.management' and detail_type == 'User Action':
        user_id = detail.get('userId')
        action = detail.get('action')
        
        print(f"Processing user action {action} for user {user_id} "
              f"in region {region}")
`;
  }
}

/**
 * Main CDK Application
 */
class MultiRegionEventReplicationApp extends cdk.App {
  constructor() {
    super();

    // Configuration
    const eventBusName = process.env.EVENT_BUS_NAME || 'global-events-bus';
    const lambdaFunctionName = process.env.LAMBDA_FUNCTION_NAME || 'event-processor';
    const globalEndpointName = process.env.GLOBAL_ENDPOINT_NAME || 'global-endpoint';
    const snsTopicArn = process.env.SNS_TOPIC_ARN;

    // Define regions
    const primaryRegion = 'us-east-1';
    const secondaryRegion = 'us-west-2';
    const tertiaryRegion = 'eu-west-1';

    // Create primary region stack
    const primaryStack = new MultiRegionEventReplicationStack(this, 'MultiRegionEventReplication-Primary', {
      env: { region: primaryRegion },
      isPrimaryRegion: true,
      otherRegions: [secondaryRegion, tertiaryRegion],
      eventBusName,
      lambdaFunctionName,
      globalEndpointName,
      snsTopicArn,
      description: 'Primary region stack for multi-region EventBridge event replication',
    });

    // Create secondary region stack
    const secondaryStack = new MultiRegionEventReplicationStack(this, 'MultiRegionEventReplication-Secondary', {
      env: { region: secondaryRegion },
      isPrimaryRegion: false,
      otherRegions: [primaryRegion, tertiaryRegion],
      eventBusName,
      lambdaFunctionName,
      description: 'Secondary region stack for multi-region EventBridge event replication',
    });

    // Create tertiary region stack
    const tertiaryStack = new MultiRegionEventReplicationStack(this, 'MultiRegionEventReplication-Tertiary', {
      env: { region: tertiaryRegion },
      isPrimaryRegion: false,
      otherRegions: [primaryRegion, secondaryRegion],
      eventBusName,
      lambdaFunctionName,
      description: 'Tertiary region stack for multi-region EventBridge event replication',
    });

    // Add dependencies
    secondaryStack.addDependency(primaryStack);
    tertiaryStack.addDependency(primaryStack);

    // Add tags to all stacks
    cdk.Tags.of(primaryStack).add('Environment', 'Production');
    cdk.Tags.of(primaryStack).add('Application', 'MultiRegionEventReplication');
    cdk.Tags.of(primaryStack).add('Region', 'Primary');

    cdk.Tags.of(secondaryStack).add('Environment', 'Production');
    cdk.Tags.of(secondaryStack).add('Application', 'MultiRegionEventReplication');
    cdk.Tags.of(secondaryStack).add('Region', 'Secondary');

    cdk.Tags.of(tertiaryStack).add('Environment', 'Production');
    cdk.Tags.of(tertiaryStack).add('Application', 'MultiRegionEventReplication');
    cdk.Tags.of(tertiaryStack).add('Region', 'Tertiary');
  }
}

// Create and run the CDK application
const app = new MultiRegionEventReplicationApp();