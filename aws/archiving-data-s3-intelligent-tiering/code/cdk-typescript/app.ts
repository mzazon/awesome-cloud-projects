#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * CDK Stack for Sustainable Data Archiving with S3 Intelligent-Tiering
 * 
 * This stack implements a comprehensive sustainability-focused data archiving solution
 * using S3 Intelligent-Tiering, automated monitoring, and carbon footprint tracking.
 */
export class SustainableDataArchivingStack extends cdk.Stack {
  // Public properties for accessing created resources
  public readonly archiveBucket: s3.Bucket;
  public readonly analyticsBucket: s3.Bucket;
  public readonly sustainabilityFunction: lambda.Function;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate random suffix for unique resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // Create main archive bucket with sustainability-focused configuration
    this.archiveBucket = this.createArchiveBucket(randomSuffix);

    // Create analytics bucket for Storage Lens reports
    this.analyticsBucket = this.createAnalyticsBucket(randomSuffix);

    // Create IAM role for sustainability monitoring Lambda
    const lambdaRole = this.createLambdaRole();

    // Deploy sustainability monitoring Lambda function
    this.sustainabilityFunction = this.createSustainabilityMonitoringFunction(
      lambdaRole,
      this.archiveBucket.bucketName
    );

    // Configure automated monitoring with EventBridge
    this.setupAutomatedMonitoring();

    // Create CloudWatch dashboard for sustainability metrics
    this.dashboard = this.createSustainabilityDashboard();

    // Configure S3 Storage Lens for comprehensive analytics
    this.configureStorageLens();

    // Output important resource information
    this.createOutputs();
  }

  /**
   * Creates the main archive bucket with Intelligent-Tiering and lifecycle policies
   */
  private createArchiveBucket(randomSuffix: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'ArchiveBucket', {
      bucketName: `sustainable-archive-${randomSuffix}`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      
      // Configure lifecycle rules for sustainability optimization
      lifecycleRules: [
        {
          id: 'SustainabilityOptimization',
          enabled: true,
          // Immediately transition all objects to Intelligent-Tiering
          transitions: [
            {
              storageClass: s3.StorageClass.INTELLIGENT_TIERING,
              transitionAfter: cdk.Duration.days(0)
            }
          ],
          // Manage non-current versions for compliance and cost efficiency
          noncurrentVersionTransitions: [
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: cdk.Duration.days(90)
            }
          ],
          // Clean up incomplete multipart uploads
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(1),
          // Delete old versions after 1 year for cost optimization
          noncurrentVersionExpiration: cdk.Duration.days(365)
        }
      ],
      
      // Add sustainability-focused tags
      tags: {
        'Purpose': 'SustainableArchive',
        'Environment': 'Production',
        'CostOptimization': 'Enabled',
        'SustainabilityGoal': 'CarbonNeutral'
      },

      // Configure CORS for web applications
      cors: [
        {
          allowedMethods: [s3.HttpMethods.GET, s3.HttpMethods.PUT, s3.HttpMethods.POST],
          allowedOrigins: ['*'],
          allowedHeaders: ['*'],
          maxAge: 3000
        }
      ],

      // Enable event notifications for monitoring
      eventBridgeEnabled: true,
      
      // Configure intelligent tiering
      intelligentTieringConfigurations: [
        {
          id: 'SustainableArchiveConfig',
          status: s3.IntelligentTieringStatus.ENABLED,
          // Apply to all objects in the bucket
          prefix: '',
          // Enable archive access tiers for maximum cost savings
          optionalFields: [s3.IntelligentTieringOptionalField.BUCKET_KEY_STATUS]
        },
        {
          id: 'AdvancedSustainableConfig',
          status: s3.IntelligentTieringStatus.ENABLED,
          // Apply to long-term retention data
          prefix: 'long-term/',
          optionalFields: [s3.IntelligentTieringOptionalField.BUCKET_KEY_STATUS]
        }
      ],

      // Configure server access logging for compliance
      serverAccessLogsBucket: new s3.Bucket(this, 'AccessLogsBucket', {
        bucketName: `access-logs-${randomSuffix}`,
        blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
        encryption: s3.BucketEncryption.S3_MANAGED,
        lifecycleRules: [
          {
            id: 'DeleteOldLogs',
            enabled: true,
            expiration: cdk.Duration.days(90)
          }
        ]
      }),
      serverAccessLogsPrefix: 'access-logs/',

      // Configure inventory for detailed object tracking
      inventories: [
        {
          inventoryId: 'SustainabilityInventory',
          enabled: true,
          destination: {
            bucket: new s3.Bucket(this, 'InventoryBucket', {
              bucketName: `inventory-${randomSuffix}`,
              blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
              encryption: s3.BucketEncryption.S3_MANAGED
            })
          },
          frequency: s3.InventoryFrequency.DAILY,
          format: s3.InventoryFormat.CSV,
          includeObjectVersions: s3.InventoryObjectVersion.CURRENT,
          optionalFields: [
            s3.InventoryOptionalField.SIZE,
            s3.InventoryOptionalField.LAST_MODIFIED_DATE,
            s3.InventoryOptionalField.STORAGE_CLASS,
            s3.InventoryOptionalField.INTELLIGENT_TIERING_ACCESS_TIER
          ]
        }
      ]
    });

    return bucket;
  }

  /**
   * Creates analytics bucket for Storage Lens reports
   */
  private createAnalyticsBucket(randomSuffix: string): s3.Bucket {
    return new s3.Bucket(this, 'AnalyticsBucket', {
      bucketName: `archive-analytics-${randomSuffix}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldReports',
          enabled: true,
          expiration: cdk.Duration.days(365) // Keep reports for 1 year
        }
      ]
    });
  }

  /**
   * Creates IAM role for sustainability monitoring Lambda function
   */
  private createLambdaRole(): iam.Role {
    const role = new iam.Role(this, 'SustainabilityMonitorRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for sustainability monitoring Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    // Add custom permissions for sustainability monitoring
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetBucketTagging',
        's3:GetBucketLocation',
        's3:ListBucket',
        's3:GetObject',
        's3:GetStorageLensConfiguration',
        's3:ListStorageLensConfigurations',
        's3:GetBucketIntelligentTieringConfiguration',
        's3:GetBucketLifecycleConfiguration',
        's3:GetBucketInventoryConfiguration',
        'cloudwatch:GetMetricStatistics',
        'cloudwatch:ListMetrics',
        'cloudwatch:PutMetricData',
        'sns:Publish'
      ],
      resources: ['*']
    }));

    return role;
  }

  /**
   * Creates the sustainability monitoring Lambda function
   */
  private createSustainabilityMonitoringFunction(role: iam.Role, bucketName: string): lambda.Function {
    return new lambda.Function(this, 'SustainabilityMonitorFunction', {
      functionName: 'sustainability-archive-monitor',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      role: role,
      environment: {
        'ARCHIVE_BUCKET': bucketName
      },
      description: 'Monitors sustainability metrics and calculates carbon footprint for S3 archive bucket',
      
      // Lambda function code for sustainability monitoring
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    cloudwatch = boto3.client('cloudwatch')
    
    bucket_name = os.environ['ARCHIVE_BUCKET']
    
    try:
        # Get bucket tagging to identify sustainability goals
        tags_response = s3.get_bucket_tagging(Bucket=bucket_name)
        tags = {tag['Key']: tag['Value'] for tag in tags_response['TagSet']}
        
        # Calculate storage metrics
        storage_metrics = calculate_storage_efficiency(s3, bucket_name)
        
        # Estimate carbon footprint reduction
        carbon_metrics = calculate_carbon_impact(storage_metrics)
        
        # Publish custom CloudWatch metrics
        publish_sustainability_metrics(cloudwatch, storage_metrics, carbon_metrics)
        
        # Generate sustainability report
        report = generate_sustainability_report(storage_metrics, carbon_metrics, tags)
        
        print(f"Sustainability analysis completed: {json.dumps(report, default=str)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Sustainability analysis completed',
                'report': report
            }, default=decimal_default)
        }
        
    except Exception as e:
        print(f"Error in sustainability monitoring: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def calculate_storage_efficiency(s3, bucket_name):
    """Calculate storage efficiency metrics"""
    try:
        total_objects = 0
        total_size = 0
        
        # Use paginator to handle large buckets efficiently
        paginator = s3.get_paginator('list_objects_v2')
        
        for page in paginator.paginate(Bucket=bucket_name):
            if 'Contents' in page:
                for obj in page['Contents']:
                    total_objects += 1
                    total_size += obj['Size']
        
        return {
            'total_objects': total_objects,
            'total_size_gb': round(total_size / (1024**3), 2),
            'average_object_size_mb': round((total_size / total_objects) / (1024**2), 2) if total_objects > 0 else 0
        }
    except Exception as e:
        print(f"Error calculating storage metrics: {str(e)}")
        return {'total_objects': 0, 'total_size_gb': 0, 'average_object_size_mb': 0}

def calculate_carbon_impact(storage_metrics):
    """Estimate carbon footprint reduction through intelligent tiering"""
    # AWS sustainability estimates for carbon impact (simplified model)
    # Based on AWS Carbon Footprint Tool methodology
    total_size_gb = storage_metrics['total_size_gb']
    
    # Estimate tier distribution based on typical Intelligent-Tiering patterns
    estimated_standard = total_size_gb * 0.3  # 30% frequently accessed
    estimated_ia = total_size_gb * 0.4        # 40% infrequently accessed
    estimated_archive = total_size_gb * 0.3   # 30% archive tiers
    
    # Carbon intensity estimates (kg CO2e per GB per month)
    carbon_standard = estimated_standard * 0.000385
    carbon_ia = estimated_ia * 0.000308
    carbon_archive = estimated_archive * 0.000077
    
    total_carbon = carbon_standard + carbon_ia + carbon_archive
    carbon_baseline = total_size_gb * 0.000385  # All in standard tier
    carbon_saved = carbon_baseline - total_carbon
    
    return {
        'estimated_monthly_carbon_kg': round(total_carbon, 4),
        'estimated_monthly_savings_kg': round(carbon_saved, 4),
        'carbon_reduction_percentage': round((carbon_saved / carbon_baseline) * 100, 1) if carbon_baseline > 0 else 0
    }

def publish_sustainability_metrics(cloudwatch, storage_metrics, carbon_metrics):
    """Publish sustainability metrics to CloudWatch"""
    metrics_data = [
        {
            'MetricName': 'TotalStorageGB',
            'Value': storage_metrics['total_size_gb'],
            'Unit': 'Count',
            'Timestamp': datetime.utcnow()
        },
        {
            'MetricName': 'EstimatedMonthlyCarbonKg',
            'Value': carbon_metrics['estimated_monthly_carbon_kg'],
            'Unit': 'Count',
            'Timestamp': datetime.utcnow()
        },
        {
            'MetricName': 'CarbonReductionPercentage',
            'Value': carbon_metrics['carbon_reduction_percentage'],
            'Unit': 'Percent',
            'Timestamp': datetime.utcnow()
        },
        {
            'MetricName': 'TotalObjects',
            'Value': storage_metrics['total_objects'],
            'Unit': 'Count',
            'Timestamp': datetime.utcnow()
        }
    ]
    
    cloudwatch.put_metric_data(
        Namespace='SustainableArchive',
        MetricData=metrics_data
    )

def generate_sustainability_report(storage_metrics, carbon_metrics, tags):
    """Generate comprehensive sustainability report"""
    return {
        'timestamp': datetime.utcnow().isoformat(),
        'sustainability_goal': tags.get('SustainabilityGoal', 'Not specified'),
        'storage_efficiency': storage_metrics,
        'environmental_impact': carbon_metrics,
        'recommendations': generate_recommendations(storage_metrics, carbon_metrics)
    }

def generate_recommendations(storage_metrics, carbon_metrics):
    """Generate actionable sustainability recommendations"""
    recommendations = []
    
    if storage_metrics['average_object_size_mb'] < 1:
        recommendations.append("Consider aggregating small objects for better storage efficiency")
    
    if carbon_metrics['carbon_reduction_percentage'] < 30:
        recommendations.append("Review access patterns to optimize tier transitions")
    
    if storage_metrics['total_objects'] > 10000:
        recommendations.append("Enable S3 Storage Lens for detailed analytics")
    
    recommendations.append("Monitor monthly sustainability metrics for continuous improvement")
    
    return recommendations

def decimal_default(obj):
    """JSON serializer for Decimal objects"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError
      `),

      // Configure CloudWatch Logs retention
      logRetention: logs.RetentionDays.ONE_MONTH
    });
  }

  /**
   * Sets up automated monitoring with EventBridge
   */
  private setupAutomatedMonitoring(): void {
    // Create EventBridge rule for daily sustainability monitoring
    const dailyRule = new events.Rule(this, 'SustainabilityDailyCheck', {
      description: 'Triggers daily sustainability metrics collection',
      schedule: events.Schedule.rate(cdk.Duration.days(1))
    });

    // Add Lambda function as target
    dailyRule.addTarget(new targets.LambdaFunction(this.sustainabilityFunction));

    // Create rule for weekly detailed analysis
    const weeklyRule = new events.Rule(this, 'SustainabilityWeeklyAnalysis', {
      description: 'Triggers weekly detailed sustainability analysis',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '8',
        weekDay: 'MON'
      })
    });

    weeklyRule.addTarget(new targets.LambdaFunction(this.sustainabilityFunction, {
      event: events.RuleTargetInput.fromObject({
        analysis_type: 'detailed',
        reporting_period: 'weekly'
      })
    }));
  }

  /**
   * Creates CloudWatch dashboard for sustainability metrics visualization
   */
  private createSustainabilityDashboard(): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'SustainabilityDashboard', {
      dashboardName: 'SustainableArchive-Metrics',
      defaultInterval: cdk.Duration.hours(24)
    });

    // Storage metrics widget
    const storageWidget = new cloudwatch.GraphWidget({
      title: 'Storage Metrics',
      width: 12,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'SustainableArchive',
          metricName: 'TotalStorageGB',
          statistic: 'Average',
          label: 'Total Storage (GB)'
        }),
        new cloudwatch.Metric({
          namespace: 'SustainableArchive',
          metricName: 'TotalObjects',
          statistic: 'Average',
          label: 'Total Objects'
        })
      ]
    });

    // Carbon footprint widget
    const carbonWidget = new cloudwatch.GraphWidget({
      title: 'Carbon Footprint Metrics',
      width: 12,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'SustainableArchive',
          metricName: 'EstimatedMonthlyCarbonKg',
          statistic: 'Average',
          label: 'Monthly Carbon (kg CO2e)'
        }),
        new cloudwatch.Metric({
          namespace: 'SustainableArchive',
          metricName: 'CarbonReductionPercentage',
          statistic: 'Average',
          label: 'Carbon Reduction %'
        })
      ]
    });

    // S3 storage class distribution widget
    const s3MetricsWidget = new cloudwatch.GraphWidget({
      title: 'S3 Storage Class Distribution',
      width: 24,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/S3',
          metricName: 'BucketSizeBytesStandardStorage',
          dimensionsMap: {
            'BucketName': this.archiveBucket.bucketName,
            'StorageType': 'StandardStorage'
          },
          statistic: 'Average',
          label: 'Standard Tier'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/S3',
          metricName: 'BucketSizeBytesStandardIAStorage',
          dimensionsMap: {
            'BucketName': this.archiveBucket.bucketName,
            'StorageType': 'StandardIAStorage'
          },
          statistic: 'Average',
          label: 'Infrequent Access Tier'
        })
      ]
    });

    // Lambda function metrics widget
    const lambdaWidget = new cloudwatch.GraphWidget({
      title: 'Sustainability Monitor Function',
      width: 12,
      height: 6,
      left: [
        this.sustainabilityFunction.metricInvocations({
          label: 'Invocations'
        }),
        this.sustainabilityFunction.metricErrors({
          label: 'Errors'
        })
      ],
      right: [
        this.sustainabilityFunction.metricDuration({
          label: 'Duration (ms)'
        })
      ]
    });

    // Add widgets to dashboard
    dashboard.addWidgets(storageWidget, carbonWidget);
    dashboard.addWidgets(s3MetricsWidget);
    dashboard.addWidgets(lambdaWidget);

    return dashboard;
  }

  /**
   * Configures S3 Storage Lens for comprehensive storage analytics
   */
  private configureStorageLens(): void {
    // Note: S3 Storage Lens configuration requires the s3control API
    // This is implemented through a custom resource for advanced configuration
    const storageLensConfig = new cdk.CustomResource(this, 'StorageLensConfig', {
      serviceToken: this.createStorageLensProvider().serviceToken,
      properties: {
        AccountId: this.account,
        ConfigId: 'SustainabilityMetrics',
        StorageLensConfiguration: {
          Id: 'SustainabilityMetrics',
          AccountLevel: {
            ActivityMetrics: {
              IsEnabled: true
            },
            BucketLevel: {
              ActivityMetrics: {
                IsEnabled: true
              }
            }
          },
          Include: {
            Buckets: [this.archiveBucket.bucketArn]
          },
          DataExport: {
            S3BucketDestination: {
              OutputSchemaVersion: 'V_1',
              AccountId: this.account,
              Arn: this.analyticsBucket.bucketArn,
              Format: 'CSV',
              Prefix: 'storage-lens-reports/'
            }
          },
          IsEnabled: true
        }
      }
    });

    // Ensure the analytics bucket is created before Storage Lens configuration
    storageLensConfig.node.addDependency(this.analyticsBucket);
  }

  /**
   * Creates a custom resource provider for S3 Storage Lens configuration
   */
  private createStorageLensProvider(): lambda.Function {
    const providerRole = new iam.Role(this, 'StorageLensProviderRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    providerRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:PutStorageLensConfiguration',
        's3:GetStorageLensConfiguration',
        's3:DeleteStorageLensConfiguration'
      ],
      resources: ['*']
    }));

    return new lambda.Function(this, 'StorageLensProvider', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.handler',
      role: providerRole,
      timeout: cdk.Duration.minutes(5),
      code: lambda.Code.fromInline(`
import boto3
import json
import cfnresponse

def handler(event, context):
    try:
        s3control = boto3.client('s3control')
        
        if event['RequestType'] == 'Create' or event['RequestType'] == 'Update':
            response = s3control.put_storage_lens_configuration(
                ConfigId=event['ResourceProperties']['ConfigId'],
                AccountId=event['ResourceProperties']['AccountId'],
                StorageLensConfiguration=event['ResourceProperties']['StorageLensConfiguration']
            )
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            
        elif event['RequestType'] == 'Delete':
            try:
                s3control.delete_storage_lens_configuration(
                    ConfigId=event['ResourceProperties']['ConfigId'],
                    AccountId=event['ResourceProperties']['AccountId']
                )
            except s3control.exceptions.NoSuchConfiguration:
                pass  # Already deleted
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            
    except Exception as e:
        print(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
      `)
    });
  }

  /**
   * Creates stack outputs for important resource information
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'ArchiveBucketName', {
      value: this.archiveBucket.bucketName,
      description: 'Name of the main archive bucket with Intelligent-Tiering'
    });

    new cdk.CfnOutput(this, 'ArchiveBucketArn', {
      value: this.archiveBucket.bucketArn,
      description: 'ARN of the main archive bucket'
    });

    new cdk.CfnOutput(this, 'AnalyticsBucketName', {
      value: this.analyticsBucket.bucketName,
      description: 'Name of the analytics bucket for Storage Lens reports'
    });

    new cdk.CfnOutput(this, 'SustainabilityFunctionName', {
      value: this.sustainabilityFunction.functionName,
      description: 'Name of the sustainability monitoring Lambda function'
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to the CloudWatch sustainability dashboard'
    });

    new cdk.CfnOutput(this, 'S3ConsoleUrl', {
      value: `https://s3.console.aws.amazon.com/s3/buckets/${this.archiveBucket.bucketName}`,
      description: 'URL to the S3 console for the archive bucket'
    });
  }
}

// Main CDK application
const app = new cdk.App();

// Deploy the sustainability stack
new SustainableDataArchivingStack(app, 'SustainableDataArchivingStack', {
  description: 'Sustainable Data Archiving Solution with S3 Intelligent-Tiering and carbon footprint monitoring',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  tags: {
    'Project': 'SustainableDataArchiving',
    'Purpose': 'CostOptimization',
    'Environment': 'Production',
    'SustainabilityGoal': 'CarbonNeutral'
  }
});

// Synthesize the CDK application
app.synth();