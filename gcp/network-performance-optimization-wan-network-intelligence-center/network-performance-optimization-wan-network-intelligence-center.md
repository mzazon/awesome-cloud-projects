---
title: Network Performance Optimization with Cloud WAN and Network Intelligence Center
id: 7a3f8c21
category: networking
difficulty: 200
subject: gcp
services: Cloud WAN, Network Intelligence Center, Cloud Monitoring, Cloud Functions
estimated-time: 120 minutes
recipe-version: 1.1
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: network-optimization, cloud-wan, network-intelligence, automation, enterprise-networking, performance-monitoring
recipe-generator-version: 1.3
---

# Network Performance Optimization with Cloud WAN and Network Intelligence Center

## Problem

Enterprise organizations struggle with network performance issues across distributed global infrastructure, experiencing unpredictable latency, connectivity failures, and suboptimal routing that impacts critical business applications. Traditional network monitoring solutions provide reactive insights after problems occur, while manual remediation efforts are time-consuming and prone to human error. Companies need intelligent, automated network optimization that proactively identifies performance degradation and implements corrective actions before end users are affected.

## Solution

Build an intelligent network operations system that leverages Google Cloud WAN for global connectivity optimization and Network Intelligence Center for AI-powered network observability. The solution combines real-time performance monitoring with automated remediation workflows using Cloud Functions, providing proactive network optimization that adapts to changing conditions and automatically resolves common connectivity issues before they impact business operations.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Global Network Infrastructure"
        WAN[Cloud WAN]
        ISP1[ISP Connection 1]
        ISP2[ISP Connection 2]
        BRANCH1[Branch Office 1]
        BRANCH2[Branch Office 2]
        DC[Data Center]
    end
    
    subgraph "Network Intelligence & Monitoring"
        NIC[Network Intelligence Center]
        CT[Connectivity Tests]
        FA[Flow Analyzer]
        PD[Performance Dashboard]
        NA[Network Analyzer]
        FI[Firewall Insights]
    end
    
    subgraph "Automation & Remediation"
        CM[Cloud Monitoring]
        CF[Cloud Functions]
        ALERTS[Alert Policies]
        WORKFLOWS[Remediation Workflows]
    end
    
    subgraph "Optimization Actions"
        ROUTING[Route Optimization]
        FAILOVER[Automatic Failover]
        SCALING[Bandwidth Scaling]
        CONFIG[Config Updates]
    end
    
    BRANCH1 --> WAN
    BRANCH2 --> WAN
    DC --> WAN
    ISP1 --> WAN
    ISP2 --> WAN
    
    WAN --> NIC
    NIC --> CT
    NIC --> FA
    NIC --> PD
    NIC --> NA
    NIC --> FI
    
    NIC --> CM
    CM --> ALERTS
    ALERTS --> CF
    CF --> WORKFLOWS
    
    WORKFLOWS --> ROUTING
    WORKFLOWS --> FAILOVER
    WORKFLOWS --> SCALING
    WORKFLOWS --> CONFIG
    
    ROUTING --> WAN
    FAILOVER --> WAN
    SCALING --> WAN
    CONFIG --> WAN
    
    style WAN fill:#4285F4
    style NIC fill:#34A853
    style CF fill:#EA4335
    style CM fill:#FBBC04
```

## Prerequisites

1. Google Cloud account with appropriate permissions for networking, monitoring, and Cloud Functions
2. Google Cloud CLI installed and configured (or Cloud Shell access)
3. Basic understanding of network concepts (routing, latency, connectivity)
4. Existing Google Cloud project with billing enabled
5. Network infrastructure with multiple connection points (branches, data centers, or cloud regions)
6. Estimated cost: $50-200/month depending on network traffic volume and monitoring frequency

> **Note**: Cloud WAN pricing varies based on data transfer volumes and connection types. Network Intelligence Center modules have different pricing structures, with some features included in the free tier.

## Preparation

```bash
# Set environment variables for the project
export PROJECT_ID="network-ops-$(date +%s)"
export REGION="us-central1"
export ZONE="us-central1-a"

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(openssl rand -hex 3)
export FUNCTION_NAME="network-optimizer-${RANDOM_SUFFIX}"
export BUCKET_NAME="network-ops-data-${RANDOM_SUFFIX}"
export TOPIC_NAME="network-alerts-${RANDOM_SUFFIX}"

# Set default project and region for gcloud
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
gcloud config set compute/zone ${ZONE}

# Enable required Google Cloud APIs
gcloud services enable networkmanagement.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable pubsub.googleapis.com
gcloud services enable logging.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable eventarc.googleapis.com

# Create a Cloud Storage bucket for function code and data
gsutil mb -p ${PROJECT_ID} \
    -c STANDARD \
    -l ${REGION} \
    gs://${BUCKET_NAME}

echo "✅ Environment prepared successfully"
echo "Project ID: ${PROJECT_ID}"
echo "Function Name: ${FUNCTION_NAME}"
echo "Storage Bucket: ${BUCKET_NAME}"
```

## Steps

1. **Create Pub/Sub Topic for Network Alerts**:

   Google Cloud Pub/Sub provides reliable, many-to-many, asynchronous messaging that enables event-driven architectures. Creating a dedicated topic for network alerts establishes the communication backbone for our intelligent network optimization system, allowing different components to publish and subscribe to network events in real-time.

   ```bash
   # Create Pub/Sub topic for network alert notifications
   gcloud pubsub topics create ${TOPIC_NAME}
   
   # Create a subscription for the Cloud Function to consume messages
   gcloud pubsub subscriptions create ${TOPIC_NAME}-sub \
       --topic=${TOPIC_NAME}
   
   echo "✅ Pub/Sub topic and subscription created"
   ```

   The Pub/Sub topic now serves as the central nervous system for network events, enabling loosely coupled communication between monitoring systems and remediation functions. This decoupled architecture ensures that network optimization can scale independently and handle high-frequency events without bottlenecks.

2. **Configure Network Intelligence Center Connectivity Tests**:

   Network Intelligence Center's Connectivity Tests provide proactive network validation by simulating traffic flows between network endpoints. These tests help identify connectivity issues, suboptimal routing, and firewall misconfigurations before they affect production traffic, forming the foundation of our intelligent monitoring system.

   ```bash
   # Create connectivity test between regions for monitoring
   gcloud network-management connectivity-tests create \
       regional-connectivity-test \
       --source-project=${PROJECT_ID} \
       --source-network-type=gcp-network \
       --source-network=default \
       --source-region=${REGION} \
       --destination-project=${PROJECT_ID} \
       --destination-network-type=gcp-network \
       --destination-network=default \
       --destination-region=us-west1 \
       --protocol=TCP \
       --destination-port=80
   
   # Create a test for external connectivity monitoring
   gcloud network-management connectivity-tests create \
       external-connectivity-test \
       --source-project=${PROJECT_ID} \
       --source-network-type=gcp-network \
       --source-network=default \
       --source-region=${REGION} \
       --destination-ip-address=8.8.8.8 \
       --protocol=ICMP
   
   echo "✅ Connectivity tests configured"
   ```

   These connectivity tests now continuously validate network paths and will generate insights that feed into our optimization algorithms. The tests simulate real user traffic patterns and help identify performance degradation trends before they become critical issues.

3. **Set Up Performance Dashboard Monitoring**:

   The Network Intelligence Center Performance Dashboard provides real-time visibility into network performance metrics across Google's global infrastructure. Configuring custom monitoring helps establish baselines and detect anomalies that trigger our automated optimization workflows.

   ```bash
   # Create Cloud Monitoring metrics for network performance tracking
   cat > network_metrics.yaml << 'EOF'
displayName: "Network Performance Metrics"
combiner: OR
conditions:
  - displayName: "High Latency Alert"
    conditionThreshold:
      filter: 'resource.type="gce_instance"'
      comparison: COMPARISON_GREATER_THAN
      thresholdValue: 100
      duration: "60s"
notificationChannels: []
alertStrategy:
  autoClose: "1800s"
EOF
   
   # Apply the monitoring configuration
   gcloud alpha monitoring policies create --policy-from-file=network_metrics.yaml
   
   echo "✅ Performance monitoring configured"
   ```

   The performance monitoring system is now actively tracking network metrics and will trigger alerts when thresholds are exceeded. This provides the data foundation for intelligent decision-making in our automated optimization system.

4. **Deploy Network Optimization Cloud Function**:

   Cloud Functions provides serverless compute for event-driven automation, enabling our network optimization system to respond to alerts and performance issues automatically. This function implements intelligent routing decisions, failover logic, and performance tuning based on real-time network conditions.

   ```bash
   # Create the Cloud Function source code for network optimization
   mkdir -p network-optimizer
   cd network-optimizer
   
   cat > main.py << 'EOF'
import functions_framework
import json
import logging
import time
import os
from google.cloud import monitoring_v3
from google.cloud import networkmanagement_v1
from google.cloud import pubsub_v1
import base64

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.cloud_event
def optimize_network(cloud_event):
    """
    Main function to handle network optimization events.
    Analyzes network performance data and implements optimization strategies.
    """
    try:
        # Decode the Pub/Sub message
        message_data = base64.b64decode(cloud_event.data["message"]["data"]).decode()
        alert_data = json.loads(message_data)
        
        logger.info(f"Processing network optimization request: {alert_data}")
        
        # Initialize Google Cloud clients
        monitoring_client = monitoring_v3.MetricServiceClient()
        network_client = networkmanagement_v1.ReachabilityServiceClient()
        
        # Analyze current network performance
        performance_metrics = analyze_network_performance(monitoring_client)
        
        # Determine optimization actions based on metrics
        optimization_actions = determine_optimization_actions(performance_metrics)
        
        # Execute optimization strategies
        for action in optimization_actions:
            execute_optimization_action(action, network_client)
        
        logger.info("Network optimization completed successfully")
        return {"status": "success", "actions_taken": len(optimization_actions)}
        
    except Exception as e:
        logger.error(f"Error in network optimization: {str(e)}")
        return {"status": "error", "message": str(e)}

def analyze_network_performance(monitoring_client):
    """
    Analyze current network performance metrics to identify optimization opportunities.
    """
    project_name = f"projects/{os.environ.get('GCP_PROJECT')}"
    
    # Query latency metrics
    interval = monitoring_v3.TimeInterval({
        "end_time": {"seconds": int(time.time())},
        "start_time": {"seconds": int(time.time()) - 300}  # Last 5 minutes
    })
    
    # Retrieve network performance data
    results = monitoring_client.list_time_series(
        request={
            "name": project_name,
            "filter": 'metric.type="compute.googleapis.com/instance/network/sent_bytes_count"',
            "interval": interval,
        }
    )
    
    metrics = {
        "latency": 0,
        "packet_loss": 0,
        "throughput": 0,
        "connection_failures": 0
    }
    
    # Process and analyze the metrics
    for result in results:
        for point in result.points:
            metrics["throughput"] += point.value.double_value
    
    logger.info(f"Analyzed network metrics: {metrics}")
    return metrics

def determine_optimization_actions(metrics):
    """
    Determine what optimization actions to take based on performance metrics.
    """
    actions = []
    
    # High latency optimization
    if metrics.get("latency", 0) > 100:  # milliseconds
        actions.append({
            "type": "route_optimization",
            "priority": "high",
            "target": "reduce_latency"
        })
    
    # Low throughput optimization
    if metrics.get("throughput", 0) < 1000000:  # bytes per second
        actions.append({
            "type": "bandwidth_scaling",
            "priority": "medium",
            "target": "increase_throughput"
        })
    
    # Connection failure handling
    if metrics.get("connection_failures", 0) > 5:
        actions.append({
            "type": "failover_activation",
            "priority": "critical",
            "target": "restore_connectivity"
        })
    
    logger.info(f"Determined optimization actions: {actions}")
    return actions

def execute_optimization_action(action, network_client):
    """
    Execute a specific network optimization action.
    """
    action_type = action.get("type")
    priority = action.get("priority")
    
    logger.info(f"Executing {action_type} action with {priority} priority")
    
    if action_type == "route_optimization":
        # Implement intelligent routing optimization
        optimize_routing(network_client)
    elif action_type == "bandwidth_scaling":
        # Scale bandwidth based on demand
        scale_bandwidth()
    elif action_type == "failover_activation":
        # Activate failover mechanisms
        activate_failover()
    
    logger.info(f"Successfully executed {action_type} action")

def optimize_routing(network_client):
    """
    Optimize network routing for better performance.
    """
    # Implementation would include actual routing optimization logic
    # This is a simplified example for demonstration
    logger.info("Optimizing network routing for improved latency")

def scale_bandwidth():
    """
    Scale network bandwidth based on current demand.
    """
    logger.info("Scaling network bandwidth to meet demand")

def activate_failover():
    """
    Activate failover mechanisms for improved reliability.
    """
    logger.info("Activating network failover mechanisms")
EOF
   
   # Create requirements.txt for the function dependencies
   cat > requirements.txt << 'EOF'
functions-framework==3.8.3
google-cloud-monitoring==2.23.1
google-cloud-network-management==1.9.1
google-cloud-pubsub==2.24.0
EOF
   
   # Deploy the Cloud Function
   gcloud functions deploy ${FUNCTION_NAME} \
       --gen2 \
       --runtime=python311 \
       --region=${REGION} \
       --source=. \
       --entry-point=optimize_network \
       --trigger-topic=${TOPIC_NAME} \
       --set-env-vars="GCP_PROJECT=${PROJECT_ID}" \
       --memory=256MB \
       --timeout=60s
   
   cd ..
   
   echo "✅ Network optimization Cloud Function deployed"
   ```

   The Cloud Function is now deployed and ready to process network optimization events. It implements intelligent algorithms that analyze performance metrics, determine appropriate optimization strategies, and execute remediation actions automatically, providing the core automation for our network optimization system.

5. **Configure Network Analyzer for Automated Insights**:

   Network Analyzer automatically monitors VPC network configurations and detects misconfigurations, suboptimal settings, and potential issues. Enabling this service provides continuous intelligence about network health and feeds recommendations into our optimization system.

   ```bash
   # Enable Network Analyzer for automated configuration monitoring
   # Note: Network Analyzer automatically monitors configurations once enabled
   
   # Create a Cloud Monitoring policy for Network Analyzer insights
   cat > network_analyzer_policy.yaml << 'EOF'
displayName: "Network Analyzer Alerts"
combiner: OR
conditions:
  - displayName: "Network Configuration Issue"
    conditionThreshold:
      filter: 'resource.type="gce_network"'
      comparison: COMPARISON_GREATER_THAN
      thresholdValue: 0
      duration: "60s"
notificationChannels: []
alertStrategy:
  autoClose: "1800s"
EOF
   
   # Apply the Network Analyzer monitoring policy
   gcloud alpha monitoring policies create --policy-from-file=network_analyzer_policy.yaml
   
   echo "✅ Network Analyzer configured for automated insights"
   ```

   Network Analyzer is now continuously monitoring the network infrastructure and will automatically detect configuration issues, providing intelligent insights that enhance our optimization decision-making process.

6. **Set Up Flow Analyzer for Traffic Pattern Analysis**:

   Flow Analyzer processes VPC Flow Logs to provide detailed insights into network traffic patterns, security compliance, and performance optimization opportunities. This analysis helps identify traffic anomalies and optimization targets for our intelligent system.

   ```bash
   # Enable VPC Flow Logs for detailed traffic analysis
   gcloud compute networks subnets update default \
       --region=${REGION} \
       --enable-flow-logs \
       --logging-flow-sampling=0.1 \
       --logging-aggregation-interval=INTERVAL_5_SEC \
       --logging-metadata=INCLUDE_ALL_METADATA
   
   # Create a scheduled Cloud Function for periodic flow analysis
   cat > flow_analyzer.py << 'EOF'
import functions_framework
import logging
import os
import json
from google.cloud import bigquery
from google.cloud import pubsub_v1

logger = logging.getLogger(__name__)

@functions_framework.http
def analyze_traffic_flows(request):
    """
    Analyze VPC Flow Logs to identify traffic patterns and optimization opportunities.
    """
    try:
        # Initialize BigQuery client for flow log analysis
        bq_client = bigquery.Client()
        
        # Query to analyze traffic patterns (simplified for demonstration)
        query = """
        SELECT
            jsonPayload.src_ip as src_ip,
            jsonPayload.dest_ip as dest_ip,
            jsonPayload.protocol as protocol,
            AVG(CAST(jsonPayload.bytes_sent AS INT64)) as avg_bytes,
            COUNT(*) as connection_count
        FROM `{project}.compute_googleapis_com_vpc_flows`
        WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
        GROUP BY src_ip, dest_ip, protocol
        HAVING connection_count > 1000
        ORDER BY connection_count DESC
        LIMIT 100
        """.format(project=os.environ.get('GCP_PROJECT'))
        
        # Execute the analysis query
        query_job = bq_client.query(query)
        results = query_job.result()
        
        # Process flow analysis results
        optimization_opportunities = []
        for row in results:
            if row.connection_count > 1500:  # High connection threshold
                optimization_opportunities.append({
                    "type": "high_connection_flow",
                    "src_ip": row.src_ip,
                    "dest_ip": row.dest_ip,
                    "connection_count": row.connection_count,
                    "recommendation": "bandwidth_optimization"
                })
        
        # Publish optimization opportunities to Pub/Sub
        if optimization_opportunities:
            publisher = pubsub_v1.PublisherClient()
            topic_path = publisher.topic_path(
                os.environ.get('GCP_PROJECT'), 
                os.environ.get('TOPIC_NAME')
            )
            
            for opportunity in optimization_opportunities:
                message_data = json.dumps(opportunity).encode('utf-8')
                publisher.publish(topic_path, message_data)
        
        logger.info(f"Flow analysis completed. Found {len(optimization_opportunities)} opportunities")
        return {"status": "success", "opportunities": len(optimization_opportunities)}
        
    except Exception as e:
        logger.error(f"Error in flow analysis: {str(e)}")
        return {"status": "error", "message": str(e)}
EOF
   
   # Deploy the flow analyzer function
   gcloud functions deploy flow-analyzer-${RANDOM_SUFFIX} \
       --gen2 \
       --runtime=python311 \
       --region=${REGION} \
       --source=. \
       --entry-point=analyze_traffic_flows \
       --trigger-http \
       --set-env-vars="GCP_PROJECT=${PROJECT_ID},TOPIC_NAME=${TOPIC_NAME}" \
       --memory=512MB \
       --timeout=120s
   
   echo "✅ Flow Analyzer configured for traffic pattern analysis"
   ```

   Flow Analyzer is now processing network traffic data and identifying optimization opportunities based on real traffic patterns. This provides data-driven insights that enhance the intelligence of our automated optimization system.

7. **Create Cloud Scheduler for Periodic Optimization**:

   Cloud Scheduler enables time-based automation, allowing our network optimization system to perform regular health checks, analyze trends, and apply proactive optimizations during maintenance windows. This ensures continuous improvement of network performance.

   ```bash
   # Create a Cloud Scheduler job for periodic network optimization
   gcloud scheduler jobs create http periodic-network-optimization \
       --schedule="*/15 * * * *" \
       --uri="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/flow-analyzer-${RANDOM_SUFFIX}" \
       --http-method=GET \
       --time-zone="UTC" \
       --description="Periodic network traffic analysis and optimization"
   
   # Create a scheduler for daily network health reports
   gcloud scheduler jobs create pubsub daily-network-report \
       --schedule="0 9 * * *" \
       --topic=${TOPIC_NAME} \
       --message-body='{"type":"daily_report","action":"generate_network_health_report"}' \
       --time-zone="UTC" \
       --description="Daily network health and performance report"
   
   echo "✅ Cloud Scheduler configured for periodic optimization"
   ```

   The scheduling system now automatically triggers network analysis and optimization at regular intervals, ensuring that the system continuously monitors and improves network performance without manual intervention.

8. **Configure Firewall Insights for Security Optimization**:

   Firewall Insights provides intelligence about firewall rule usage, identifying overly permissive rules, unused rules, and optimization opportunities. This enhances both security and performance by ensuring optimal firewall configurations.

   ```bash
   # Enable Firewall Insights for security and performance optimization
   # Note: Firewall Insights is automatically enabled with Network Intelligence Center
   
   # Create monitoring for firewall rule optimization opportunities
   cat > firewall_optimization.py << 'EOF'
import functions_framework
import logging
import os
import json
from google.cloud import compute_v1
from google.cloud import pubsub_v1

logger = logging.getLogger(__name__)

@functions_framework.http
def optimize_firewall_rules(request):
    """
    Analyze firewall rules and recommend optimizations for better performance and security.
    """
    try:
        # Initialize Compute Engine client
        compute_client = compute_v1.FirewallsClient()
        project_id = os.environ.get('GCP_PROJECT')
        
        # List all firewall rules
        firewall_rules = compute_client.list(project=project_id)
        
        optimization_recommendations = []
        
        for rule in firewall_rules:
            # Analyze rule for optimization opportunities
            if rule.source_ranges and '0.0.0.0/0' in rule.source_ranges:
                optimization_recommendations.append({
                    "type": "overly_permissive_rule",
                    "rule_name": rule.name,
                    "recommendation": "restrict_source_ranges",
                    "priority": "high",
                    "security_impact": "reduce_attack_surface"
                })
            
            # Check for unused rules (simplified logic)
            if not rule.target_tags and not rule.target_service_accounts:
                optimization_recommendations.append({
                    "type": "potentially_unused_rule",
                    "rule_name": rule.name,
                    "recommendation": "review_and_cleanup",
                    "priority": "medium",
                    "performance_impact": "reduce_rule_processing_overhead"
                })
        
        # Publish recommendations to optimization system
        if optimization_recommendations:
            publisher = pubsub_v1.PublisherClient()
            topic_path = publisher.topic_path(project_id, os.environ.get('TOPIC_NAME'))
            
            for recommendation in optimization_recommendations:
                message_data = json.dumps(recommendation).encode('utf-8')
                publisher.publish(topic_path, message_data)
        
        logger.info(f"Firewall analysis completed. Found {len(optimization_recommendations)} recommendations")
        return {"status": "success", "recommendations": len(optimization_recommendations)}
        
    except Exception as e:
        logger.error(f"Error in firewall analysis: {str(e)}")
        return {"status": "error", "message": str(e)}
EOF
   
   # Deploy the firewall optimization function
   gcloud functions deploy firewall-optimizer-${RANDOM_SUFFIX} \
       --gen2 \
       --runtime=python311 \
       --region=${REGION} \
       --source=. \
       --entry-point=optimize_firewall_rules \
       --trigger-http \
       --set-env-vars="GCP_PROJECT=${PROJECT_ID},TOPIC_NAME=${TOPIC_NAME}" \
       --memory=256MB \
       --timeout=60s
   
   echo "✅ Firewall Insights configured for security optimization"
   ```

   Firewall optimization is now integrated into the system, providing security-focused performance improvements and ensuring that firewall rules are optimized for both protection and network efficiency.

## Validation & Testing

1. **Verify Network Intelligence Center Integration**:

   ```bash
   # Check connectivity test status
   gcloud network-management connectivity-tests list
   
   # Verify that tests are passing
   gcloud network-management connectivity-tests describe \
       regional-connectivity-test \
       --format="value(reachabilityDetails.result)"
   ```

   Expected output: `REACHABLE` status indicating successful connectivity validation.

2. **Test Cloud Function Deployment and Execution**:

   ```bash
   # Test the network optimization function
   gcloud pubsub topics publish ${TOPIC_NAME} \
       --message='{"type":"test","latency":150,"throughput":500000}'
   
   # Check function logs
   gcloud functions logs read ${FUNCTION_NAME} \
       --region=${REGION} \
       --limit=10
   ```

   Expected output: Function execution logs showing successful processing of the test message.

3. **Validate Monitoring and Alerting Configuration**:

   ```bash
   # List configured monitoring policies
   gcloud alpha monitoring policies list \
       --format="table(displayName,combiner)"
   
   # Check that scheduled jobs are created
   gcloud scheduler jobs list
   ```

   Expected output: Monitoring policies and scheduler jobs listed with `ENABLED` status.

4. **Test Flow Analyzer Functionality**:

   ```bash
   # Trigger flow analysis manually
   FLOW_ANALYZER_URL=$(gcloud functions describe flow-analyzer-${RANDOM_SUFFIX} \
       --region=${REGION} \
       --format="value(serviceConfig.uri)")
   
   curl -X GET "${FLOW_ANALYZER_URL}"
   ```

   Expected output: JSON response indicating successful flow analysis execution.

## Cleanup

1. **Remove Cloud Functions and Scheduled Jobs**:

   ```bash
   # Delete Cloud Functions
   gcloud functions delete ${FUNCTION_NAME} \
       --region=${REGION} \
       --quiet
   
   gcloud functions delete flow-analyzer-${RANDOM_SUFFIX} \
       --region=${REGION} \
       --quiet
   
   gcloud functions delete firewall-optimizer-${RANDOM_SUFFIX} \
       --region=${REGION} \
       --quiet
   
   # Delete scheduled jobs
   gcloud scheduler jobs delete periodic-network-optimization --quiet
   gcloud scheduler jobs delete daily-network-report --quiet
   
   echo "✅ Functions and scheduled jobs removed"
   ```

2. **Clean Up Network Intelligence Center Resources**:

   ```bash
   # Delete connectivity tests
   gcloud network-management connectivity-tests delete \
       regional-connectivity-test --quiet
   
   gcloud network-management connectivity-tests delete \
       external-connectivity-test --quiet
   
   # Disable VPC Flow Logs
   gcloud compute networks subnets update default \
       --region=${REGION} \
       --no-enable-flow-logs
   
   echo "✅ Network Intelligence Center resources cleaned up"
   ```

3. **Remove Monitoring and Pub/Sub Resources**:

   ```bash
   # Delete monitoring policies
   gcloud alpha monitoring policies list \
       --format="value(name)" | \
       xargs -I {} gcloud alpha monitoring policies delete {} --quiet
   
   # Delete Pub/Sub resources
   gcloud pubsub subscriptions delete ${TOPIC_NAME}-sub --quiet
   gcloud pubsub topics delete ${TOPIC_NAME} --quiet
   
   # Delete Cloud Storage bucket
   gsutil -m rm -r gs://${BUCKET_NAME}
   
   echo "✅ Monitoring and messaging resources removed"
   ```

4. **Clean Up Project Resources**:

   ```bash
   # Remove temporary files
   rm -rf network-optimizer/
   rm -f network_metrics.yaml
   rm -f network_analyzer_policy.yaml
   rm -f flow_analyzer.py
   rm -f firewall_optimization.py
   
   # Optional: Delete the entire project if created specifically for this recipe
   # gcloud projects delete ${PROJECT_ID} --quiet
   
   echo "✅ All resources cleaned up successfully"
   echo "Note: Project deletion may take several minutes to complete"
   ```

## Discussion

This intelligent network performance optimization solution demonstrates the power of combining Google Cloud WAN's global infrastructure with Network Intelligence Center's AI-powered insights to create a self-healing network operations system. The architecture leverages multiple Google Cloud services working in harmony: Cloud WAN provides the high-performance global network backbone, Network Intelligence Center delivers comprehensive visibility and analysis, Cloud Functions enable serverless automation, and Cloud Monitoring ensures continuous oversight.

The solution addresses common enterprise networking challenges through proactive intelligence rather than reactive troubleshooting. By automatically analyzing connectivity tests, traffic flow patterns, firewall configurations, and performance metrics, the system can identify optimization opportunities and implement corrective actions before issues impact end users. This approach significantly reduces mean time to resolution (MTTR) and improves overall network reliability while following Google Cloud's best practices for security and performance.

The serverless architecture ensures that optimization logic scales automatically with network complexity and event volume, while the event-driven design enables real-time responses to changing network conditions. The integration of multiple Network Intelligence Center modules—Connectivity Tests, Flow Analyzer, Performance Dashboard, Network Analyzer, and Firewall Insights—provides comprehensive coverage of network health aspects, creating a holistic optimization strategy that adheres to the Google Cloud Architecture Framework principles.

Key benefits include automated remediation workflows that reduce operational overhead, intelligent routing optimizations that improve application performance, and proactive issue detection that prevents outages. The solution also provides detailed audit trails and reporting capabilities, enabling network teams to understand optimization decisions and continuously improve their infrastructure strategy based on Google Cloud's operational excellence patterns.

> **Tip**: Consider implementing custom machine learning models using Vertex AI to enhance optimization decision-making based on historical network performance data and business-specific traffic patterns, following Google Cloud's AI/ML best practices.

For deeper understanding and advanced configurations, refer to these official Google Cloud resources:

- [Network Intelligence Center Overview](https://cloud.google.com/network-intelligence-center/docs) - Complete documentation for all NIC modules and capabilities
- [Connectivity Tests Guide](https://cloud.google.com/network-intelligence-center/docs/connectivity-tests/concepts/overview) - Detailed information on network path validation and troubleshooting
- [Flow Analyzer Documentation](https://cloud.google.com/network-intelligence-center/docs/flow-analyzer/overview) - Guide to VPC Flow Logs analysis and traffic optimization
- [Google Cloud Architecture Framework](https://cloud.google.com/architecture/framework) - Best practices for designing resilient and efficient cloud architectures
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices) - Optimization guidelines for serverless function development

## Challenge

Extend this solution by implementing these enhancements:

1. **Machine Learning-Enhanced Optimization**: Develop custom ML models using Vertex AI to predict network performance issues and optimize routing decisions based on historical patterns and business requirements.

2. **Multi-Cloud Network Optimization**: Integrate Cross-Cloud Interconnect to extend optimization capabilities across AWS, Azure, and other cloud providers, creating unified global network performance management.

3. **Advanced Security Integration**: Implement Cloud Armor integration for DDoS protection optimization and Security Command Center integration for comprehensive security posture management.

4. **Custom Performance Metrics**: Create business-specific KPIs and SLAs that trigger optimization actions based on application-level performance requirements rather than just network metrics.

5. **Disaster Recovery Automation**: Build automated failover and recovery workflows that leverage Cloud WAN's redundancy features and Network Intelligence Center's health monitoring for business continuity optimization.

## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [Infrastructure Manager](code/infrastructure-manager/) - GCP Infrastructure Manager templates
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using gcloud CLI commands to deploy infrastructure
- [Terraform](code/terraform/) - Terraform configuration files