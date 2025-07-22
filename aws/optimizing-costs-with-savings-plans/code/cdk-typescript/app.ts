#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as path from 'path';

/**
 * Stack for AWS Savings Plans Recommendations with Cost Explorer
 * 
 * This stack creates infrastructure for automated Savings Plans analysis using
 * AWS Cost Explorer APIs. It includes Lambda functions for analysis, S3 storage
 * for reports, EventBridge for automation, and CloudWatch for monitoring.
 */
export class SavingsPlansRecommendationsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create S3 bucket for storing cost recommendations and reports
    const reportsBucket = new s3.Bucket(this, 'CostRecommendationsBucket', {
      bucketName: `cost-recommendations-${this.account}-${cdk.Aws.REGION}`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldReports',
          enabled: true,
          expiration: cdk.Duration.days(90), // Keep reports for 90 days
          noncurrentVersionExpiration: cdk.Duration.days(30)
        }
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true // For demo purposes
    });

    // Create IAM role for Lambda function with Cost Explorer and Savings Plans permissions
    const lambdaRole = new iam.Role(this, 'SavingsPlansAnalyzerRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for Lambda function to analyze Savings Plans recommendations',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    // Add Cost Explorer and Savings Plans permissions
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ce:GetSavingsPlansPurchaseRecommendation',
        'ce:StartSavingsPlansPurchaseRecommendationGeneration',
        'ce:GetCostAndUsage',
        'ce:GetDimensionValues',
        'ce:GetUsageReport',
        'savingsplans:DescribeSavingsPlans',
        'savingsplans:DescribeSavingsPlansOfferings'
      ],
      resources: ['*']
    }));

    // Add S3 permissions for the Lambda function
    reportsBucket.grantReadWrite(lambdaRole);

    // Create Lambda function for Savings Plans analysis
    const savingsAnalyzerFunction = new lambda.Function(this, 'SavingsPlansAnalyzer', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import datetime
from decimal import Decimal
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda handler for analyzing Savings Plans recommendations
    
    Args:
        event: Lambda event containing analysis parameters
        context: Lambda context
        
    Returns:
        Dict containing analysis results and recommendations
    """
    try:
        # Initialize AWS clients
        ce_client = boto3.client('ce')
        s3_client = boto3.client('s3')
        
        # Extract analysis parameters from event
        lookback_days = event.get('lookback_days', 'SIXTY_DAYS')
        term_years = event.get('term_years', 'ONE_YEAR')
        payment_option = event.get('payment_option', 'NO_UPFRONT')
        bucket_name = event.get('bucket_name', '${reportsBucket.bucketName}')
        
        logger.info(f"Starting analysis with parameters: lookback={lookback_days}, term={term_years}, payment={payment_option}")
        
        # Initialize results structure
        results = {
            'analysis_date': datetime.datetime.now().isoformat(),
            'parameters': {
                'lookback_days': lookback_days,
                'term_years': term_years,
                'payment_option': payment_option
            },
            'recommendations': []
        }
        
        # Analyze different Savings Plans types
        sp_types = ['COMPUTE_SP', 'EC2_INSTANCE_SP', 'SAGEMAKER_SP']
        
        for sp_type in sp_types:
            try:
                logger.info(f"Analyzing {sp_type} recommendations...")
                
                # Get Savings Plans recommendations from Cost Explorer
                response = ce_client.get_savings_plans_purchase_recommendation(
                    SavingsPlansType=sp_type,
                    TermInYears=term_years,
                    PaymentOption=payment_option,
                    LookbackPeriodInDays=lookback_days,
                    PageSize=10
                )
                
                # Process recommendation data
                if 'SavingsPlansPurchaseRecommendation' in response:
                    rec = response['SavingsPlansPurchaseRecommendation']
                    summary = rec.get('SavingsPlansPurchaseRecommendationSummary', {})
                    
                    recommendation = {
                        'savings_plan_type': sp_type,
                        'summary': {
                            'estimated_monthly_savings': summary.get('EstimatedMonthlySavingsAmount', '0'),
                            'estimated_roi': summary.get('EstimatedROI', '0'),
                            'estimated_savings_percentage': summary.get('EstimatedSavingsPercentage', '0'),
                            'hourly_commitment': summary.get('HourlyCommitmentToPurchase', '0'),
                            'total_recommendations': summary.get('TotalRecommendationCount', '0')
                        },
                        'details': []
                    }
                    
                    # Add detailed recommendations
                    for detail in rec.get('SavingsPlansPurchaseRecommendationDetails', []):
                        recommendation['details'].append({
                            'account_id': detail.get('AccountId', ''),
                            'currency_code': detail.get('CurrencyCode', 'USD'),
                            'estimated_monthly_savings': detail.get('EstimatedMonthlySavingsAmount', '0'),
                            'estimated_roi': detail.get('EstimatedROI', '0'),
                            'hourly_commitment': detail.get('HourlyCommitmentToPurchase', '0'),
                            'upfront_cost': detail.get('UpfrontCost', '0'),
                            'savings_plans_details': detail.get('SavingsPlansDetails', {})
                        })
                    
                    results['recommendations'].append(recommendation)
                    logger.info(f"Successfully analyzed {sp_type}")
                else:
                    logger.warning(f"No recommendations found for {sp_type}")
                    
            except Exception as e:
                logger.error(f"Error analyzing {sp_type}: {str(e)}")
                results['recommendations'].append({
                    'savings_plan_type': sp_type,
                    'error': str(e)
                })
        
        # Calculate total potential savings
        total_monthly_savings = 0
        for rec in results['recommendations']:
            if 'error' not in rec:
                try:
                    savings = float(rec['summary']['estimated_monthly_savings'])
                    total_monthly_savings += savings
                except (ValueError, KeyError):
                    logger.warning(f"Could not parse savings amount for {rec.get('savings_plan_type')}")
                    pass
        
        results['total_monthly_savings'] = total_monthly_savings
        results['annual_savings_potential'] = total_monthly_savings * 12
        
        logger.info(f"Total monthly savings potential: ${total_monthly_savings}")
        
        # Save results to S3
        if bucket_name:
            try:
                timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
                key = f"savings-plans-recommendations/{timestamp}.json"
                
                s3_client.put_object(
                    Bucket=bucket_name,
                    Key=key,
                    Body=json.dumps(results, indent=2, default=str),
                    ContentType='application/json'
                )
                
                results['report_location'] = f"s3://{bucket_name}/{key}"
                logger.info(f"Report saved to S3: {results['report_location']}")
                
            except Exception as e:
                logger.error(f"Error saving report to S3: {str(e)}")
                results['s3_error'] = str(e)
        
        return {
            'statusCode': 200,
            'body': json.dumps(results, indent=2, default=str)
        }
        
    except Exception as e:
        logger.error(f"Lambda function error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to analyze Savings Plans recommendations'
            })
        }
      `),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: {
        BUCKET_NAME: reportsBucket.bucketName,
        LOG_LEVEL: 'INFO'
      },
      description: 'Analyzes AWS Savings Plans recommendations using Cost Explorer APIs'
    });

    // Create EventBridge rule for monthly automated analysis
    const monthlyAnalysisRule = new events.Rule(this, 'MonthlySavingsPlansAnalysis', {
      schedule: events.Schedule.rate(cdk.Duration.days(30)),
      description: 'Monthly Savings Plans recommendations generation',
      enabled: true
    });

    // Add Lambda function as target for the EventBridge rule
    monthlyAnalysisRule.addTarget(new targets.LambdaFunction(savingsAnalyzerFunction, {
      event: events.RuleTargetInput.fromObject({
        lookback_days: 'SIXTY_DAYS',
        term_years: 'ONE_YEAR',
        payment_option: 'NO_UPFRONT',
        bucket_name: reportsBucket.bucketName
      })
    }));

    // Create CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'SavingsAnalyzerLogGroup', {
      logGroupName: `/aws/lambda/${savingsAnalyzerFunction.functionName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create CloudWatch Dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'SavingsPlansRecommendationsDashboard', {
      dashboardName: 'SavingsPlansRecommendations',
      defaultInterval: cdk.Duration.hours(1)
    });

    // Add Lambda function metrics to dashboard
    const lambdaMetrics = [
      savingsAnalyzerFunction.metricDuration({
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      savingsAnalyzerFunction.metricInvocations({
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      savingsAnalyzerFunction.metricErrors({
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      })
    ];

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Savings Plans Analyzer Performance',
        left: lambdaMetrics,
        width: 12,
        height: 6
      }),
      new cloudwatch.LogQueryWidget({
        title: 'Recent Analysis Logs',
        logGroups: [logGroup],
        query: 'fields @timestamp, @message | sort @timestamp desc | limit 50',
        width: 12,
        height: 6
      })
    );

    // Add S3 bucket metrics to dashboard
    const s3Metrics = [
      new cloudwatch.Metric({
        namespace: 'AWS/S3',
        metricName: 'BucketSizeBytes',
        dimensionsMap: {
          BucketName: reportsBucket.bucketName,
          StorageType: 'StandardStorage'
        },
        statistic: 'Average',
        period: cdk.Duration.days(1)
      }),
      new cloudwatch.Metric({
        namespace: 'AWS/S3',
        metricName: 'NumberOfObjects',
        dimensionsMap: {
          BucketName: reportsBucket.bucketName,
          StorageType: 'AllStorageTypes'
        },
        statistic: 'Average',
        period: cdk.Duration.days(1)
      })
    ];

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'S3 Storage Metrics',
        left: s3Metrics,
        width: 12,
        height: 6
      })
    );

    // Stack outputs
    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: savingsAnalyzerFunction.functionName,
      description: 'Name of the Savings Plans analyzer Lambda function'
    });

    new cdk.CfnOutput(this, 'S3BucketName', {
      value: reportsBucket.bucketName,
      description: 'Name of the S3 bucket storing cost recommendations'
    });

    new cdk.CfnOutput(this, 'S3BucketArn', {
      value: reportsBucket.bucketArn,
      description: 'ARN of the S3 bucket storing cost recommendations'
    });

    new cdk.CfnOutput(this, 'EventBridgeRuleName', {
      value: monthlyAnalysisRule.ruleName,
      description: 'Name of the EventBridge rule for monthly analysis'
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboardURL', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for monitoring'
    });

    new cdk.CfnOutput(this, 'IAMRoleArn', {
      value: lambdaRole.roleArn,
      description: 'ARN of the IAM role used by the Lambda function'
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'SavingsPlansRecommendations');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'CostOptimization');
    cdk.Tags.of(this).add('Purpose', 'AutomatedCostAnalysis');
  }
}

// Create the CDK app
const app = new cdk.App();

// Deploy the stack
new SavingsPlansRecommendationsStack(app, 'SavingsPlansRecommendationsStack', {
  description: 'Stack for automated AWS Savings Plans recommendations using Cost Explorer APIs',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  }
});

// Add stack-level tags
cdk.Tags.of(app).add('Application', 'SavingsPlansRecommendations');
cdk.Tags.of(app).add('DeployedBy', 'CDK');
cdk.Tags.of(app).add('Version', '1.0.0');