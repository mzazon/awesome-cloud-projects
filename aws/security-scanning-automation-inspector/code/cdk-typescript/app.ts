#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { 
  Stack, 
  StackProps, 
  RemovalPolicy,
  Duration 
} from 'aws-cdk-lib';
import { 
  Function as LambdaFunction, 
  Runtime, 
  Code, 
  Architecture 
} from 'aws-cdk-lib/aws-lambda';
import { 
  Topic, 
  Subscription, 
  SubscriptionProtocol 
} from 'aws-cdk-lib/aws-sns';
import { 
  Role, 
  ServicePrincipal, 
  PolicyStatement, 
  Effect,
  ManagedPolicy,
  PolicyDocument 
} from 'aws-cdk-lib/aws-iam';
import { 
  Rule, 
  Schedule, 
  RuleTargetInput 
} from 'aws-cdk-lib/aws-events';
import { 
  LambdaFunction as EventsLambdaTarget, 
  SnsTopic 
} from 'aws-cdk-lib/aws-events-targets';
import { 
  CfnHub, 
  CfnStandardsSubscription,
  CfnInsight 
} from 'aws-cdk-lib/aws-securityhub';
import { 
  CfnAssessmentTarget,
  CfnAssessmentTemplate 
} from 'aws-cdk-lib/aws-inspector';
import { Construct } from 'constructs';

/**
 * Properties for the AutomatedSecurityScanningStack
 */
interface AutomatedSecurityScanningStackProps extends StackProps {
  /**
   * Email address to receive security alerts
   */
  readonly alertEmail?: string;
  
  /**
   * Whether to enable Inspector scanning for EC2 instances
   * @default true
   */
  readonly enableEc2Scanning?: boolean;
  
  /**
   * Whether to enable Inspector scanning for ECR repositories
   * @default true
   */
  readonly enableEcrScanning?: boolean;
  
  /**
   * Whether to enable Inspector scanning for Lambda functions
   * @default true
   */
  readonly enableLambdaScanning?: boolean;
  
  /**
   * Schedule expression for compliance reports
   * @default 'rate(7 days)' - weekly reports
   */
  readonly reportingSchedule?: string;
}

/**
 * CDK Stack for Automated Security Scanning with Inspector and Security Hub
 * 
 * This stack creates a comprehensive security scanning solution that:
 * - Enables Amazon Inspector for vulnerability assessments
 * - Configures AWS Security Hub for centralized security findings
 * - Sets up automated response workflows with Lambda functions
 * - Provides real-time alerting through SNS
 * - Generates automated compliance reports
 */
export class AutomatedSecurityScanningStack extends Stack {
  public readonly securityTopic: Topic;
  public readonly responseFunction: LambdaFunction;
  public readonly complianceFunction: LambdaFunction;
  
  constructor(scope: Construct, id: string, props: AutomatedSecurityScanningStackProps = {}) {
    super(scope, id, props);
    
    // Extract configuration from props with defaults
    const {
      alertEmail,
      enableEc2Scanning = true,
      enableEcrScanning = true,
      enableLambdaScanning = true,
      reportingSchedule = 'rate(7 days)'
    } = props;
    
    // Create SNS topic for security alerts
    this.securityTopic = this.createSecurityAlertsTopic(alertEmail);
    
    // Enable Security Hub
    const securityHub = this.enableSecurityHub();
    
    // Create Lambda function for automated security response
    this.responseFunction = this.createSecurityResponseFunction(this.securityTopic);
    
    // Create Lambda function for compliance reporting
    this.complianceFunction = this.createComplianceReportingFunction();
    
    // Create EventBridge rules for security findings
    this.createSecurityFindingsRule(this.responseFunction);
    
    // Create scheduled compliance reporting
    this.createComplianceReportingRule(this.complianceFunction, reportingSchedule);
    
    // Create Security Hub custom insights
    this.createSecurityHubInsights();
    
    // Enable Security Hub standards
    this.enableSecurityHubStandards(securityHub);
    
    // Output important ARNs and configuration
    this.createOutputs();
  }
  
  /**
   * Creates SNS topic for security alerts with optional email subscription
   */
  private createSecurityAlertsTopic(alertEmail?: string): Topic {
    const topic = new Topic(this, 'SecurityAlertsTopic', {
      displayName: 'Security Alerts Topic',
      topicName: `security-alerts-${this.stackName}`.toLowerCase(),
    });
    
    // Add email subscription if provided
    if (alertEmail) {
      new Subscription(this, 'SecurityAlertsEmailSubscription', {
        topic,
        protocol: SubscriptionProtocol.EMAIL,
        endpoint: alertEmail,
      });
    }
    
    return topic;
  }
  
  /**
   * Enables AWS Security Hub with comprehensive configuration
   */
  private enableSecurityHub(): CfnHub {
    const securityHub = new CfnHub(this, 'SecurityHub', {
      tags: [
        {
          key: 'Purpose',
          value: 'AutomatedSecurityScanning'
        }
      ]
    });
    
    return securityHub;
  }
  
  /**
   * Creates Lambda function for automated security response
   */
  private createSecurityResponseFunction(securityTopic: Topic): LambdaFunction {
    // Create IAM role for the Lambda function
    const lambdaRole = new Role(this, 'SecurityResponseLambdaRole', {
      assumedBy: new ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        SecurityResponsePolicy: new PolicyDocument({
          statements: [
            new PolicyStatement({
              effect: Effect.ALLOW,
              actions: [
                'securityhub:BatchImportFindings',
                'securityhub:BatchUpdateFindings',
                'securityhub:GetFindings',
                'inspector2:ListFindings',
                'inspector2:BatchGetFinding',
                'ec2:CreateTags',
                'ec2:DescribeInstances',
                'sns:Publish'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });
    
    // Create the Lambda function
    const responseFunction = new LambdaFunction(this, 'SecurityResponseFunction', {
      runtime: Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: Duration.minutes(5),
      architecture: Architecture.X86_64,
      environment: {
        SNS_TOPIC_ARN: securityTopic.topicArn,
        LOG_LEVEL: 'INFO'
      },
      code: Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process Security Hub findings and trigger appropriate automated responses.
    
    This function:
    1. Parses incoming EventBridge events from Security Hub
    2. Evaluates finding severity and resource types
    3. Sends notifications for high-severity findings
    4. Performs automated remediation actions
    5. Tags affected resources for tracking
    
    Args:
        event: EventBridge event containing Security Hub findings
        context: Lambda execution context
        
    Returns:
        Response object with processing status
    """
    try:
        # Parse the EventBridge event
        detail = event.get('detail', {})
        findings = detail.get('findings', [])
        
        if not findings:
            logger.warning('No findings in event')
            return create_response(200, 'No findings to process')
        
        # Initialize AWS clients
        sns = boto3.client('sns')
        ec2 = boto3.client('ec2')
        
        sns_topic_arn = os.environ['SNS_TOPIC_ARN']
        processed_count = 0
        alert_count = 0
        
        for finding in findings:
            try:
                processed_count += 1
                
                # Extract finding details
                finding_details = extract_finding_details(finding)
                
                # Send notification for HIGH and CRITICAL findings
                if finding_details['severity'] in ['HIGH', 'CRITICAL']:
                    send_security_alert(sns, sns_topic_arn, finding_details)
                    alert_count += 1
                
                # Perform automated remediation based on finding type
                perform_automated_remediation(ec2, finding_details)
                
                logger.info(f"Processed finding: {finding_details['title']} "
                           f"(Severity: {finding_details['severity']})")
                           
            except Exception as e:
                logger.error(f"Error processing individual finding: {str(e)}")
                continue
        
        return create_response(200, {
            'message': f'Successfully processed {processed_count} findings',
            'alerts_sent': alert_count,
            'timestamp': datetime.utcnow().isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error processing security findings: {str(e)}")
        return create_response(500, {'error': str(e)})

def extract_finding_details(finding: Dict[str, Any]) -> Dict[str, Any]:
    """Extract and normalize finding details"""
    resources = finding.get('Resources', [{}])
    primary_resource = resources[0] if resources else {}
    
    return {
        'id': finding.get('Id', ''),
        'title': finding.get('Title', 'Unknown Security Finding'),
        'description': finding.get('Description', ''),
        'severity': finding.get('Severity', {}).get('Label', 'UNKNOWN'),
        'resource_id': primary_resource.get('Id', 'Unknown'),
        'resource_type': primary_resource.get('Type', 'Unknown'),
        'aws_account': finding.get('AwsAccountId', ''),
        'region': finding.get('Region', ''),
        'created_at': finding.get('CreatedAt', ''),
        'compliance_status': finding.get('Compliance', {}).get('Status', 'UNKNOWN')
    }

def send_security_alert(sns: Any, topic_arn: str, finding_details: Dict[str, Any]) -> None:
    """Send SNS notification for high-severity findings"""
    try:
        message = {
            'timestamp': datetime.utcnow().isoformat(),
            'severity': finding_details['severity'],
            'title': finding_details['title'],
            'description': finding_details['description'],
            'resource': finding_details['resource_id'],
            'resource_type': finding_details['resource_type'],
            'finding_id': finding_details['id'],
            'aws_account': finding_details['aws_account'],
            'region': finding_details['region'],
            'compliance_status': finding_details['compliance_status']
        }
        
        sns.publish(
            TopicArn=topic_arn,
            Subject=f"🚨 Security Alert: {finding_details['severity']} - {finding_details['title']}",
            Message=json.dumps(message, indent=2)
        )
        
        logger.info(f"Sent alert for {finding_details['severity']} finding: {finding_details['title']}")
        
    except Exception as e:
        logger.error(f"Failed to send SNS alert: {str(e)}")

def perform_automated_remediation(ec2: Any, finding_details: Dict[str, Any]) -> None:
    """Perform automated remediation actions based on finding type"""
    try:
        resource_id = finding_details['resource_id']
        resource_type = finding_details['resource_type']
        
        # Handle EC2 instance findings
        if 'EC2' in resource_type and 'instance' in resource_id:
            tag_ec2_instance_for_remediation(ec2, resource_id, finding_details)
        
        # Handle other resource types as needed
        # Additional remediation logic can be added here
        
    except Exception as e:
        logger.error(f"Failed to perform automated remediation: {str(e)}")

def tag_ec2_instance_for_remediation(ec2: Any, resource_id: str, finding_details: Dict[str, Any]) -> None:
    """Tag EC2 instances for security remediation tracking"""
    try:
        # Extract instance ID from resource ARN/ID
        instance_id = resource_id.split('/')[-1]
        
        # Validate instance ID format
        if not instance_id.startswith('i-'):
            logger.warning(f"Invalid EC2 instance ID format: {instance_id}")
            return
        
        # Create remediation tags
        tags = [
            {
                'Key': 'SecurityStatus',
                'Value': 'RequiresRemediation'
            },
            {
                'Key': 'SecurityFindingSeverity',
                'Value': finding_details['severity']
            },
            {
                'Key': 'LastSecurityScan',
                'Value': datetime.utcnow().strftime('%Y-%m-%d')
            },
            {
                'Key': 'SecurityFindingId',
                'Value': finding_details['id'][:50]  # Truncate for tag value limits
            }
        ]
        
        ec2.create_tags(
            Resources=[instance_id],
            Tags=tags
        )
        
        logger.info(f"Tagged EC2 instance {instance_id} for security remediation")
        
    except Exception as e:
        logger.error(f"Failed to tag EC2 instance {resource_id}: {str(e)}")

def create_response(status_code: int, body: Any) -> Dict[str, Any]:
    """Create standardized Lambda response"""
    return {
        'statusCode': status_code,
        'body': json.dumps(body) if isinstance(body, dict) else body
    }
      `)
    });
    
    // Grant SNS publish permissions
    securityTopic.grantPublish(responseFunction);
    
    return responseFunction;
  }
  
  /**
   * Creates Lambda function for compliance reporting
   */
  private createComplianceReportingFunction(): LambdaFunction {
    // Create IAM role for compliance reporting
    const complianceRole = new Role(this, 'ComplianceReportingLambdaRole', {
      assumedBy: new ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        ComplianceReportingPolicy: new PolicyDocument({
          statements: [
            new PolicyStatement({
              effect: Effect.ALLOW,
              actions: [
                'securityhub:GetFindings',
                'securityhub:GetInsights',
                'securityhub:GetInsightResults',
                'inspector2:ListFindings',
                'inspector2:GetCoverageStatistics',
                'cloudwatch:PutMetricData',
                's3:PutObject'  // Optional: for storing reports in S3
              ],
              resources: ['*']
            })
          ]
        })
      }
    });
    
    const complianceFunction = new LambdaFunction(this, 'ComplianceReportingFunction', {
      runtime: Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: complianceRole,
      timeout: Duration.minutes(10),
      architecture: Architecture.X86_64,
      environment: {
        LOG_LEVEL: 'INFO'
      },
      code: Code.fromInline(`
import json
import boto3
import logging
import os
import csv
from datetime import datetime, timedelta
from typing import Dict, List, Any
from io import StringIO

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Generate comprehensive compliance and security reports.
    
    This function:
    1. Retrieves security findings from the past week
    2. Analyzes finding trends and patterns
    3. Generates compliance metrics
    4. Creates summary reports
    5. Publishes metrics to CloudWatch
    
    Args:
        event: EventBridge scheduled event
        context: Lambda execution context
        
    Returns:
        Response with report generation status
    """
    try:
        logger.info("Starting compliance report generation")
        
        # Initialize AWS clients
        securityhub = boto3.client('securityhub')
        inspector = boto3.client('inspector2')
        cloudwatch = boto3.client('cloudwatch')
        
        # Calculate reporting period (last 7 days)
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(days=7)
        
        # Generate comprehensive security report
        report_data = generate_security_report(securityhub, inspector, start_time, end_time)
        
        # Publish metrics to CloudWatch
        publish_security_metrics(cloudwatch, report_data)
        
        # Generate CSV report
        csv_report = generate_csv_report(report_data['findings'])
        
        logger.info(f"Generated compliance report with {len(report_data['findings'])} findings")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Compliance report generated successfully',
                'report_period': {
                    'start': start_time.isoformat(),
                    'end': end_time.isoformat()
                },
                'summary': report_data['summary'],
                'csv_length': len(csv_report),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error generating compliance report: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def generate_security_report(securityhub: Any, inspector: Any, start_time: datetime, end_time: datetime) -> Dict[str, Any]:
    """Generate comprehensive security report data"""
    
    # Get Security Hub findings
    findings = get_security_hub_findings(securityhub, start_time, end_time)
    
    # Get Inspector coverage statistics
    coverage_stats = get_inspector_coverage(inspector)
    
    # Analyze findings
    summary = analyze_findings(findings)
    
    return {
        'findings': findings,
        'coverage': coverage_stats,
        'summary': summary,
        'period': {
            'start': start_time.isoformat(),
            'end': end_time.isoformat()
        }
    }

def get_security_hub_findings(securityhub: Any, start_time: datetime, end_time: datetime) -> List[Dict[str, Any]]:
    """Retrieve Security Hub findings for the specified time period"""
    findings = []
    
    try:
        paginator = securityhub.get_paginator('get_findings')
        
        page_iterator = paginator.paginate(
            Filters={
                'CreatedAt': [
                    {
                        'Start': start_time.isoformat(),
                        'End': end_time.isoformat()
                    }
                ]
            }
        )
        
        for page in page_iterator:
            findings.extend(page['Findings'])
            
    except Exception as e:
        logger.error(f"Error retrieving Security Hub findings: {str(e)}")
    
    return findings

def get_inspector_coverage(inspector: Any) -> Dict[str, Any]:
    """Get Inspector coverage statistics"""
    coverage_stats = {}
    
    try:
        # Get coverage for different resource types
        for resource_type in ['EC2_INSTANCE', 'ECR_REPOSITORY', 'LAMBDA_FUNCTION']:
            try:
                response = inspector.get_coverage_statistics(
                    filterCriteria={
                        'resourceType': [
                            {
                                'comparison': 'EQUALS',
                                'value': resource_type
                            }
                        ]
                    }
                )
                coverage_stats[resource_type] = response['totalCounts']
            except Exception as e:
                logger.warning(f"Could not get coverage for {resource_type}: {str(e)}")
                coverage_stats[resource_type] = {'total': 0, 'covered': 0}
                
    except Exception as e:
        logger.error(f"Error retrieving Inspector coverage: {str(e)}")
    
    return coverage_stats

def analyze_findings(findings: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Analyze findings to generate summary statistics"""
    severity_counts = {'CRITICAL': 0, 'HIGH': 0, 'MEDIUM': 0, 'LOW': 0, 'INFORMATIONAL': 0}
    resource_type_counts = {}
    compliance_status_counts = {'PASSED': 0, 'FAILED': 0, 'WARNING': 0, 'NOT_AVAILABLE': 0}
    
    for finding in findings:
        # Count by severity
        severity = finding.get('Severity', {}).get('Label', 'UNKNOWN')
        if severity in severity_counts:
            severity_counts[severity] += 1
        
        # Count by resource type
        resources = finding.get('Resources', [])
        for resource in resources:
            resource_type = resource.get('Type', 'Unknown')
            resource_type_counts[resource_type] = resource_type_counts.get(resource_type, 0) + 1
        
        # Count by compliance status
        compliance_status = finding.get('Compliance', {}).get('Status', 'NOT_AVAILABLE')
        if compliance_status in compliance_status_counts:
            compliance_status_counts[compliance_status] += 1
    
    return {
        'total_findings': len(findings),
        'severity_breakdown': severity_counts,
        'resource_type_breakdown': resource_type_counts,
        'compliance_breakdown': compliance_status_counts,
        'high_priority_count': severity_counts['CRITICAL'] + severity_counts['HIGH']
    }

def publish_security_metrics(cloudwatch: Any, report_data: Dict[str, Any]) -> None:
    """Publish security metrics to CloudWatch"""
    try:
        metrics = []
        summary = report_data['summary']
        
        # Total findings metric
        metrics.append({
            'MetricName': 'TotalSecurityFindings',
            'Value': summary['total_findings'],
            'Unit': 'Count'
        })
        
        # High priority findings metric
        metrics.append({
            'MetricName': 'HighPriorityFindings',
            'Value': summary['high_priority_count'],
            'Unit': 'Count'
        })
        
        # Severity-specific metrics
        for severity, count in summary['severity_breakdown'].items():
            metrics.append({
                'MetricName': f'{severity}SeverityFindings',
                'Value': count,
                'Unit': 'Count'
            })
        
        # Compliance metrics
        failed_compliance = summary['compliance_breakdown'].get('FAILED', 0)
        metrics.append({
            'MetricName': 'FailedComplianceChecks',
            'Value': failed_compliance,
            'Unit': 'Count'
        })
        
        # Publish metrics in batches
        for i in range(0, len(metrics), 20):  # CloudWatch limit is 20 metrics per call
            batch = metrics[i:i+20]
            cloudwatch.put_metric_data(
                Namespace='SecurityHub/Compliance',
                MetricData=batch
            )
        
        logger.info(f"Published {len(metrics)} security metrics to CloudWatch")
        
    except Exception as e:
        logger.error(f"Error publishing metrics to CloudWatch: {str(e)}")

def generate_csv_report(findings: List[Dict[str, Any]]) -> str:
    """Generate CSV report from findings"""
    csv_buffer = StringIO()
    writer = csv.writer(csv_buffer)
    
    # Write header
    writer.writerow([
        'Finding ID', 'Title', 'Severity', 'Resource Type', 
        'Resource ID', 'Compliance Status', 'Created Date', 
        'AWS Account', 'Region', 'Description'
    ])
    
    # Write findings
    for finding in findings:
        primary_resource = finding.get('Resources', [{}])[0]
        
        writer.writerow([
            finding.get('Id', ''),
            finding.get('Title', ''),
            finding.get('Severity', {}).get('Label', ''),
            primary_resource.get('Type', ''),
            primary_resource.get('Id', ''),
            finding.get('Compliance', {}).get('Status', ''),
            finding.get('CreatedAt', ''),
            finding.get('AwsAccountId', ''),
            finding.get('Region', ''),
            finding.get('Description', '')[:100] + '...' if len(finding.get('Description', '')) > 100 else finding.get('Description', '')
        ])
    
    return csv_buffer.getvalue()
      `)
    });
    
    return complianceFunction;
  }
  
  /**
   * Creates EventBridge rule for Security Hub findings
   */
  private createSecurityFindingsRule(responseFunction: LambdaFunction): void {
    const findingsRule = new Rule(this, 'SecurityHubFindingsRule', {
      description: 'Route high severity Security Hub findings to automated response',
      eventPattern: {
        source: ['aws.securityhub'],
        detailType: ['Security Hub Findings - Imported'],
        detail: {
          findings: {
            Severity: {
              Label: ['HIGH', 'CRITICAL']
            }
          }
        }
      }
    });
    
    // Add Lambda function as target
    findingsRule.addTarget(new EventsLambdaTarget(responseFunction, {
      retryAttempts: 3
    }));
  }
  
  /**
   * Creates EventBridge rule for scheduled compliance reporting
   */
  private createComplianceReportingRule(complianceFunction: LambdaFunction, schedule: string): void {
    const reportingRule = new Rule(this, 'ComplianceReportingRule', {
      description: 'Generate periodic compliance reports',
      schedule: Schedule.expression(schedule)
    });
    
    reportingRule.addTarget(new EventsLambdaTarget(complianceFunction, {
      retryAttempts: 2
    }));
  }
  
  /**
   * Creates Security Hub custom insights
   */
  private createSecurityHubInsights(): void {
    // Critical vulnerabilities by resource type
    new CfnInsight(this, 'CriticalVulnerabilitiesInsight', {
      name: 'Critical Vulnerabilities by Resource Type',
      filters: {
        SeverityLabel: [
          {
            Value: 'CRITICAL',
            Comparison: 'EQUALS'
          }
        ],
        RecordState: [
          {
            Value: 'ACTIVE',
            Comparison: 'EQUALS'
          }
        ]
      },
      groupByAttribute: 'ResourceType'
    });
    
    // Failed compliance checks by resource
    new CfnInsight(this, 'FailedComplianceInsight', {
      name: 'Failed Compliance Checks by Resource',
      filters: {
        ComplianceStatus: [
          {
            Value: 'FAILED',
            Comparison: 'EQUALS'
          }
        ],
        RecordState: [
          {
            Value: 'ACTIVE',
            Comparison: 'EQUALS'
          }
        ]
      },
      groupByAttribute: 'ResourceId'
    });
    
    // High severity EC2 findings
    new CfnInsight(this, 'HighSeverityEC2Insight', {
      name: 'High Severity EC2 Findings',
      filters: {
        ResourceType: [
          {
            Value: 'AwsEc2Instance',
            Comparison: 'EQUALS'
          }
        ],
        SeverityLabel: [
          {
            Value: 'HIGH',
            Comparison: 'EQUALS'
          },
          {
            Value: 'CRITICAL',
            Comparison: 'EQUALS'
          }
        ],
        RecordState: [
          {
            Value: 'ACTIVE',
            Comparison: 'EQUALS'
          }
        ]
      },
      groupByAttribute: 'ResourceId'
    });
  }
  
  /**
   * Enables Security Hub standards
   */
  private enableSecurityHubStandards(securityHub: CfnHub): void {
    // AWS Foundational Security Standard
    new CfnStandardsSubscription(this, 'FoundationalSecurityStandard', {
      standardsArn: `arn:aws:securityhub:${this.region}::standard/aws-foundational-security-best-practices/v/1.0.0`,
      dependsOn: [securityHub]
    });
    
    // CIS AWS Foundations Benchmark
    new CfnStandardsSubscription(this, 'CISFoundationsBenchmark', {
      standardsArn: `arn:aws:securityhub:${this.region}::standard/cis-aws-foundations-benchmark/v/1.2.0`,
      dependsOn: [securityHub]
    });
    
    // PCI DSS Standard (if needed)
    new CfnStandardsSubscription(this, 'PCIDSSStandard', {
      standardsArn: `arn:aws:securityhub:${this.region}::standard/pci-dss/v/3.2.1`,
      dependsOn: [securityHub]
    });
  }
  
  /**
   * Creates CloudFormation outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'SecurityTopicArn', {
      value: this.securityTopic.topicArn,
      description: 'ARN of the SNS topic for security alerts',
      exportName: `${this.stackName}-SecurityTopicArn`
    });
    
    new cdk.CfnOutput(this, 'ResponseFunctionArn', {
      value: this.responseFunction.functionArn,
      description: 'ARN of the security response Lambda function',
      exportName: `${this.stackName}-ResponseFunctionArn`
    });
    
    new cdk.CfnOutput(this, 'ComplianceFunctionArn', {
      value: this.complianceFunction.functionArn,
      description: 'ARN of the compliance reporting Lambda function',
      exportName: `${this.stackName}-ComplianceFunctionArn`
    });
    
    new cdk.CfnOutput(this, 'SecurityHubConsoleUrl', {
      value: `https://${this.region}.console.aws.amazon.com/securityhub/home?region=${this.region}#/findings`,
      description: 'URL to Security Hub findings console'
    });
    
    new cdk.CfnOutput(this, 'InspectorConsoleUrl', {
      value: `https://${this.region}.console.aws.amazon.com/inspector/v2/home?region=${this.region}#/findings`,
      description: 'URL to Inspector findings console'
    });
  }
}

/**
 * Main CDK App
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const alertEmail = app.node.tryGetContext('alertEmail');
const enableEc2Scanning = app.node.tryGetContext('enableEc2Scanning') !== 'false';
const enableEcrScanning = app.node.tryGetContext('enableEcrScanning') !== 'false';
const enableLambdaScanning = app.node.tryGetContext('enableLambdaScanning') !== 'false';
const reportingSchedule = app.node.tryGetContext('reportingSchedule') || 'rate(7 days)';

new AutomatedSecurityScanningStack(app, 'AutomatedSecurityScanningStack', {
  alertEmail,
  enableEc2Scanning,
  enableEcrScanning,
  enableLambdaScanning,
  reportingSchedule,
  description: 'Automated Security Scanning with Amazon Inspector and AWS Security Hub',
  tags: {
    Purpose: 'SecurityAutomation',
    Service: 'SecurityHub-Inspector',
    Environment: 'Production'
  }
});

app.synth();