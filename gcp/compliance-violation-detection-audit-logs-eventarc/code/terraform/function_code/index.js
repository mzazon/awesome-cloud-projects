// Cloud Function for Compliance Violation Detection
// This function analyzes Google Cloud Audit Logs for compliance violations
// and triggers appropriate alerting and remediation workflows

const functions = require('@google-cloud/functions-framework');
const { PubSub } = require('@google-cloud/pubsub');
const { BigQuery } = require('@google-cloud/bigquery');
const { MetricServiceClient } = require('@google-cloud/monitoring');

// Initialize Google Cloud clients
const pubsub = new PubSub();
const bigquery = new BigQuery();
const monitoring = new MetricServiceClient();

// Configuration from environment variables (set by Terraform)
const CONFIG = {
  topicName: process.env.TOPIC_NAME || '${topic_name}',
  datasetName: process.env.DATASET_NAME || '${dataset_name}',
  projectId: process.env.PROJECT_ID || '${project_id}',
  environment: process.env.ENVIRONMENT || 'development'
};

// Compliance rules configuration
// These rules define what constitutes a compliance violation
const COMPLIANCE_RULES = {
  // High-severity violations
  IAM_POLICY_CHANGES: {
    severity: 'HIGH',
    methods: ['SetIamPolicy', 'setIamPolicy', 'CreateRole', 'DeleteRole', 'UpdateRole'],
    services: ['iam.googleapis.com', 'cloudresourcemanager.googleapis.com'],
    description: 'IAM policy modifications that could affect access controls'
  },
  
  PRIVILEGE_ESCALATION: {
    severity: 'CRITICAL',
    methods: ['SetIamPolicy'],
    services: ['iam.googleapis.com'],
    rolePatterns: ['.*admin.*', '.*owner.*', '.*editor.*'],
    description: 'Potential privilege escalation through role assignments'
  },
  
  // Medium-severity violations
  ADMIN_ACTIONS: {
    severity: 'MEDIUM',
    methods: ['Delete', 'Create', 'Update', 'Patch'],
    services: [
      'compute.googleapis.com',
      'storage.googleapis.com',
      'container.googleapis.com',
      'sqladmin.googleapis.com'
    ],
    description: 'Administrative actions on critical infrastructure'
  },
  
  SECURITY_CONFIG_CHANGES: {
    severity: 'HIGH',
    methods: ['Create', 'Delete', 'Update', 'Patch'],
    services: ['compute.googleapis.com'],
    resourcePatterns: ['.*firewall.*', '.*securityPolicy.*', '.*sslCertificate.*'],
    description: 'Changes to security configurations'
  },
  
  // Low-severity violations (monitoring for trends)
  DATA_ACCESS: {
    severity: 'LOW',
    logType: 'DATA_READ',
    services: [
      'storage.googleapis.com',
      'bigquery.googleapis.com',
      'cloudsql.googleapis.com'
    ],
    description: 'Data access events for compliance auditing'
  },
  
  UNUSUAL_LOCATIONS: {
    severity: 'MEDIUM',
    description: 'Access from unusual geographic locations',
    checkCallerIp: true
  }
};

// Main Cloud Function entry point
// Processes CloudEvent containing audit log data
functions.cloudEvent('analyzeAuditLog', async (cloudEvent) => {
  console.log('Processing audit log event:', JSON.stringify(cloudEvent.type));
  
  try {
    // Extract audit log data from the CloudEvent
    const auditLog = cloudEvent.data;
    const logEntry = auditLog.protoPayload || auditLog.jsonPayload;
    
    if (!logEntry) {
      console.log('No audit log payload found, skipping analysis');
      return;
    }
    
    console.log('Analyzing audit log entry:', {
      serviceName: logEntry.serviceName,
      methodName: logEntry.methodName,
      resourceName: auditLog.resource?.labels?.resource_name,
      principal: logEntry.authenticationInfo?.principalEmail,
      severity: auditLog.severity
    });
    
    // Analyze the audit log for compliance violations
    const violations = await analyzeCompliance(logEntry, auditLog);
    
    if (violations.length > 0) {
      console.log(`Found ${violations.length} compliance violations`);
      
      // Process each violation
      await Promise.all(violations.map(violation => processViolation(violation, auditLog)));
      
      console.log('Successfully processed all violations');
    } else {
      console.log('No compliance violations detected');
    }
    
  } catch (error) {
    console.error('Error processing audit log:', error);
    
    // Create error metric for monitoring
    await createErrorMetric(error);
    throw error;
  }
});

// Analyze audit log entry against compliance rules
async function analyzeCompliance(logEntry, auditLog) {
  const violations = [];
  const timestamp = auditLog.timestamp;
  const resource = extractResourceName(auditLog);
  const principal = logEntry.authenticationInfo?.principalEmail || 'unknown';
  const callerIp = logEntry.requestMetadata?.callerIp;
  
  // Check IAM policy changes
  if (isViolation(logEntry, COMPLIANCE_RULES.IAM_POLICY_CHANGES)) {
    violations.push({
      type: 'IAM_POLICY_CHANGE',
      severity: 'HIGH',
      timestamp: timestamp,
      resource: resource,
      principal: principal,
      details: `IAM policy modified: ${logEntry.methodName} on ${logEntry.serviceName}`,
      logEntry: logEntry,
      callerIp: callerIp
    });
  }
  
  // Check for privilege escalation
  if (isPotentialPrivilegeEscalation(logEntry)) {
    violations.push({
      type: 'PRIVILEGE_ESCALATION',
      severity: 'CRITICAL',
      timestamp: timestamp,
      resource: resource,
      principal: principal,
      details: `Potential privilege escalation: ${logEntry.methodName} with admin roles`,
      logEntry: logEntry,
      callerIp: callerIp
    });
  }
  
  // Check administrative actions
  if (isViolation(logEntry, COMPLIANCE_RULES.ADMIN_ACTIONS)) {
    violations.push({
      type: 'ADMIN_ACTION',
      severity: 'MEDIUM',
      timestamp: timestamp,
      resource: resource,
      principal: principal,
      details: `Administrative action: ${logEntry.methodName} on ${logEntry.serviceName}`,
      logEntry: logEntry,
      callerIp: callerIp
    });
  }
  
  // Check security configuration changes
  if (isSecurityConfigChange(logEntry)) {
    violations.push({
      type: 'SECURITY_CONFIG_CHANGE',
      severity: 'HIGH',
      timestamp: timestamp,
      resource: resource,
      principal: principal,
      details: `Security configuration change: ${logEntry.methodName} on ${resource}`,
      logEntry: logEntry,
      callerIp: callerIp
    });
  }
  
  // Check data access patterns
  if (isDataAccessViolation(logEntry, auditLog)) {
    violations.push({
      type: 'DATA_ACCESS',
      severity: 'LOW',
      timestamp: timestamp,
      resource: resource,
      principal: principal,
      details: `Data access: ${logEntry.methodName} on ${logEntry.serviceName}`,
      logEntry: logEntry,
      callerIp: callerIp
    });
  }
  
  // Check for unusual geographic access
  if (isUnusualLocationAccess(logEntry)) {
    violations.push({
      type: 'UNUSUAL_LOCATION',
      severity: 'MEDIUM',
      timestamp: timestamp,
      resource: resource,
      principal: principal,
      details: `Access from unusual location: ${callerIp}`,
      logEntry: logEntry,
      callerIp: callerIp
    });
  }
  
  return violations;
}

// Helper function to check if log entry matches violation rule
function isViolation(logEntry, rule) {
  if (rule.methods && !rule.methods.some(method => 
    logEntry.methodName && logEntry.methodName.includes(method))) {
    return false;
  }
  
  if (rule.services && !rule.services.includes(logEntry.serviceName)) {
    return false;
  }
  
  return true;
}

// Check for potential privilege escalation
function isPotentialPrivilegeEscalation(logEntry) {
  const rule = COMPLIANCE_RULES.PRIVILEGE_ESCALATION;
  
  if (!isViolation(logEntry, rule)) {
    return false;
  }
  
  // Check if high-privilege roles are being assigned
  const request = logEntry.request;
  if (request && request.policy && request.policy.bindings) {
    return request.policy.bindings.some(binding => 
      binding.role && rule.rolePatterns.some(pattern => 
        new RegExp(pattern, 'i').test(binding.role)
      )
    );
  }
  
  return false;
}

// Check for security configuration changes
function isSecurityConfigChange(logEntry) {
  const rule = COMPLIANCE_RULES.SECURITY_CONFIG_CHANGES;
  
  if (!isViolation(logEntry, rule)) {
    return false;
  }
  
  const resourceName = logEntry.resourceName || '';
  return rule.resourcePatterns.some(pattern => 
    new RegExp(pattern, 'i').test(resourceName)
  );
}

// Check for data access violations
function isDataAccessViolation(logEntry, auditLog) {
  const rule = COMPLIANCE_RULES.DATA_ACCESS;
  
  // Only process data access logs in development/monitoring mode
  if (CONFIG.environment === 'production') {
    return false;
  }
  
  return rule.services.includes(logEntry.serviceName) && 
         auditLog.severity === 'INFO' &&
         logEntry.authenticationInfo;
}

// Check for access from unusual locations
function isUnusualLocationAccess(logEntry) {
  // Simplified geolocation check - in practice, you'd use more sophisticated logic
  const callerIp = logEntry.requestMetadata?.callerIp;
  
  if (!callerIp || callerIp.startsWith('10.') || callerIp.startsWith('172.') || 
      callerIp.startsWith('192.168.') || callerIp === '127.0.0.1') {
    return false; // Internal or local IP
  }
  
  // This is a simplified check - implement proper geolocation analysis
  return false;
}

// Extract resource name from audit log
function extractResourceName(auditLog) {
  if (auditLog.resource?.labels?.resource_name) {
    return auditLog.resource.labels.resource_name;
  }
  
  if (auditLog.protoPayload?.resourceName) {
    return auditLog.protoPayload.resourceName;
  }
  
  return 'unknown';
}

// Process a detected compliance violation
async function processViolation(violation, auditLog) {
  try {
    console.log(`Processing ${violation.type} violation for ${violation.principal}`);
    
    // Store violation in BigQuery for analysis
    await storeViolationInBigQuery(violation);
    
    // Send alert via Pub/Sub
    await sendAlert(violation);
    
    // Create custom metric for monitoring
    await createCustomMetric(violation);
    
    // Log violation for immediate visibility
    console.log(`COMPLIANCE VIOLATION DETECTED: ${violation.type}`, {
      severity: violation.severity,
      principal: violation.principal,
      resource: violation.resource,
      details: violation.details,
      timestamp: violation.timestamp
    });
    
  } catch (error) {
    console.error('Error processing violation:', error);
    throw error;
  }
}

// Store violation record in BigQuery
async function storeViolationInBigQuery(violation) {
  try {
    const dataset = bigquery.dataset(CONFIG.datasetName);
    const table = dataset.table('violations');
    
    const row = {
      timestamp: violation.timestamp,
      violation_type: violation.type,
      severity: violation.severity,
      resource: violation.resource,
      principal: violation.principal,
      details: violation.details,
      remediation_status: 'PENDING',
      project_id: CONFIG.projectId
    };
    
    await table.insert([row]);
    console.log('Violation stored in BigQuery successfully');
    
  } catch (error) {
    console.error('Error storing violation in BigQuery:', error);
    throw error;
  }
}

// Send compliance alert via Pub/Sub
async function sendAlert(violation) {
  try {
    const topic = pubsub.topic(CONFIG.topicName);
    
    const alertMessage = {
      violation_type: violation.type,
      severity: violation.severity,
      timestamp: violation.timestamp,
      resource: violation.resource,
      principal: violation.principal,
      details: violation.details,
      project_id: CONFIG.projectId,
      caller_ip: violation.callerIp,
      alert_id: generateAlertId(violation),
      environment: CONFIG.environment
    };
    
    const messageBuffer = Buffer.from(JSON.stringify(alertMessage));
    await topic.publishMessage({ 
      data: messageBuffer,
      attributes: {
        severity: violation.severity,
        violationType: violation.type,
        environment: CONFIG.environment
      }
    });
    
    console.log('Compliance alert sent via Pub/Sub');
    
  } catch (error) {
    console.error('Error sending alert:', error);
    throw error;
  }
}

// Create custom metric for Cloud Monitoring
async function createCustomMetric(violation) {
  try {
    const projectPath = monitoring.projectPath(CONFIG.projectId);
    
    const request = {
      name: projectPath,
      timeSeries: [{
        metric: {
          type: 'custom.googleapis.com/compliance/violations',
          labels: {
            violation_type: violation.type,
            severity: violation.severity,
            environment: CONFIG.environment
          }
        },
        resource: {
          type: 'global',
          labels: {
            project_id: CONFIG.projectId
          }
        },
        points: [{
          interval: {
            endTime: {
              seconds: Math.floor(Date.now() / 1000)
            }
          },
          value: {
            int64Value: 1
          }
        }]
      }]
    };
    
    await monitoring.createTimeSeries(request);
    console.log('Custom metric created successfully');
    
  } catch (error) {
    console.error('Error creating custom metric:', error);
    // Don't throw - metric creation failure shouldn't stop violation processing
  }
}

// Create error metric for monitoring function health
async function createErrorMetric(error) {
  try {
    const projectPath = monitoring.projectPath(CONFIG.projectId);
    
    const request = {
      name: projectPath,
      timeSeries: [{
        metric: {
          type: 'custom.googleapis.com/compliance/errors',
          labels: {
            error_type: error.name || 'UnknownError',
            environment: CONFIG.environment
          }
        },
        resource: {
          type: 'cloud_function',
          labels: {
            project_id: CONFIG.projectId,
            function_name: process.env.FUNCTION_NAME || 'compliance-detector'
          }
        },
        points: [{
          interval: {
            endTime: {
              seconds: Math.floor(Date.now() / 1000)
            }
          },
          value: {
            int64Value: 1
          }
        }]
      }]
    };
    
    await monitoring.createTimeSeries(request);
    
  } catch (metricError) {
    console.error('Error creating error metric:', metricError);
  }
}

// Generate unique alert ID for tracking
function generateAlertId(violation) {
  const timestamp = new Date(violation.timestamp).getTime();
  const hash = require('crypto')
    .createHash('md5')
    .update(`${violation.type}-${violation.principal}-${violation.resource}-${timestamp}`)
    .digest('hex')
    .substring(0, 8);
  
  return `alert-${hash}`;
}

// Export the function for testing
module.exports = { analyzeCompliance, processViolation };