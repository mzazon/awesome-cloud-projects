#!/usr/bin/env python3
"""
Real-time Data Quality Monitoring with Deequ on EMR
This script performs comprehensive data quality analysis using Amazon Deequ
and integrates with AWS CloudWatch and SNS for monitoring and alerting.
"""

import sys
import json
import boto3
from datetime import datetime
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp, lit

# Initialize Spark session with Deequ
spark = SparkSession.builder \
    .appName("DeeQuDataQualityMonitor") \
    .config("spark.jars.packages", "com.amazon.deequ:deequ:${deequ_version}") \
    .config("spark.sql.adaptive.enabled", "true") \
    .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
    .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer") \
    .getOrCreate()

# Import Deequ classes
from pydeequ.analyzers import *
from pydeequ.checks import *
from pydeequ.verification import *
from pydeequ.suggestions import *

def publish_metrics_to_cloudwatch(metrics, bucket_name):
    """
    Publish data quality metrics to CloudWatch
    
    Args:
        metrics (dict): Dictionary of metric names and values
        bucket_name (str): S3 bucket name for metric dimension
    """
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        for metric_name, metric_value in metrics.items():
            # Clean up metric name for CloudWatch compatibility
            clean_metric_name = metric_name.replace(":", "_").replace("(", "_").replace(")", "_")
            
            cloudwatch.put_metric_data(
                Namespace='DataQuality/Deequ',
                MetricData=[
                    {
                        'MetricName': clean_metric_name,
                        'Value': float(metric_value) if isinstance(metric_value, (int, float)) else 1.0,
                        'Unit': 'Count',
                        'Dimensions': [
                            {
                                'Name': 'DataSource',
                                'Value': bucket_name
                            },
                            {
                                'Name': 'Environment',
                                'Value': 'EMR'
                            }
                        ],
                        'Timestamp': datetime.now()
                    }
                ]
            )
        
        print(f"✅ Published {len(metrics)} metrics to CloudWatch")
        
    except Exception as e:
        print(f"❌ Error publishing metrics to CloudWatch: {str(e)}")

def send_alert_if_needed(verification_result, sns_topic_arn):
    """
    Send SNS alert if data quality issues are found
    
    Args:
        verification_result: Deequ verification result object
        sns_topic_arn (str): SNS topic ARN for alerts
    """
    try:
        failed_checks = []
        
        for check_result in verification_result.checkResults:
            if check_result.status != CheckStatus.Success:
                failed_checks.append({
                    'check': str(check_result.check),
                    'status': str(check_result.status),
                    'constraint': str(check_result.constraint),
                    'message': getattr(check_result, 'message', 'No message available')
                })
        
        if failed_checks:
            sns = boto3.client('sns')
            
            # Create detailed alert message
            alert_message = {
                'timestamp': datetime.now().isoformat(),
                'alert_type': 'DATA_QUALITY_FAILURE',
                'severity': 'HIGH' if len(failed_checks) > 3 else 'MEDIUM',
                'total_failed_checks': len(failed_checks),
                'failed_checks': failed_checks[:5],  # Limit to first 5 failures
                'summary': f"{len(failed_checks)} data quality checks failed",
                'recommended_action': 'Review data source and investigate quality issues'
            }
            
            # Publish to SNS
            sns.publish(
                TopicArn=sns_topic_arn,
                Message=json.dumps(alert_message, indent=2),
                Subject=f'🚨 Data Quality Alert - {len(failed_checks)} Issues Detected',
                MessageAttributes={
                    'AlertType': {
                        'DataType': 'String',
                        'StringValue': 'DATA_QUALITY'
                    },
                    'Severity': {
                        'DataType': 'String',
                        'StringValue': alert_message['severity']
                    }
                }
            )
            
            print(f"🚨 Sent alert for {len(failed_checks)} failed checks")
        else:
            print("✅ All data quality checks passed - no alerts sent")
            
    except Exception as e:
        print(f"❌ Error sending alert: {str(e)}")

def generate_quality_suggestions(df):
    """
    Generate data quality improvement suggestions using Deequ
    
    Args:
        df: Spark DataFrame to analyze
        
    Returns:
        dict: Quality suggestions and recommendations
    """
    try:
        suggestion_result = ConstraintSuggestionRunner(spark) \
            .onData(df) \
            .addConstraintRule(DEFAULT()) \
            .run()
        
        suggestions = []
        for constraint in suggestion_result['constraint_suggestions']:
            suggestions.append({
                'column': constraint.column_name,
                'constraint_type': constraint.constraint_name,
                'description': constraint.description,
                'code_for_constraint': constraint.code_for_constraint
            })
        
        return {
            'total_suggestions': len(suggestions),
            'suggestions': suggestions[:10]  # Limit to top 10 suggestions
        }
        
    except Exception as e:
        print(f"⚠️  Error generating quality suggestions: {str(e)}")
        return {'total_suggestions': 0, 'suggestions': []}

def analyze_data_profiling(df):
    """
    Perform comprehensive data profiling analysis
    
    Args:
        df: Spark DataFrame to profile
        
    Returns:
        dict: Profiling results
    """
    try:
        # Column profiling
        columns_info = []
        for col_name, col_type in df.dtypes:
            col_stats = df.select(col_name).describe().collect()
            columns_info.append({
                'column_name': col_name,
                'data_type': col_type,
                'stats': {row['summary']: row[col_name] for row in col_stats}
            })
        
        # Overall dataset statistics
        row_count = df.count()
        column_count = len(df.columns)
        
        return {
            'dataset_stats': {
                'total_rows': row_count,
                'total_columns': column_count,
                'memory_usage_mb': df.rdd.getStorageLevel().useMemory
            },
            'column_profiles': columns_info
        }
        
    except Exception as e:
        print(f"⚠️  Error in data profiling: {str(e)}")
        return {'dataset_stats': {}, 'column_profiles': []}

def main():
    """Main execution function"""
    
    # Validate command line arguments
    if len(sys.argv) != 4:
        print("Usage: deequ-quality-monitor.py <s3_bucket> <data_path> <sns_topic_arn>")
        print("Example: deequ-quality-monitor.py my-bucket s3://my-bucket/data/file.csv arn:aws:sns:us-east-1:123456789012:alerts")
        sys.exit(1)
    
    s3_bucket = sys.argv[1]
    data_path = sys.argv[2]
    sns_topic_arn = sys.argv[3]
    
    print(f"🔍 Starting data quality monitoring")
    print(f"📊 Data source: {data_path}")
    print(f"📦 S3 bucket: {s3_bucket}")
    print(f"📢 SNS topic: {sns_topic_arn}")
    
    try:
        # Read data with error handling
        print("📖 Reading data...")
        df = spark.read.option("header", "true").option("inferSchema", "true").csv(data_path)
        
        record_count = df.count()
        print(f"📋 Processing {record_count} records from {data_path}")
        
        if record_count == 0:
            print("⚠️  Warning: Dataset is empty")
            return
        
        # Show sample data
        print("📄 Sample data:")
        df.show(5, truncate=False)
        
        # Define comprehensive data quality checks
        print("🔬 Running data quality verification...")
        verification_result = VerificationSuite(spark) \
            .onData(df) \
            .addCheck(
                Check(spark, CheckLevel.Error, "Customer Data Quality Checks")
                .hasSize(lambda x: x > 0, "Dataset should not be empty")
                .isComplete("customer_id", "Customer ID should not be null")
                .isUnique("customer_id", "Customer ID should be unique")
                .isComplete("email", "Email should not be null")
                .containsEmail("email", "Email should have valid format")
                .isNonNegative("age", "Age should be non-negative")
                .isContainedIn("region", ["US", "EU", "APAC"], "Region should be valid")
                .hasCompleteness("income", lambda x: x > 0.9, "Income should be 90%+ complete")
            ) \
            .addCheck(
                Check(spark, CheckLevel.Warning, "Data Distribution Checks")
                .hasStandardDeviation("age", lambda x: x > 0, "Age should have variation")
                .hasDataType("customer_id", ConstrainableDataTypes.Integral, "Customer ID should be integer")
                .hasMean("age", lambda x: x > 18 and x < 100, "Average age should be reasonable")
            ) \
            .run()
        
        # Run comprehensive analysis for detailed metrics
        print("📈 Running statistical analysis...")
        analysis_result = AnalysisRunner(spark) \
            .onData(df) \
            .addAnalyzer(Size()) \
            .addAnalyzer(Completeness("customer_id")) \
            .addAnalyzer(Completeness("email")) \
            .addAnalyzer(Completeness("income")) \
            .addAnalyzer(Uniqueness("customer_id")) \
            .addAnalyzer(Mean("age")) \
            .addAnalyzer(StandardDeviation("age")) \
            .addAnalyzer(Minimum("age")) \
            .addAnalyzer(Maximum("age")) \
            .addAnalyzer(CountDistinct("region")) \
            .addAnalyzer(DataType("customer_id")) \
            .addAnalyzer(Entropy("region")) \
            .run()
        
        # Extract metrics from analysis results
        metrics = {}
        for analyzer_name, analyzer_result in analysis_result.analyzerContext.metricMap.items():
            if analyzer_result.value.isSuccess():
                metric_name = str(analyzer_name).replace(":", "_").replace("(", "_").replace(")", "_")
                metrics[metric_name] = analyzer_result.value.get()
        
        print(f"📊 Extracted {len(metrics)} quality metrics")
        
        # Perform data profiling
        print("🔍 Performing data profiling...")
        profiling_results = analyze_data_profiling(df)
        
        # Generate quality suggestions
        print("💡 Generating quality improvement suggestions...")
        suggestions = generate_quality_suggestions(df)
        
        # Publish metrics to CloudWatch
        print("☁️  Publishing metrics to CloudWatch...")
        publish_metrics_to_cloudwatch(metrics, s3_bucket)
        
        # Send alerts if needed
        print("🚨 Checking for quality issues...")
        send_alert_if_needed(verification_result, sns_topic_arn)
        
        # Save detailed results to S3
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        print("💾 Saving quality reports...")
        
        # Save verification results
        verification_df = VerificationResult.checkResultsAsDataFrame(spark, verification_result)
        verification_path = f"s3://{s3_bucket}/quality-reports/verification_{timestamp}"
        verification_df.coalesce(1).write.mode("overwrite").json(verification_path)
        
        # Save analysis results
        analysis_df = AnalysisResult.successMetricsAsDataFrame(spark, analysis_result)
        analysis_path = f"s3://{s3_bucket}/quality-reports/analysis_{timestamp}"
        analysis_df.coalesce(1).write.mode("overwrite").json(analysis_path)
        
        # Save profiling results
        profiling_df = spark.createDataFrame([profiling_results])
        profiling_path = f"s3://{s3_bucket}/quality-reports/profiling_{timestamp}"
        profiling_df.coalesce(1).write.mode("overwrite").json(profiling_path)
        
        # Save suggestions
        if suggestions['suggestions']:
            suggestions_df = spark.createDataFrame(suggestions['suggestions'])
            suggestions_path = f"s3://{s3_bucket}/quality-reports/suggestions_{timestamp}"
            suggestions_df.coalesce(1).write.mode("overwrite").json(suggestions_path)
        
        print("✅ Data quality monitoring completed successfully")
        print(f"📈 Metrics published to CloudWatch namespace: DataQuality/Deequ")
        print(f"📄 Reports saved to: s3://{s3_bucket}/quality-reports/")
        
        # Print summary of results
        print("\n" + "="*80)
        print("📋 VERIFICATION RESULTS SUMMARY")
        print("="*80)
        verification_df.show(truncate=False)
        
        print("\n" + "="*80)
        print("📊 ANALYSIS RESULTS SUMMARY")
        print("="*80)
        analysis_df.show(truncate=False)
        
        print("\n" + "="*80)
        print("💡 QUALITY IMPROVEMENT SUGGESTIONS")
        print("="*80)
        print(f"Total suggestions: {suggestions['total_suggestions']}")
        for i, suggestion in enumerate(suggestions['suggestions'][:5], 1):
            print(f"{i}. {suggestion['column']}: {suggestion['description']}")
        
        print("\n✅ Data quality monitoring job completed successfully! 🎉")
        
    except Exception as e:
        print(f"❌ Error in data quality monitoring: {str(e)}")
        
        # Send error alert
        try:
            sns = boto3.client('sns')
            error_alert = {
                'timestamp': datetime.now().isoformat(),
                'alert_type': 'MONITORING_ERROR',
                'severity': 'HIGH',
                'error_message': str(e),
                'data_path': data_path,
                'recommended_action': 'Check data format and EMR cluster logs'
            }
            
            sns.publish(
                TopicArn=sns_topic_arn,
                Message=json.dumps(error_alert, indent=2),
                Subject='🚨 Data Quality Monitoring Error'
            )
        except:
            pass  # Don't fail if error alert fails
        
        sys.exit(1)
    
    finally:
        # Clean up Spark session
        if 'spark' in locals():
            spark.stop()

if __name__ == "__main__":
    main()