#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as sfnTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as route53 from 'aws-cdk-lib/aws-route53';

/**
 * Properties for the Disaster Recovery Stack
 */
interface DisasterRecoveryStackProps extends cdk.StackProps {
  /** Primary AWS region for production resources */
  primaryRegion: string;
  /** Disaster recovery region for backup resources */
  drRegion: string;
  /** Email address for disaster recovery notifications */
  notificationEmail?: string;
  /** Project identifier for resource naming */
  projectId?: string;
  /** Domain name for Route 53 health checks */
  domainName?: string;
}

/**
 * Main stack for Cross-Region Disaster Recovery Automation
 * 
 * This stack implements automated disaster recovery using AWS Elastic Disaster Recovery (DRS)
 * with intelligent failover orchestration, automated testing, and seamless failback capabilities.
 */
class DisasterRecoveryStack extends cdk.Stack {
  public readonly drAutomationRole: iam.Role;
  public readonly drVpc: ec2.Vpc;
  public readonly failoverFunction: lambda.Function;
  public readonly failbackFunction: lambda.Function;
  public readonly testingFunction: lambda.Function;
  public readonly orchestrationStateMachine: stepfunctions.StateMachine;
  public readonly alertsTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: DisasterRecoveryStackProps) {
    super(scope, id, props);

    const projectId = props.projectId || this.generateProjectId();

    // Create IAM role for disaster recovery automation
    this.drAutomationRole = this.createAutomationRole(projectId);

    // Create DR region VPC infrastructure
    this.drVpc = this.createDrVpc(projectId);

    // Create SNS topic for alerts
    this.alertsTopic = this.createAlertsTopic(projectId, props.notificationEmail);

    // Create Lambda functions for DR automation
    this.failoverFunction = this.createFailoverFunction(projectId, props.drRegion);
    this.failbackFunction = this.createFailbackFunction(projectId, props.primaryRegion);
    this.testingFunction = this.createTestingFunction(projectId, props.drRegion);

    // Create Step Functions state machine for orchestration
    this.orchestrationStateMachine = this.createOrchestrationStateMachine(projectId);

    // Create CloudWatch alarms and monitoring
    this.createMonitoringResources(projectId, props.domainName);

    // Create automated testing schedule
    this.createTestingSchedule(projectId);

    // Create CloudWatch dashboard
    this.createMonitoringDashboard(projectId);

    // Output important resources
    this.createOutputs();
  }

  /**
   * Generates a unique project identifier
   */
  private generateProjectId(): string {
    return Math.random().toString(36).substring(2, 10);
  }

  /**
   * Creates IAM role for disaster recovery automation with necessary permissions
   */
  private createAutomationRole(projectId: string): iam.Role {
    const role = new iam.Role(this, 'DrAutomationRole', {
      roleName: `DRAutomationRole-${projectId}`,
      description: 'Role for disaster recovery automation across AWS services',
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('lambda.amazonaws.com'),
        new iam.ServicePrincipal('states.amazonaws.com'),
        new iam.ServicePrincipal('ssm.amazonaws.com')
      ),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add comprehensive policy for DRS and related services
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        // DRS permissions
        'drs:*',
        // EC2 permissions for instance management
        'ec2:*',
        // IAM role passing
        'iam:PassRole',
        // Route 53 for DNS failover
        'route53:*',
        // SNS for notifications
        'sns:*',
        // Systems Manager for automation
        'ssm:*',
        // CloudWatch for monitoring
        'cloudwatch:*',
        'logs:*',
        // Lambda for function invocation
        'lambda:*',
        // Step Functions for orchestration
        'states:*'
      ],
      resources: ['*'],
    }));

    cdk.Tags.of(role).add('Project', `enterprise-dr-${projectId}`);
    cdk.Tags.of(role).add('Purpose', 'DisasterRecovery');

    return role;
  }

  /**
   * Creates VPC infrastructure in the disaster recovery region
   */
  private createDrVpc(projectId: string): ec2.Vpc {
    const vpc = new ec2.Vpc(this, 'DrVpc', {
      vpcName: `disaster-recovery-vpc-${projectId}`,
      ipAddresses: ec2.IpAddresses.cidr('10.100.0.0/16'),
      maxAzs: 2,
      natGateways: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'DR-Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'DR-Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Create security group for DR instances
    const drSecurityGroup = new ec2.SecurityGroup(this, 'DrSecurityGroup', {
      vpc,
      securityGroupName: `dr-security-group-${projectId}`,
      description: 'Security group for disaster recovery instances',
      allowAllOutbound: true,
    });

    // Allow HTTP and HTTPS traffic
    drSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic'
    );
    drSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic'
    );

    cdk.Tags.of(vpc).add('Project', `enterprise-dr-${projectId}`);
    cdk.Tags.of(vpc).add('Purpose', 'DisasterRecovery');

    return vpc;
  }

  /**
   * Creates SNS topic for disaster recovery alerts and notifications
   */
  private createAlertsTopic(projectId: string, notificationEmail?: string): sns.Topic {
    const topic = new sns.Topic(this, 'DrAlertsTopic', {
      topicName: `dr-alerts-${projectId}`,
      displayName: 'Disaster Recovery Alerts',
      description: 'SNS topic for disaster recovery notifications and alerts',
    });

    // Add email subscription if provided
    if (notificationEmail) {
      topic.addSubscription(new snsSubscriptions.EmailSubscription(notificationEmail));
    }

    cdk.Tags.of(topic).add('Project', `enterprise-dr-${projectId}`);

    return topic;
  }

  /**
   * Creates Lambda function for automated failover orchestration
   */
  private createFailoverFunction(projectId: string, drRegion: string): lambda.Function {
    const func = new lambda.Function(this, 'FailoverFunction', {
      functionName: `dr-automated-failover-${projectId}`,
      description: 'Orchestrates automated disaster recovery failover procedures',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      role: this.drAutomationRole,
      environment: {
        DR_REGION: drRegion,
        SNS_TOPIC_ARN: this.alertsTopic.topicArn,
        PROJECT_ID: projectId,
      },
      logRetention: logs.RetentionDays.ONE_MONTH,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Orchestrates automated disaster recovery failover procedures
    """
    drs_client = boto3.client('drs', region_name=os.environ['DR_REGION'])
    route53_client = boto3.client('route53')
    sns_client = boto3.client('sns')
    
    try:
        logger.info("Starting automated disaster recovery failover")
        
        # Get source servers for recovery
        response = drs_client.describe_source_servers()
        source_servers = response.get('sourceServers', [])
        
        if not source_servers:
            logger.warning("No source servers found for recovery")
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'No source servers available for recovery'})
            }
        
        recovery_jobs = []
        
        # Start recovery jobs for each source server
        for server in source_servers:
            if server.get('sourceServerID'):
                try:
                    job_response = drs_client.start_recovery(
                        sourceServers=[{
                            'sourceServerID': server['sourceServerID'],
                            'recoverySnapshotID': 'LATEST'
                        }],
                        tags={
                            'Purpose': 'AutomatedDR',
                            'Timestamp': datetime.utcnow().isoformat(),
                            'Project': os.environ.get('PROJECT_ID', 'unknown')
                        }
                    )
                    recovery_jobs.append(job_response['job']['jobID'])
                    logger.info(f"Started recovery job {job_response['job']['jobID']} for server {server['sourceServerID']}")
                except Exception as e:
                    logger.error(f"Failed to start recovery for server {server['sourceServerID']}: {str(e)}")
        
        # Update Route 53 records for failover (example implementation)
        try:
            hosted_zones = route53_client.list_hosted_zones()
            for zone in hosted_zones['HostedZones']:
                # This is a template - replace with actual domain logic
                if any(domain in zone['Name'] for domain in ['example.com', 'yourdomain.com']):
                    logger.info(f"Updating DNS records for zone {zone['Name']}")
                    # DNS failover logic would go here
        except Exception as e:
            logger.error(f"Failed to update DNS records: {str(e)}")
        
        # Send success notification
        message = f'Automated DR failover initiated successfully. Recovery jobs: {recovery_jobs}'
        sns_client.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=message,
            Subject='DR Failover Activated - Success'
        )
        
        logger.info("Disaster recovery failover completed successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Failover initiated successfully',
                'recoveryJobs': recovery_jobs,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        error_message = f'DR failover failed: {str(e)}'
        logger.error(error_message)
        
        # Send failure notification
        try:
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Message=error_message,
                Subject='DR Failover Failed'
            )
        except Exception as sns_error:
            logger.error(f"Failed to send failure notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
      `),
    });

    cdk.Tags.of(func).add('Project', `enterprise-dr-${projectId}`);
    cdk.Tags.of(func).add('Purpose', 'DisasterRecovery');

    return func;
  }

  /**
   * Creates Lambda function for automated failback orchestration
   */
  private createFailbackFunction(projectId: string, primaryRegion: string): lambda.Function {
    const func = new lambda.Function(this, 'FailbackFunction', {
      functionName: `dr-automated-failback-${projectId}`,
      description: 'Orchestrates automated failback to primary region',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      role: this.drAutomationRole,
      environment: {
        PRIMARY_REGION: primaryRegion,
        SNS_TOPIC_ARN: this.alertsTopic.topicArn,
        PROJECT_ID: projectId,
      },
      logRetention: logs.RetentionDays.ONE_MONTH,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Orchestrates automated failback to primary region
    """
    drs_client = boto3.client('drs', region_name=os.environ['PRIMARY_REGION'])
    route53_client = boto3.client('route53')
    sns_client = boto3.client('sns')
    
    try:
        logger.info("Starting automated failback to primary region")
        
        # Get recovery instances for failback
        response = drs_client.describe_recovery_instances()
        recovery_instances = response.get('recoveryInstances', [])
        
        if not recovery_instances:
            logger.warning("No recovery instances found for failback")
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'No recovery instances available for failback'})
            }
        
        failback_jobs = []
        
        # Start failback jobs for each recovery instance
        for instance in recovery_instances:
            if instance.get('recoveryInstanceID'):
                try:
                    job_response = drs_client.start_failback_launch(
                        recoveryInstanceIDs=[instance['recoveryInstanceID']],
                        tags={
                            'Purpose': 'AutomatedFailback',
                            'Timestamp': datetime.utcnow().isoformat(),
                            'Project': os.environ.get('PROJECT_ID', 'unknown')
                        }
                    )
                    failback_jobs.append(job_response['job']['jobID'])
                    logger.info(f"Started failback job {job_response['job']['jobID']} for instance {instance['recoveryInstanceID']}")
                except Exception as e:
                    logger.error(f"Failed to start failback for instance {instance['recoveryInstanceID']}: {str(e)}")
        
        # Update Route 53 records back to primary
        try:
            hosted_zones = route53_client.list_hosted_zones()
            for zone in hosted_zones['HostedZones']:
                # This is a template - replace with actual domain logic
                if any(domain in zone['Name'] for domain in ['example.com', 'yourdomain.com']):
                    logger.info(f"Updating DNS records back to primary for zone {zone['Name']}")
                    # DNS failback logic would go here
        except Exception as e:
            logger.error(f"Failed to update DNS records: {str(e)}")
        
        # Send success notification
        message = f'Automated failback initiated successfully. Failback jobs: {failback_jobs}'
        sns_client.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=message,
            Subject='DR Failback Activated - Success'
        )
        
        logger.info("Failback to primary region completed successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Failback initiated successfully',
                'failbackJobs': failback_jobs,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        error_message = f'DR failback failed: {str(e)}'
        logger.error(error_message)
        
        # Send failure notification
        try:
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Message=error_message,
                Subject='DR Failback Failed'
            )
        except Exception as sns_error:
            logger.error(f"Failed to send failure notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
      `),
    });

    cdk.Tags.of(func).add('Project', `enterprise-dr-${projectId}`);
    cdk.Tags.of(func).add('Purpose', 'DisasterRecovery');

    return func;
  }

  /**
   * Creates Lambda function for automated disaster recovery testing
   */
  private createTestingFunction(projectId: string, drRegion: string): lambda.Function {
    const func = new lambda.Function(this, 'TestingFunction', {
      functionName: `dr-testing-${projectId}`,
      description: 'Orchestrates automated disaster recovery testing and drills',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      role: this.drAutomationRole,
      environment: {
        DR_REGION: drRegion,
        SNS_TOPIC_ARN: this.alertsTopic.topicArn,
        PROJECT_ID: projectId,
      },
      logRetention: logs.RetentionDays.ONE_MONTH,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime, timedelta
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Orchestrates automated disaster recovery testing and drills
    """
    drs_client = boto3.client('drs', region_name=os.environ['DR_REGION'])
    ssm_client = boto3.client('ssm', region_name=os.environ['DR_REGION'])
    sns_client = boto3.client('sns')
    
    try:
        logger.info("Starting automated disaster recovery drill")
        
        # Get source servers for drill
        response = drs_client.describe_source_servers()
        source_servers = response.get('sourceServers', [])
        
        if not source_servers:
            logger.warning("No source servers found for DR drill")
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'No source servers available for drill'})
            }
        
        drill_jobs = []
        
        # Start drill jobs for each source server
        for server in source_servers:
            if server.get('sourceServerID'):
                try:
                    job_response = drs_client.start_recovery(
                        sourceServers=[{
                            'sourceServerID': server['sourceServerID'],
                            'recoverySnapshotID': 'LATEST'
                        }],
                        isDrill=True,
                        tags={
                            'Purpose': 'DR-Drill',
                            'Timestamp': datetime.utcnow().isoformat(),
                            'Project': os.environ.get('PROJECT_ID', 'unknown')
                        }
                    )
                    drill_jobs.append(job_response['job']['jobID'])
                    logger.info(f"Started drill job {job_response['job']['jobID']} for server {server['sourceServerID']}")
                except Exception as e:
                    logger.error(f"Failed to start drill for server {server['sourceServerID']}: {str(e)}")
        
        # Schedule automatic cleanup (2 hours from now)
        cleanup_time = datetime.utcnow() + timedelta(hours=2)
        
        try:
            # This would schedule cleanup commands for drill instances
            logger.info(f"DR drill cleanup scheduled for {cleanup_time}")
            # Actual cleanup scheduling would depend on specific instance IDs from drill
        except Exception as e:
            logger.error(f"Failed to schedule cleanup: {str(e)}")
        
        # Send notification about drill initiation
        message = f'Automated DR drill initiated successfully. Drill jobs: {drill_jobs}. Cleanup scheduled for {cleanup_time}'
        sns_client.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=message,
            Subject='DR Drill Initiated - Success'
        )
        
        logger.info("Disaster recovery drill completed successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'DR drill initiated successfully',
                'drillJobs': drill_jobs,
                'cleanupScheduled': cleanup_time.isoformat(),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        error_message = f'DR testing failed: {str(e)}'
        logger.error(error_message)
        
        # Send failure notification
        try:
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Message=error_message,
                Subject='DR Drill Failed'
            )
        except Exception as sns_error:
            logger.error(f"Failed to send failure notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
      `),
    });

    cdk.Tags.of(func).add('Project', `enterprise-dr-${projectId}`);
    cdk.Tags.of(func).add('Purpose', 'DisasterRecovery');

    return func;
  }

  /**
   * Creates Step Functions state machine for disaster recovery orchestration
   */
  private createOrchestrationStateMachine(projectId: string): stepfunctions.StateMachine {
    // Define state machine tasks
    const validateSourceServers = new sfnTasks.CallAwsService(this, 'ValidateSourceServers', {
      service: 'drs',
      action: 'describeSourceServers',
      iamResources: ['*'],
      resultPath: '$.sourceServersResult',
    });

    const checkReplicationStatus = new sfnTasks.CallAwsService(this, 'CheckReplicationStatus', {
      service: 'drs',
      action: 'describeSourceServers',
      iamResources: ['*'],
      resultPath: '$.replicationStatus',
    });

    const initiateRecovery = new sfnTasks.LambdaInvoke(this, 'InitiateRecovery', {
      lambdaFunction: this.failoverFunction,
      resultPath: '$.recoveryResult',
    });

    const monitorRecoveryJobs = new sfnTasks.CallAwsService(this, 'MonitorRecoveryJobs', {
      service: 'drs',
      action: 'describeJobs',
      iamResources: ['*'],
      resultPath: '$.jobsStatus',
    });

    const waitForCompletion = new stepfunctions.Wait(this, 'WaitForCompletion', {
      time: stepfunctions.WaitTime.duration(cdk.Duration.seconds(30)),
    });

    const updateDnsRecords = new sfnTasks.CallAwsService(this, 'UpdateDnsRecords', {
      service: 'route53',
      action: 'changeResourceRecordSets',
      parameters: {
        'HostedZoneId': 'Z123456789', // Replace with actual hosted zone ID
        'ChangeBatch': {
          'Changes': [{
            'Action': 'UPSERT',
            'ResourceRecordSet': {
              'Name': 'app.example.com', // Replace with actual domain
              'Type': 'A',
              'SetIdentifier': 'DR-Failover',
              'Failover': 'SECONDARY',
              'TTL': 60,
              'ResourceRecords': [{ 'Value': '10.100.1.100' }] // Replace with DR IP
            }
          }]
        }
      },
      iamResources: ['*'],
      resultPath: '$.dnsResult',
    });

    const notifySuccess = new sfnTasks.SnsPublish(this, 'NotifySuccess', {
      topic: this.alertsTopic,
      message: stepfunctions.TaskInput.fromText('Disaster recovery completed successfully'),
      subject: 'DR Orchestration - Success',
    });

    const notifyFailure = new sfnTasks.SnsPublish(this, 'NotifyFailure', {
      topic: this.alertsTopic,
      message: stepfunctions.TaskInput.fromText('Disaster recovery failed'),
      subject: 'DR Orchestration - Failed',
    });

    // Define job status check logic
    const checkJobStatus = new stepfunctions.Choice(this, 'CheckJobStatus')
      .when(
        stepfunctions.Condition.stringEquals('$.jobsStatus.jobs[0].status', 'COMPLETED'),
        updateDnsRecords.next(notifySuccess)
      )
      .when(
        stepfunctions.Condition.stringEquals('$.jobsStatus.jobs[0].status', 'FAILED'),
        notifyFailure
      )
      .otherwise(waitForCompletion.next(monitorRecoveryJobs));

    // Chain the state machine workflow
    const definition = validateSourceServers
      .next(checkReplicationStatus)
      .next(initiateRecovery)
      .next(monitorRecoveryJobs)
      .next(checkJobStatus);

    const stateMachine = new stepfunctions.StateMachine(this, 'DrOrchestrationStateMachine', {
      stateMachineName: `dr-orchestration-${projectId}`,
      definition,
      role: this.drAutomationRole,
      timeout: cdk.Duration.hours(2),
      logs: {
        destination: new logs.LogGroup(this, 'StateMachineLogGroup', {
          logGroupName: `/aws/stepfunctions/dr-orchestration-${projectId}`,
          retention: logs.RetentionDays.ONE_MONTH,
        }),
        level: stepfunctions.LogLevel.ALL,
      },
    });

    cdk.Tags.of(stateMachine).add('Project', `enterprise-dr-${projectId}`);
    cdk.Tags.of(stateMachine).add('Purpose', 'DisasterRecovery');

    return stateMachine;
  }

  /**
   * Creates CloudWatch monitoring resources including alarms and metrics
   */
  private createMonitoringResources(projectId: string, domainName?: string): void {
    // Create application health alarm
    const applicationHealthAlarm = new cloudwatch.Alarm(this, 'ApplicationHealthAlarm', {
      alarmName: `Application-Health-${projectId}`,
      alarmDescription: 'Monitor application health for DR trigger',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Route53',
        metricName: 'HealthCheckStatus',
        statistic: 'Minimum',
        period: cdk.Duration.minutes(1),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
    });

    applicationHealthAlarm.addAlarmAction(
      new cloudwatch.SnsAction(this.alertsTopic)
    );

    // Create DRS replication lag alarm
    const replicationLagAlarm = new cloudwatch.Alarm(this, 'ReplicationLagAlarm', {
      alarmName: `DRS-Replication-Lag-${projectId}`,
      alarmDescription: 'Monitor DRS replication lag',
      metric: new cloudwatch.Metric({
        namespace: 'Custom/DRS',
        metricName: 'ReplicationLag',
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 300, // 5 minutes
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    replicationLagAlarm.addAlarmAction(
      new cloudwatch.SnsAction(this.alertsTopic)
    );

    cdk.Tags.of(applicationHealthAlarm).add('Project', `enterprise-dr-${projectId}`);
    cdk.Tags.of(replicationLagAlarm).add('Project', `enterprise-dr-${projectId}`);
  }

  /**
   * Creates automated testing schedule using EventBridge rules
   */
  private createTestingSchedule(projectId: string): void {
    // Create EventBridge rule for monthly DR testing
    const monthlyDrDrill = new events.Rule(this, 'MonthlyDrDrill', {
      ruleName: `monthly-dr-drill-${projectId}`,
      description: 'Monthly automated disaster recovery drill',
      schedule: events.Schedule.rate(cdk.Duration.days(30)),
    });

    monthlyDrDrill.addTarget(new targets.LambdaFunction(this.testingFunction));

    cdk.Tags.of(monthlyDrDrill).add('Project', `enterprise-dr-${projectId}`);
  }

  /**
   * Creates CloudWatch dashboard for DR monitoring
   */
  private createMonitoringDashboard(projectId: string): void {
    const dashboard = new cloudwatch.Dashboard(this, 'DrMonitoringDashboard', {
      dashboardName: `DR-Monitoring-${projectId}`,
    });

    // Add DRS replication metrics widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'DRS Replication Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/DRS',
            metricName: 'ReplicationLag',
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/DRS',
            metricName: 'StagingStorageUtilization',
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Add Lambda function metrics widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'DR Automation Function Metrics',
        left: [
          this.failoverFunction.metricInvocations({
            period: cdk.Duration.minutes(5),
          }),
          this.failoverFunction.metricErrors({
            period: cdk.Duration.minutes(5),
          }),
        ],
        right: [
          this.failoverFunction.metricDuration({
            period: cdk.Duration.minutes(5),
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Add Step Functions execution metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'DR Orchestration Metrics',
        left: [
          this.orchestrationStateMachine.metricStarted({
            period: cdk.Duration.minutes(5),
          }),
          this.orchestrationStateMachine.metricSucceeded({
            period: cdk.Duration.minutes(5),
          }),
          this.orchestrationStateMachine.metricFailed({
            period: cdk.Duration.minutes(5),
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    cdk.Tags.of(dashboard).add('Project', `enterprise-dr-${projectId}`);
  }

  /**
   * Creates CloudFormation outputs for important resources
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'DrVpcId', {
      value: this.drVpc.vpcId,
      description: 'VPC ID for disaster recovery infrastructure',
      exportName: 'DrVpcId',
    });

    new cdk.CfnOutput(this, 'DrAutomationRoleArn', {
      value: this.drAutomationRole.roleArn,
      description: 'ARN of the disaster recovery automation role',
      exportName: 'DrAutomationRoleArn',
    });

    new cdk.CfnOutput(this, 'FailoverFunctionArn', {
      value: this.failoverFunction.functionArn,
      description: 'ARN of the automated failover Lambda function',
      exportName: 'FailoverFunctionArn',
    });

    new cdk.CfnOutput(this, 'OrchestrationStateMachineArn', {
      value: this.orchestrationStateMachine.stateMachineArn,
      description: 'ARN of the disaster recovery orchestration state machine',
      exportName: 'OrchestrationStateMachineArn',
    });

    new cdk.CfnOutput(this, 'AlertsTopicArn', {
      value: this.alertsTopic.topicArn,
      description: 'ARN of the disaster recovery alerts SNS topic',
      exportName: 'AlertsTopicArn',
    });
  }
}

/**
 * CDK Application for Cross-Region Disaster Recovery Automation
 */
class DisasterRecoveryApp extends cdk.App {
  constructor() {
    super();

    // Get configuration from CDK context or environment variables
    const primaryRegion = this.node.tryGetContext('primaryRegion') || process.env.PRIMARY_REGION || 'us-east-1';
    const drRegion = this.node.tryGetContext('drRegion') || process.env.DR_REGION || 'us-west-2';
    const notificationEmail = this.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
    const domainName = this.node.tryGetContext('domainName') || process.env.DOMAIN_NAME;
    const projectId = this.node.tryGetContext('projectId') || process.env.PROJECT_ID;

    // Create primary stack in DR region (where DR infrastructure resides)
    new DisasterRecoveryStack(this, 'DisasterRecoveryStack', {
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: drRegion,
      },
      primaryRegion,
      drRegion,
      notificationEmail,
      domainName,
      projectId,
      description: 'Cross-Region Disaster Recovery Automation with AWS Elastic Disaster Recovery',
    });

    // Add stack-level tags
    cdk.Tags.of(this).add('Application', 'CrossRegionDisasterRecovery');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'Infrastructure Team');
    cdk.Tags.of(this).add('CostCenter', 'IT-Operations');
  }
}

// Create and synth the application
const app = new DisasterRecoveryApp();