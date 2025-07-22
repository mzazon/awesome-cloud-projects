import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { Construct } from 'constructs';

export interface InfrastructureAutomationStackProps extends cdk.StackProps {
  /**
   * Email address for notification alerts (optional)
   */
  readonly notificationEmail?: string;
  
  /**
   * Schedule expression for automation execution
   * @default 'cron(0 6 * * ? *)' - Daily at 6 AM UTC
   */
  readonly scheduleExpression?: string;
  
  /**
   * Log retention period for automation logs
   * @default logs.RetentionDays.ONE_MONTH
   */
  readonly logRetention?: logs.RetentionDays;
}

/**
 * CDK Stack for Infrastructure Management Automation
 * 
 * This stack creates a serverless automation framework that integrates:
 * - AWS CloudShell PowerShell environment for script development
 * - Systems Manager Automation Documents for PowerShell script execution
 * - Lambda functions for orchestration and scheduling
 * - EventBridge for scheduled execution
 * - CloudWatch for monitoring and alerting
 * 
 * The solution enables infrastructure engineers to develop PowerShell automation
 * scripts in CloudShell and deploy them as enterprise-grade automation workflows.
 */
export class InfrastructureAutomationStack extends cdk.Stack {
  /**
   * The IAM role used by automation services
   */
  public readonly automationRole: iam.Role;
  
  /**
   * The Lambda function that orchestrates automation execution
   */
  public readonly orchestrationFunction: lambda.Function;
  
  /**
   * The CloudWatch Log Group for automation logs
   */
  public readonly automationLogGroup: logs.LogGroup;
  
  /**
   * The SNS topic for automation alerts
   */
  public readonly alertTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: InfrastructureAutomationStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const scheduleExpression = props.scheduleExpression ?? 'cron(0 6 * * ? *)';
    const logRetention = props.logRetention ?? logs.RetentionDays.ONE_MONTH;

    // Create IAM role for automation services
    this.automationRole = this.createAutomationRole();

    // Create CloudWatch Log Group for automation logs
    this.automationLogGroup = this.createLogGroup(logRetention);

    // Create SNS topic for notifications
    this.alertTopic = this.createAlertTopic(props.notificationEmail);

    // Create Lambda function for orchestration
    this.orchestrationFunction = this.createOrchestrationFunction();

    // Create Systems Manager Automation Document
    const automationDocument = this.createAutomationDocument();

    // Create EventBridge rule for scheduled execution
    this.createScheduledRule(scheduleExpression);

    // Create CloudWatch monitoring and alarms
    this.createMonitoringResources();

    // Create CloudWatch Dashboard
    this.createDashboard();

    // Output important resource information
    this.createOutputs();
  }

  /**
   * Creates the IAM role used by automation services with necessary permissions
   */
  private createAutomationRole(): iam.Role {
    const role = new iam.Role(this, 'AutomationRole', {
      roleName: `InfraAutomationRole-${this.region}`,
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('lambda.amazonaws.com'),
        new iam.ServicePrincipal('ssm.amazonaws.com')
      ),
      description: 'IAM role for infrastructure automation services',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add custom policy for automation permissions
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        // Systems Manager permissions
        'ssm:StartAutomationExecution',
        'ssm:GetAutomationExecution',
        'ssm:StopAutomationExecution',
        'ssm:SendCommand',
        'ssm:ListCommandInvocations',
        'ssm:DescribeInstanceInformation',
        'ssm:GetParameter',
        'ssm:GetParameters',
        'ssm:PutParameter',
        
        // EC2 permissions for health checks
        'ec2:DescribeInstances',
        'ec2:DescribeInstanceStatus',
        'ec2:DescribeSecurityGroups',
        'ec2:DescribeImages',
        'ec2:DescribeSnapshots',
        'ec2:DescribeVolumes',
        
        // S3 permissions for compliance checks
        's3:ListAllMyBuckets',
        's3:GetBucketEncryption',
        's3:GetBucketVersioning',
        's3:GetBucketLogging',
        's3:GetBucketLocation',
        's3:GetBucketPolicy',
        
        // CloudWatch permissions
        'cloudwatch:PutMetricData',
        'cloudwatch:GetMetricStatistics',
        'cloudwatch:ListMetrics',
        
        // CloudWatch Logs permissions
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        'logs:DescribeLogGroups',
        'logs:DescribeLogStreams',
        
        // SNS permissions for notifications
        'sns:Publish',
        
        // IAM permissions for resource discovery
        'iam:ListRoles',
        'iam:ListPolicies',
        'iam:GetRole',
        'iam:GetPolicy'
      ],
      resources: ['*'],
      conditions: {
        StringEquals: {
          'aws:RequestedRegion': this.region
        }
      }
    }));

    return role;
  }

  /**
   * Creates the CloudWatch Log Group for automation logs
   */
  private createLogGroup(retention: logs.RetentionDays): logs.LogGroup {
    return new logs.LogGroup(this, 'AutomationLogGroup', {
      logGroupName: '/aws/automation/infrastructure-health',
      retention,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
  }

  /**
   * Creates the SNS topic for automation alerts
   */
  private createAlertTopic(email?: string): sns.Topic {
    const topic = new sns.Topic(this, 'AutomationAlerts', {
      topicName: 'infrastructure-automation-alerts',
      displayName: 'Infrastructure Automation Alerts',
      description: 'Notifications for infrastructure automation events and errors',
    });

    // Add email subscription if provided
    if (email) {
      topic.addSubscription(new subscriptions.EmailSubscription(email));
    }

    return topic;
  }

  /**
   * Creates the Lambda function for automation orchestration
   */
  private createOrchestrationFunction(): lambda.Function {
    const func = new lambda.Function(this, 'OrchestrationFunction', {
      functionName: 'infrastructure-automation-orchestrator',
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: this.automationRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Orchestrates infrastructure automation workflows',
      environment: {
        AUTOMATION_DOCUMENT_NAME: 'InfrastructureHealthCheck',
        LOG_GROUP_NAME: this.automationLogGroup.logGroupName,
        SNS_TOPIC_ARN: this.alertTopic.topicArn,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function to orchestrate infrastructure automation
    """
    ssm = boto3.client('ssm')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    automation_document = os.environ['AUTOMATION_DOCUMENT_NAME']
    log_group_name = os.environ['LOG_GROUP_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    region = context.invoked_function_arn.split(':')[3]
    
    try:
        # Execute automation document
        response = ssm.start_automation_execution(
            DocumentName=automation_document,
            Parameters={
                'Region': [region],
                'LogGroupName': [log_group_name]
            }
        )
        
        execution_id = response['AutomationExecutionId']
        
        # Send success metric to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='Infrastructure/Automation',
            MetricData=[
                {
                    'MetricName': 'AutomationExecutions',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'DocumentName',
                            'Value': automation_document
                        },
                        {
                            'Name': 'Status',
                            'Value': 'Started'
                        }
                    ]
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Automation started successfully',
                'executionId': execution_id,
                'timestamp': datetime.utcnow().isoformat(),
                'region': region
            })
        }
        
    except Exception as e:
        error_message = f"Failed to start automation: {str(e)}"
        
        # Send error metric
        cloudwatch.put_metric_data(
            Namespace='Infrastructure/Automation',
            MetricData=[
                {
                    'MetricName': 'AutomationErrors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'DocumentName',
                            'Value': automation_document
                        },
                        {
                            'Name': 'Status',
                            'Value': 'Failed'
                        }
                    ]
                }
            ]
        )
        
        # Send SNS notification for errors
        sns.publish(
            TopicArn=sns_topic_arn,
            Message=json.dumps({
                'error': error_message,
                'timestamp': datetime.utcnow().isoformat(),
                'region': region,
                'function': context.function_name
            }),
            Subject=f'Infrastructure Automation Error - {region}'
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'timestamp': datetime.utcnow().isoformat(),
                'region': region
            })
        }
`),
    });

    // Grant the function permission to publish to SNS
    this.alertTopic.grantPublish(func);

    return func;
  }

  /**
   * Creates the Systems Manager Automation Document
   */
  private createAutomationDocument(): ssm.CfnDocument {
    const documentContent = {
      schemaVersion: '0.3',
      description: 'Infrastructure Health Check Automation using PowerShell',
      assumeRole: this.automationRole.roleArn,
      parameters: {
        Region: {
          type: 'String',
          description: 'AWS Region for health check',
          default: this.region,
        },
        LogGroupName: {
          type: 'String',
          description: 'CloudWatch Log Group for automation logs',
          default: this.automationLogGroup.logGroupName,
        },
      },
      mainSteps: [
        {
          name: 'CreateLogGroup',
          action: 'aws:executeAwsApi',
          inputs: {
            Service: 'logs',
            Api: 'CreateLogGroup',
            logGroupName: '{{ LogGroupName }}',
          },
          onFailure: 'Continue',
          description: 'Ensure CloudWatch Log Group exists for automation logs',
        },
        {
          name: 'ExecuteHealthCheck',
          action: 'aws:executeScript',
          inputs: {
            Runtime: 'PowerShell Core 6.0',
            Script: this.getPowerShellScript(),
            InputPayload: {
              Region: '{{ Region }}',
              LogGroup: '{{ LogGroupName }}',
            },
          },
          description: 'Execute PowerShell infrastructure health check script',
        },
      ],
      outputs: ['ExecuteHealthCheck.Payload'],
    };

    return new ssm.CfnDocument(this, 'AutomationDocument', {
      name: 'InfrastructureHealthCheck',
      documentType: 'Automation',
      documentFormat: 'JSON',
      content: documentContent,
      tags: [
        {
          key: 'Purpose',
          value: 'Infrastructure Health Check',
        },
        {
          key: 'Runtime',
          value: 'PowerShell Core 6.0',
        },
      ],
    });
  }

  /**
   * Returns the PowerShell script content for the automation document
   */
  private getPowerShellScript(): string {
    return `
param(
    [string]$Region = (Get-DefaultAWSRegion).Region,
    [string]$LogGroup = "/aws/automation/infrastructure-health"
)

# Function to write structured logs
function Write-AutomationLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
    $logEntry = @{
        timestamp = $timestamp
        level = $Level
        message = $Message
        region = $Region
    } | ConvertTo-Json -Compress
    
    Write-Host $logEntry
    
    try {
        # Send to CloudWatch Logs
        $logEvent = @{
            Message = $logEntry
            Timestamp = [DateTimeOffset]::UtcNow
        }
        Write-CWLLogEvent -LogGroupName $LogGroup -LogStreamName "health-check-$(Get-Date -Format 'yyyy-MM-dd')" -LogEvent $logEvent
    } catch {
        Write-Host "Failed to write to CloudWatch: $($_.Exception.Message)"
    }
}

# Check EC2 instance health
function Test-EC2Health {
    Write-AutomationLog "Starting EC2 health assessment"
    $instances = Get-EC2Instance -Region $Region
    $healthReport = @()
    
    foreach ($reservation in $instances) {
        foreach ($instance in $reservation.Instances) {
            $healthStatus = @{
                InstanceId = $instance.InstanceId
                State = $instance.State.Name
                Type = $instance.InstanceType
                LaunchTime = $instance.LaunchTime
                PublicIP = $instance.PublicIpAddress
                PrivateIP = $instance.PrivateIpAddress
                SecurityGroups = ($instance.SecurityGroups | ForEach-Object { $_.GroupName }) -join ","
                SubnetId = $instance.SubnetId
                VpcId = $instance.VpcId
            }
            $healthReport += $healthStatus
        }
    }
    
    Write-AutomationLog "Found $($healthReport.Count) EC2 instances"
    return $healthReport
}

# Check S3 bucket compliance
function Test-S3Compliance {
    Write-AutomationLog "Starting S3 compliance assessment"
    $buckets = Get-S3Bucket -Region $Region
    $complianceReport = @()
    
    foreach ($bucket in $buckets) {
        try {
            $encryption = Get-S3BucketEncryption -BucketName $bucket.BucketName -ErrorAction SilentlyContinue
            $versioning = Get-S3BucketVersioning -BucketName $bucket.BucketName -ErrorAction SilentlyContinue
            $logging = Get-S3BucketLogging -BucketName $bucket.BucketName -ErrorAction SilentlyContinue
            
            $complianceStatus = @{
                BucketName = $bucket.BucketName
                CreationDate = $bucket.CreationDate
                EncryptionEnabled = $null -ne $encryption
                VersioningEnabled = $versioning.Status -eq "Enabled"
                LoggingEnabled = $null -ne $logging.LoggingEnabled
                Region = $Region
            }
            $complianceReport += $complianceStatus
        } catch {
            Write-AutomationLog "Failed to assess bucket $($bucket.BucketName): $($_.Exception.Message)" "ERROR"
        }
    }
    
    Write-AutomationLog "Assessed $($complianceReport.Count) S3 buckets"
    return $complianceReport
}

# Main execution
try {
    Write-AutomationLog "Infrastructure health check started"
    
    # Import required AWS modules
    Import-Module AWS.Tools.EC2 -Force
    Import-Module AWS.Tools.S3 -Force
    Import-Module AWS.Tools.CloudWatchLogs -Force
    
    $ec2Health = Test-EC2Health
    $s3Compliance = Test-S3Compliance
    
    $report = @{
        Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
        Region = $Region
        EC2Health = $ec2Health
        S3Compliance = $s3Compliance
        Summary = @{
            EC2InstanceCount = $ec2Health.Count
            S3BucketCount = $s3Compliance.Count
            HealthyInstances = ($ec2Health | Where-Object { $_.State -eq "running" }).Count
            CompliantBuckets = ($s3Compliance | Where-Object { $_.EncryptionEnabled -and $_.VersioningEnabled }).Count
        }
    }
    
    # Output report
    $reportJson = $report | ConvertTo-Json -Depth 10
    Write-Host $reportJson
    
    Write-AutomationLog "Health check completed successfully"
    Write-AutomationLog ($report.Summary | ConvertTo-Json)
    
    return $report
    
} catch {
    Write-AutomationLog "Health check failed: $($_.Exception.Message)" "ERROR"
    throw
}
`;
  }

  /**
   * Creates the EventBridge rule for scheduled automation execution
   */
  private createScheduledRule(scheduleExpression: string): events.Rule {
    const rule = new events.Rule(this, 'ScheduledAutomationRule', {
      ruleName: 'infrastructure-health-schedule',
      description: 'Scheduled execution of infrastructure health checks',
      schedule: events.Schedule.expression(scheduleExpression),
    });

    // Add Lambda function as target
    rule.addTarget(new targets.LambdaFunction(this.orchestrationFunction));

    return rule;
  }

  /**
   * Creates CloudWatch monitoring resources including alarms
   */
  private createMonitoringResources(): void {
    // Create alarm for automation errors
    const errorAlarm = new cloudwatch.Alarm(this, 'AutomationErrorAlarm', {
      alarmName: 'infrastructure-automation-errors',
      alarmDescription: 'Alert when infrastructure automation encounters errors',
      metric: new cloudwatch.Metric({
        namespace: 'Infrastructure/Automation',
        metricName: 'AutomationErrors',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS action to the alarm
    errorAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertTopic));

    // Create alarm for Lambda function errors
    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      alarmName: 'infrastructure-automation-lambda-errors',
      alarmDescription: 'Alert when Lambda orchestration function fails',
      metric: this.orchestrationFunction.metricErrors({
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
    });

    lambdaErrorAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertTopic));
  }

  /**
   * Creates a CloudWatch Dashboard for monitoring automation performance
   */
  private createDashboard(): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'AutomationDashboard', {
      dashboardName: 'infrastructure-automation-monitoring',
      defaultInterval: cdk.Duration.hours(1),
    });

    // Add widgets to the dashboard
    dashboard.addWidgets(
      // Automation metrics
      new cloudwatch.GraphWidget({
        title: 'Automation Executions',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'Infrastructure/Automation',
            metricName: 'AutomationExecutions',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'Infrastructure/Automation',
            metricName: 'AutomationErrors',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
        ],
      }),

      // Lambda metrics
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Performance',
        width: 12,
        height: 6,
        left: [
          this.orchestrationFunction.metricInvocations({
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
        ],
        right: [
          this.orchestrationFunction.metricDuration({
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
        ],
      })
    );

    return dashboard;
  }

  /**
   * Creates stack outputs for important resources
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'AutomationRoleArn', {
      value: this.automationRole.roleArn,
      description: 'ARN of the IAM role used by automation services',
      exportName: `${this.stackName}-AutomationRoleArn`,
    });

    new cdk.CfnOutput(this, 'OrchestrationFunctionName', {
      value: this.orchestrationFunction.functionName,
      description: 'Name of the Lambda function orchestrating automation',
      exportName: `${this.stackName}-OrchestrationFunctionName`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: this.automationLogGroup.logGroupName,
      description: 'CloudWatch Log Group for automation logs',
      exportName: `${this.stackName}-LogGroupName`,
    });

    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'SNS topic ARN for automation alerts',
      exportName: `${this.stackName}-AlertTopicArn`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=infrastructure-automation-monitoring`,
      description: 'URL to the CloudWatch Dashboard for monitoring automation',
    });

    new cdk.CfnOutput(this, 'CloudShellUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudshell/home?region=${this.region}`,
      description: 'URL to AWS CloudShell for PowerShell script development',
    });
  }
}