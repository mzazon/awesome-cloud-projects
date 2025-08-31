#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as wellarchitected from 'aws-cdk-lib/aws-wellarchitected';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the ArchitectureAssessmentStack
 */
export interface ArchitectureAssessmentStackProps extends cdk.StackProps {
  /**
   * The name of the workload to create for assessment
   * @default 'sample-web-app'
   */
  readonly workloadName?: string;

  /**
   * The environment type for the workload
   * @default 'PREPRODUCTION'
   */
  readonly environmentType?: string;

  /**
   * The industry type for the workload
   * @default 'InfoTech'
   */
  readonly industryType?: string;

  /**
   * Whether to create CloudWatch monitoring for assessment progress
   * @default true
   */
  readonly enableMonitoring?: boolean;

  /**
   * Whether to create automated assessment reminders
   * @default true
   */
  readonly enableAutomatedReminders?: boolean;
}

/**
 * CDK Stack for AWS Well-Architected Tool Architecture Assessment
 * 
 * This stack creates:
 * - A Well-Architected Tool workload for assessment
 * - CloudWatch metrics and dashboards for monitoring assessment progress
 * - Lambda function for automated assessment workflows
 * - EventBridge rules for scheduled assessment reminders
 */
export class ArchitectureAssessmentStack extends cdk.Stack {
  /**
   * The Well-Architected workload created for assessment
   */
  public readonly workload: wellarchitected.CfnWorkload;

  /**
   * CloudWatch dashboard for monitoring assessment progress
   */
  public readonly assessmentDashboard: cloudwatch.Dashboard;

  /**
   * Lambda function for assessment automation
   */
  public readonly assessmentFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: ArchitectureAssessmentStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const workloadName = props.workloadName ?? 'sample-web-app';
    const environmentType = props.environmentType ?? 'PREPRODUCTION';
    const industryType = props.industryType ?? 'InfoTech';
    const enableMonitoring = props.enableMonitoring ?? true;
    const enableAutomatedReminders = props.enableAutomatedReminders ?? true;

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);
    const fullWorkloadName = `${workloadName}-${uniqueSuffix}`;

    // Create IAM role for Well-Architected Tool access
    const wellArchitectedRole = new iam.Role(this, 'WellArchitectedRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for accessing AWS Well-Architected Tool',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        WellArchitectedAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'wellarchitected:CreateWorkload',
                'wellarchitected:GetWorkload',
                'wellarchitected:UpdateWorkload',
                'wellarchitected:DeleteWorkload',
                'wellarchitected:ListWorkloads',
                'wellarchitected:GetLensReview',
                'wellarchitected:UpdateLensReview',
                'wellarchitected:ListAnswers',
                'wellarchitected:GetAnswer',
                'wellarchitected:UpdateAnswer',
                'wellarchitected:ListLensReviewImprovements',
                'wellarchitected:CreateMilestone',
                'wellarchitected:GetMilestone',
                'wellarchitected:ListMilestones',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
                'cloudwatch:GetMetricStatistics',
                'cloudwatch:ListMetrics',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create Well-Architected Tool workload
    this.workload = new wellarchitected.CfnWorkload(this, 'AssessmentWorkload', {
      workloadName: fullWorkloadName,
      description: 'Sample web application workload for Well-Architected assessment',
      environment: environmentType,
      awsRegions: [this.region],
      reviewOwner: cdk.Aws.ACCOUNT_ID,
      lenses: ['wellarchitected'],
      industryType: industryType,
      architecturalDesign: 'Three-tier web application with load balancer, application servers, and database',
      accountIds: [cdk.Aws.ACCOUNT_ID],
      isReviewOwnerUpdateAcknowledged: true,
      tags: {
        Environment: environmentType,
        Purpose: 'Architecture Assessment',
        CreatedBy: 'CDK',
      },
    });

    // Create Lambda function for assessment automation
    this.assessmentFunction = new lambda.Function(this, 'AssessmentFunction', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: wellArchitectedRole,
      description: 'Lambda function for automating Well-Architected assessments',
      timeout: cdk.Duration.minutes(5),
      environment: {
        WORKLOAD_ID: this.workload.attrWorkloadId,
        WORKLOAD_NAME: fullWorkloadName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function to automate Well-Architected Tool operations
    """
    wellarchitected = boto3.client('wellarchitected')
    cloudwatch = boto3.client('cloudwatch')
    
    workload_id = os.environ['WORKLOAD_ID']
    workload_name = os.environ['WORKLOAD_NAME']
    
    try:
        # Get workload details
        workload_response = wellarchitected.get_workload(WorkloadId=workload_id)
        workload = workload_response['Workload']
        
        # Get lens review details
        lens_review = wellarchitected.get_lens_review(
            WorkloadId=workload_id,
            LensAlias='wellarchitected'
        )
        
        # Calculate assessment progress metrics
        total_questions = 0
        answered_questions = 0
        risk_counts = lens_review['LensReview'].get('RiskCounts', {})
        
        # Get pillar summaries
        for pillar in lens_review['LensReview'].get('PillarReviewSummaries', []):
            pillar_answers = wellarchitected.list_answers(
                WorkloadId=workload_id,
                LensAlias='wellarchitected',
                PillarId=pillar['PillarId']
            )
            
            pillar_total = len(pillar_answers['AnswerSummaries'])
            pillar_answered = len([a for a in pillar_answers['AnswerSummaries'] 
                                 if a.get('SelectedChoices')])
            
            total_questions += pillar_total
            answered_questions += pillar_answered
            
            # Send pillar-specific metrics to CloudWatch
            cloudwatch.put_metric_data(
                Namespace='WellArchitected/Assessment',
                MetricData=[
                    {
                        'MetricName': 'QuestionsAnswered',
                        'Dimensions': [
                            {'Name': 'WorkloadId', 'Value': workload_id},
                            {'Name': 'PillarId', 'Value': pillar['PillarId']},
                        ],
                        'Value': pillar_answered,
                        'Unit': 'Count'
                    },
                    {
                        'MetricName': 'TotalQuestions', 
                        'Dimensions': [
                            {'Name': 'WorkloadId', 'Value': workload_id},
                            {'Name': 'PillarId', 'Value': pillar['PillarId']},
                        ],
                        'Value': pillar_total,
                        'Unit': 'Count'
                    }
                ]
            )
        
        # Calculate completion percentage
        completion_percentage = (answered_questions / total_questions * 100) if total_questions > 0 else 0
        
        # Send overall metrics to CloudWatch
        metric_data = [
            {
                'MetricName': 'AssessmentCompletion',
                'Dimensions': [{'Name': 'WorkloadId', 'Value': workload_id}],
                'Value': completion_percentage,
                'Unit': 'Percent'
            },
            {
                'MetricName': 'TotalQuestions',
                'Dimensions': [{'Name': 'WorkloadId', 'Value': workload_id}],
                'Value': total_questions,
                'Unit': 'Count'
            },
            {
                'MetricName': 'AnsweredQuestions',
                'Dimensions': [{'Name': 'WorkloadId', 'Value': workload_id}],
                'Value': answered_questions,
                'Unit': 'Count'
            }
        ]
        
        # Add risk metrics
        for risk_level, count in risk_counts.items():
            metric_data.append({
                'MetricName': f'{risk_level}Risk',
                'Dimensions': [{'Name': 'WorkloadId', 'Value': workload_id}],
                'Value': count,
                'Unit': 'Count'
            })
        
        cloudwatch.put_metric_data(
            Namespace='WellArchitected/Assessment',
            MetricData=metric_data
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Assessment metrics updated successfully',
                'workload_id': workload_id,
                'completion_percentage': completion_percentage,
                'total_questions': total_questions,
                'answered_questions': answered_questions,
                'risk_counts': risk_counts
            })
        }
        
    except Exception as e:
        print(f"Error processing assessment: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
`),
    });

    // Create CloudWatch monitoring resources if enabled
    if (enableMonitoring) {
      // Create custom metrics for assessment progress
      const completionMetric = new cloudwatch.Metric({
        namespace: 'WellArchitected/Assessment',
        metricName: 'AssessmentCompletion',
        dimensionsMap: {
          WorkloadId: this.workload.attrWorkloadId,
        },
        statistic: 'Average',
        period: cdk.Duration.hours(1),
      });

      const highRiskMetric = new cloudwatch.Metric({
        namespace: 'WellArchitected/Assessment',
        metricName: 'HighRisk',
        dimensionsMap: {
          WorkloadId: this.workload.attrWorkloadId,
        },
        statistic: 'Average',
        period: cdk.Duration.hours(1),
      });

      const mediumRiskMetric = new cloudwatch.Metric({
        namespace: 'WellArchitected/Assessment',
        metricName: 'MediumRisk',
        dimensionsMap: {
          WorkloadId: this.workload.attrWorkloadId,
        },
        statistic: 'Average',
        period: cdk.Duration.hours(1),
      });

      // Create CloudWatch dashboard
      this.assessmentDashboard = new cloudwatch.Dashboard(this, 'AssessmentDashboard', {
        dashboardName: `WellArchitected-Assessment-${uniqueSuffix}`,
        defaultInterval: cdk.Duration.hours(24),
      });

      // Add widgets to dashboard
      this.assessmentDashboard.addWidgets(
        new cloudwatch.GraphWidget({
          title: 'Assessment Completion Progress',
          left: [completionMetric],
          width: 12,
          height: 6,
          leftYAxis: {
            min: 0,
            max: 100,
          },
        }),
        new cloudwatch.GraphWidget({
          title: 'Risk Assessment Overview',
          left: [highRiskMetric, mediumRiskMetric],
          width: 12,
          height: 6,
        })
      );

      // Add single value widgets for current status
      this.assessmentDashboard.addWidgets(
        new cloudwatch.SingleValueWidget({
          title: 'Current Completion %',
          metrics: [completionMetric],
          width: 6,
          height: 6,
        }),
        new cloudwatch.SingleValueWidget({
          title: 'High Risk Issues',
          metrics: [highRiskMetric],
          width: 6,
          height: 6,
        }),
        new cloudwatch.SingleValueWidget({
          title: 'Medium Risk Issues',
          metrics: [mediumRiskMetric],
          width: 6,
          height: 6,
        })
      );

      // Create CloudWatch alarms for high-risk findings
      const highRiskAlarm = new cloudwatch.Alarm(this, 'HighRiskAlarm', {
        metric: highRiskMetric,
        threshold: 1,
        evaluationPeriods: 1,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        alarmDescription: 'Alert when high-risk issues are identified in Well-Architected assessment',
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });

      // Create log group for assessment activities
      const assessmentLogGroup = new logs.LogGroup(this, 'AssessmentLogGroup', {
        logGroupName: `/aws/wellarchitected/assessment/${fullWorkloadName}`,
        retention: logs.RetentionDays.ONE_MONTH,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      });
    }

    // Create automated reminder system if enabled
    if (enableAutomatedReminders) {
      // Create EventBridge rule for weekly assessment reminders
      const weeklyAssessmentRule = new events.Rule(this, 'WeeklyAssessmentRule', {
        description: 'Trigger weekly Well-Architected assessment review',
        schedule: events.Schedule.cron({
          weekDay: '1', // Monday
          hour: '9',    // 9 AM
          minute: '0',
        }),
      });

      // Add Lambda function as target
      weeklyAssessmentRule.addTarget(new targets.LambdaFunction(this.assessmentFunction, {
        event: events.RuleTargetInput.fromObject({
          action: 'weekly-reminder',
          workloadId: this.workload.attrWorkloadId,
        }),
      }));

      // Create monthly milestone rule
      const monthlyMilestoneRule = new events.Rule(this, 'MonthlyMilestoneRule', {
        description: 'Create monthly Well-Architected assessment milestone',
        schedule: events.Schedule.cron({
          day: '1',     // First day of month
          hour: '10',   // 10 AM
          minute: '0',
        }),
      });

      monthlyMilestoneRule.addTarget(new targets.LambdaFunction(this.assessmentFunction, {
        event: events.RuleTargetInput.fromObject({
          action: 'create-milestone',
          workloadId: this.workload.attrWorkloadId,
        }),
      }));
    }

    // Create CloudFormation outputs
    new cdk.CfnOutput(this, 'WorkloadId', {
      value: this.workload.attrWorkloadId,
      description: 'The ID of the Well-Architected Tool workload',
      exportName: `${this.stackName}-WorkloadId`,
    });

    new cdk.CfnOutput(this, 'WorkloadName', {
      value: fullWorkloadName,
      description: 'The name of the Well-Architected Tool workload',
      exportName: `${this.stackName}-WorkloadName`,
    });

    new cdk.CfnOutput(this, 'WellArchitectedConsoleUrl', {
      value: `https://${this.region}.console.aws.amazon.com/wellarchitected/home?region=${this.region}#/workload/${this.workload.attrWorkloadId}`,
      description: 'URL to access the workload in the Well-Architected Tool console',
    });

    if (enableMonitoring) {
      new cdk.CfnOutput(this, 'DashboardUrl', {
        value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.assessmentDashboard.dashboardName}`,
        description: 'URL to access the CloudWatch dashboard for assessment monitoring',
      });
    }

    new cdk.CfnOutput(this, 'AssessmentFunctionName', {
      value: this.assessmentFunction.functionName,
      description: 'Name of the Lambda function for assessment automation',
      exportName: `${this.stackName}-AssessmentFunctionName`,
    });

    // Add tags to all resources in the stack
    cdk.Tags.of(this).add('Project', 'ArchitectureAssessment');
    cdk.Tags.of(this).add('Purpose', 'WellArchitectedTool');
    cdk.Tags.of(this).add('CreatedBy', 'CDK');
    cdk.Tags.of(this).add('Environment', environmentType);
  }
}

/**
 * Main CDK application
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables  
const workloadName = app.node.tryGetContext('workloadName') || process.env.WORKLOAD_NAME || 'sample-web-app';
const environmentType = app.node.tryGetContext('environmentType') || process.env.ENVIRONMENT_TYPE || 'PREPRODUCTION';
const industryType = app.node.tryGetContext('industryType') || process.env.INDUSTRY_TYPE || 'InfoTech';
const enableMonitoring = app.node.tryGetContext('enableMonitoring') !== false;
const enableAutomatedReminders = app.node.tryGetContext('enableAutomatedReminders') !== false;

// Create the stack
new ArchitectureAssessmentStack(app, 'ArchitectureAssessmentStack', {
  workloadName,
  environmentType,
  industryType,
  enableMonitoring,
  enableAutomatedReminders,
  description: 'CDK stack for AWS Well-Architected Tool architecture assessment with monitoring and automation',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  terminationProtection: false, // Allow easy cleanup for demo purposes
});

// Add stack-level metadata
app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', true);