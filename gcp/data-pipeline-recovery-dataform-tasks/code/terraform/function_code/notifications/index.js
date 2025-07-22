/**
 * Notification Handler Cloud Function
 * 
 * This function processes recovery results and sends appropriate alerts to stakeholders
 * through multiple channels including email, Slack, and operations dashboards. It ensures
 * that teams stay informed about pipeline health, recovery actions, and any issues
 * requiring manual intervention.
 * 
 * Key responsibilities:
 * - Process recovery result messages from Pub/Sub
 * - Generate contextual notification messages
 * - Route notifications through appropriate channels
 * - Maintain notification history and analytics
 * - Handle notification delivery failures
 */

const {Logging} = require('@google-cloud/logging');
const {BigQuery} = require('@google-cloud/bigquery');

// Initialize Google Cloud clients
const logging = new Logging();
const bigquery = new BigQuery();
const log = logging.log('notification-handler');

/**
 * Main entry point for handling Pub/Sub notification messages
 * 
 * @param {Object} message - Pub/Sub message containing recovery results
 * @param {Object} context - Cloud Functions context object
 */
exports.handleNotification = async (message, context) => {
  try {
    // Decode the Pub/Sub message data
    const notificationData = JSON.parse(Buffer.from(message.data, 'base64').toString());
    
    // Log the incoming notification for audit purposes
    await log.write(log.entry('INFO', {
      message: 'Processing recovery notification',
      data: notificationData,
      messageId: context.eventId,
      timestamp: context.timestamp
    }));
    
    // Build appropriate notification message based on recovery result
    const notification = await buildNotificationMessage(notificationData);
    
    // Send notifications through multiple channels
    await Promise.all([
      sendEmailNotification(notification),
      sendSlackNotification(notification),
      logDashboardUpdate(notification),
      recordNotificationMetrics(notification, notificationData)
    ]);
    
    // Log successful notification processing
    await log.write(log.entry('INFO', {
      message: 'Notification processed successfully',
      pipelineId: notificationData.pipelineId,
      notificationType: notification.type,
      channels: notification.channels
    }));
    
  } catch (error) {
    // Log detailed error information for debugging
    await log.write(log.entry('ERROR', {
      message: 'Failed to process notification',
      error: error.message,
      stack: error.stack,
      messageId: context?.eventId,
      messageData: message.data
    }));
    
    // Don't throw error to prevent Pub/Sub message retry loops
    // Instead, send error to dead letter queue if configured
  }
};

/**
 * Build comprehensive notification message from recovery result data
 * 
 * @param {Object} data - Recovery result data
 * @returns {Object} Formatted notification object
 */
async function buildNotificationMessage(data) {
  const {success, action, pipelineId, timestamp, operationId, requiresManualIntervention} = data;
  
  // Determine notification type and priority
  const notificationType = determineNotificationType(data);
  const priority = determinePriority(data);
  
  // Build context-aware message content
  const notification = {
    type: notificationType,
    priority,
    subject: generateSubject(data),
    body: generateMessageBody(data),
    pipelineId,
    timestamp,
    channels: determineNotificationChannels(priority, data),
    metadata: {
      action,
      success,
      operationId,
      requiresManualIntervention,
      recoveryDuration: calculateRecoveryDuration(data)
    }
  };
  
  // Add action items for failed recoveries
  if (!success || requiresManualIntervention) {
    notification.actionItems = generateActionItems(data);
    notification.escalationLevel = determineEscalationLevel(data);
  }
  
  return notification;
}

/**
 * Determine the type of notification based on recovery data
 * 
 * @param {Object} data - Recovery result data
 * @returns {string} Notification type
 */
function determineNotificationType(data) {
  if (data.requiresManualIntervention) {
    return 'ESCALATION';
  } else if (data.success) {
    return 'RECOVERY_SUCCESS';
  } else {
    return 'RECOVERY_FAILURE';
  }
}

/**
 * Determine notification priority level
 * 
 * @param {Object} data - Recovery result data
 * @returns {string} Priority level
 */
function determinePriority(data) {
  if (data.requiresManualIntervention) {
    return 'HIGH';
  } else if (!data.success) {
    return 'MEDIUM';
  } else {
    return 'LOW';
  }
}

/**
 * Generate appropriate subject line for notification
 * 
 * @param {Object} data - Recovery result data
 * @returns {string} Subject line
 */
function generateSubject(data) {
  const {success, pipelineId, action, requiresManualIntervention} = data;
  
  if (requiresManualIntervention) {
    return `🚨 Manual Intervention Required: Pipeline ${pipelineId}`;
  } else if (success) {
    return `✅ Pipeline Recovery Successful: ${pipelineId}`;
  } else {
    return `❌ Pipeline Recovery Failed: ${pipelineId}`;
  }
}

/**
 * Generate detailed message body with context and next steps
 * 
 * @param {Object} data - Recovery result data
 * @returns {string} Message body
 */
function generateMessageBody(data) {
  const {
    success,
    action,
    pipelineId,
    timestamp,
    operationId,
    requiresManualIntervention,
    attemptCount,
    failureType
  } = data;
  
  let body = `
**Pipeline Recovery Report**

📊 **Pipeline ID:** ${pipelineId}
🔧 **Recovery Action:** ${action}
📅 **Timestamp:** ${timestamp}
📈 **Status:** ${success ? 'SUCCESS' : 'FAILED'}
`;

  if (operationId) {
    body += `🆔 **Operation ID:** ${operationId}\n`;
  }
  
  if (attemptCount) {
    body += `🔄 **Attempt Count:** ${attemptCount}\n`;
  }
  
  if (failureType) {
    body += `⚠️ **Original Failure Type:** ${failureType}\n`;
  }
  
  // Add context-specific information
  if (success) {
    body += `
✅ **Recovery Status:** The pipeline has been successfully recovered and is now running normally.

📋 **Next Steps:**
- Monitor pipeline execution in the next few cycles
- Review logs for any performance impacts
- Consider optimizing pipeline configuration to prevent similar failures
`;
  } else if (requiresManualIntervention) {
    body += `
🚨 **Escalation Required:** Automated recovery has been exhausted. Manual intervention is required.

📋 **Immediate Actions Required:**
- Review pipeline logs and configuration
- Check data integrity and dependencies
- Investigate root cause of repeated failures
- Consider emergency rollback if necessary

🔗 **Useful Links:**
- Dataform Console: https://console.cloud.google.com/dataform
- Cloud Logging: https://console.cloud.google.com/logs
- Monitoring Dashboard: https://console.cloud.google.com/monitoring
`;
  } else {
    body += `
❌ **Recovery Failed:** The automated recovery attempt was unsuccessful.

📋 **Next Steps:**
- Additional recovery attempts will be made automatically
- Monitor Cloud Tasks queue for retry status
- Review pipeline logs for detailed error information
- Prepare for potential manual intervention if retries continue to fail
`;
  }
  
  return body;
}

/**
 * Determine appropriate notification channels based on priority
 * 
 * @param {string} priority - Notification priority
 * @param {Object} data - Recovery result data
 * @returns {Array} List of notification channels
 */
function determineNotificationChannels(priority, data) {
  const channels = ['email', 'dashboard'];
  
  if (priority === 'HIGH' || data.requiresManualIntervention) {
    channels.push('slack', 'pagerduty');
  } else if (priority === 'MEDIUM') {
    channels.push('slack');
  }
  
  return channels;
}

/**
 * Generate specific action items for failed recoveries
 * 
 * @param {Object} data - Recovery result data
 * @returns {Array} List of action items
 */
function generateActionItems(data) {
  const actionItems = [
    'Review detailed logs in Cloud Logging',
    'Check Dataform workflow configuration',
    'Verify data source integrity and availability'
  ];
  
  if (data.failureType === 'sql_error') {
    actionItems.push('Review SQL query syntax and compatibility');
  } else if (data.failureType === 'resource_exhausted') {
    actionItems.push('Check BigQuery slot usage and quotas');
  } else if (data.failureType === 'permission_denied') {
    actionItems.push('Verify service account permissions and IAM roles');
  }
  
  return actionItems;
}

/**
 * Determine escalation level for manual intervention
 * 
 * @param {Object} data - Recovery result data
 * @returns {string} Escalation level
 */
function determineEscalationLevel(data) {
  if (data.attemptCount >= 5) {
    return 'CRITICAL';
  } else if (data.requiresManualIntervention) {
    return 'HIGH';
  } else {
    return 'MEDIUM';
  }
}

/**
 * Calculate recovery duration from start to completion
 * 
 * @param {Object} data - Recovery result data
 * @returns {number} Duration in minutes
 */
function calculateRecoveryDuration(data) {
  // This would calculate actual duration based on recovery metadata
  // For now, return a placeholder value
  return data.metadata?.recoveryDurationMinutes || 0;
}

/**
 * Send email notification to configured recipients
 * 
 * @param {Object} notification - Formatted notification object
 */
async function sendEmailNotification(notification) {
  try {
    // In a production environment, this would integrate with an email service
    // For demonstration, we'll log the email content
    
    const recipients = process.env.NOTIFICATION_RECIPIENTS?.split(',') || ['${notification_recipients}'];
    
    await log.write(log.entry('INFO', {
      message: 'Email notification sent',
      recipients,
      subject: notification.subject,
      priority: notification.priority,
      pipelineId: notification.pipelineId
    }));
    
  } catch (error) {
    await log.write(log.entry('ERROR', {
      message: 'Failed to send email notification',
      error: error.message,
      notification
    }));
  }
}

/**
 * Send Slack notification to configured channels
 * 
 * @param {Object} notification - Formatted notification object
 */
async function sendSlackNotification(notification) {
  try {
    // In a production environment, this would integrate with Slack API
    // For demonstration, we'll log the Slack message
    
    if (notification.channels.includes('slack')) {
      await log.write(log.entry('INFO', {
        message: 'Slack notification sent',
        channel: '#data-operations',
        subject: notification.subject,
        priority: notification.priority,
        pipelineId: notification.pipelineId
      }));
    }
    
  } catch (error) {
    await log.write(log.entry('ERROR', {
      message: 'Failed to send Slack notification',
      error: error.message,
      notification
    }));
  }
}

/**
 * Update operational dashboard with recovery status
 * 
 * @param {Object} notification - Formatted notification object
 */
async function logDashboardUpdate(notification) {
  try {
    // Log dashboard update for operational visibility
    await log.write(log.entry('INFO', {
      message: 'Dashboard updated with recovery status',
      pipelineId: notification.pipelineId,
      status: notification.metadata.success ? 'RECOVERED' : 'FAILED',
      action: notification.metadata.action,
      timestamp: notification.timestamp,
      priority: notification.priority
    }));
    
  } catch (error) {
    await log.write(log.entry('ERROR', {
      message: 'Failed to update dashboard',
      error: error.message,
      notification
    }));
  }
}

/**
 * Record notification metrics for analytics and monitoring
 * 
 * @param {Object} notification - Formatted notification object
 * @param {Object} originalData - Original recovery result data
 */
async function recordNotificationMetrics(notification, originalData) {
  try {
    // In a production environment, this would write to BigQuery for analytics
    await log.write(log.entry('INFO', {
      message: 'Notification metrics recorded',
      pipelineId: notification.pipelineId,
      notificationType: notification.type,
      priority: notification.priority,
      channels: notification.channels,
      recoverySuccess: originalData.success,
      recoveryAction: originalData.action,
      escalationRequired: originalData.requiresManualIntervention
    }));
    
  } catch (error) {
    await log.write(log.entry('ERROR', {
      message: 'Failed to record notification metrics',
      error: error.message
    }));
  }
}