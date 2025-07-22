/**
 * Pipeline Controller Cloud Function
 * 
 * This function serves as the central orchestrator for the data pipeline recovery system.
 * It receives monitoring alerts about pipeline failures and intelligently determines
 * the appropriate remediation strategy before enqueuing recovery tasks.
 * 
 * Key responsibilities:
 * - Process incoming webhook notifications from Cloud Monitoring
 * - Analyze failure patterns and determine recovery strategies
 * - Enqueue recovery tasks in Cloud Tasks with proper retry configuration
 * - Maintain audit logs for troubleshooting and optimization
 */

const {CloudTasksClient} = require('@google-cloud/tasks');
const {Logging} = require('@google-cloud/logging');

// Initialize Google Cloud clients
const tasksClient = new CloudTasksClient();
const logging = new Logging();
const log = logging.log('pipeline-controller');

/**
 * Main entry point for handling pipeline alert notifications
 * 
 * @param {Object} req - Express request object containing alert data
 * @param {Object} res - Express response object for HTTP response
 */
exports.handlePipelineAlert = async (req, res) => {
  try {
    const alertData = req.body;
    
    // Extract pipeline failure details from monitoring alert
    const pipelineId = alertData.incident?.resource?.labels?.pipeline_id || 'unknown';
    const failureType = alertData.incident?.condition_name || 'general_failure';
    const severity = alertData.incident?.state || 'OPEN';
    const timestamp = new Date().toISOString();
    
    // Log the incoming alert for audit and debugging
    await log.write(log.entry('INFO', {
      message: 'Processing pipeline failure alert',
      pipelineId,
      failureType,
      severity,
      timestamp,
      alertData: JSON.stringify(alertData, null, 2)
    }));
    
    // Determine the appropriate recovery strategy based on failure type
    const recoveryAction = determineRecoveryAction(failureType);
    
    // Create comprehensive recovery task payload
    const taskPayload = {
      pipelineId,
      failureType,
      recoveryAction,
      attemptCount: 0,
      timestamp,
      metadata: {
        severity,
        alertSource: 'cloud-monitoring',
        originalAlert: alertData
      }
    };
    
    // Enqueue the recovery task with intelligent scheduling
    await enqueueRecoveryTask(taskPayload);
    
    // Send success response
    res.status(200).json({
      success: true,
      message: 'Recovery task enqueued successfully',
      pipelineId,
      recoveryAction,
      taskId: `recovery-${pipelineId}-${Date.now()}`
    });
    
  } catch (error) {
    // Log detailed error information for debugging
    await log.write(log.entry('ERROR', {
      message: 'Failed to process pipeline alert',
      error: error.message,
      stack: error.stack,
      requestBody: JSON.stringify(req.body, null, 2)
    }));
    
    // Send error response
    res.status(500).json({
      success: false,
      message: 'Error processing alert',
      error: error.message
    });
  }
};

/**
 * Determine the appropriate recovery action based on failure type
 * 
 * @param {string} failureType - Type of pipeline failure detected
 * @returns {string} Recovery action strategy
 */
function determineRecoveryAction(failureType) {
  // Mapping of failure types to recovery strategies
  const recoveryMap = {
    'sql_error': 'retry_with_validation',
    'resource_exhausted': 'retry_with_delay',
    'permission_denied': 'escalate_to_admin',
    'timeout_error': 'retry_with_extended_timeout',
    'data_validation_error': 'retry_with_data_cleanup',
    'dependency_failure': 'retry_with_dependency_check',
    'general_failure': 'standard_retry'
  };
  
  return recoveryMap[failureType] || 'standard_retry';
}

/**
 * Enqueue recovery task in Cloud Tasks with appropriate configuration
 * 
 * @param {Object} payload - Task payload containing recovery information
 */
async function enqueueRecoveryTask(payload) {
  try {
    // Construct the Cloud Tasks queue path
    const queuePath = tasksClient.queuePath(
      process.env.PROJECT_ID || '${project_id}',
      process.env.REGION || '${region}',
      process.env.TASK_QUEUE || '${task_queue}'
    );
    
    // Calculate intelligent delay based on failure type and attempt count
    const delaySeconds = calculateTaskDelay(payload.failureType, payload.attemptCount);
    
    // Create the task configuration
    const task = {
      httpRequest: {
        httpMethod: 'POST',
        url: process.env.WORKER_FUNCTION_URL,
        headers: {
          'Content-Type': 'application/json',
        },
        body: Buffer.from(JSON.stringify(payload)).toString('base64'),
      },
      scheduleTime: {
        seconds: Math.floor(Date.now() / 1000) + delaySeconds,
      },
    };
    
    // Add task to the queue
    const [response] = await tasksClient.createTask({
      parent: queuePath,
      task
    });
    
    // Log successful task creation
    await log.write(log.entry('INFO', {
      message: 'Recovery task successfully enqueued',
      taskName: response.name,
      payload,
      delaySeconds,
      scheduledTime: new Date((Math.floor(Date.now() / 1000) + delaySeconds) * 1000).toISOString()
    }));
    
    return response;
    
  } catch (error) {
    // Log task enqueuing errors
    await log.write(log.entry('ERROR', {
      message: 'Failed to enqueue recovery task',
      error: error.message,
      payload
    }));
    
    throw error;
  }
}

/**
 * Calculate intelligent task delay based on failure type and attempt count
 * 
 * @param {string} failureType - Type of pipeline failure
 * @param {number} attemptCount - Number of previous attempts
 * @returns {number} Delay in seconds
 */
function calculateTaskDelay(failureType, attemptCount = 0) {
  // Base delays for different failure types (in seconds)
  const baseDelays = {
    'sql_error': 30,
    'resource_exhausted': 120,
    'permission_denied': 0, // Immediate escalation
    'timeout_error': 60,
    'data_validation_error': 45,
    'dependency_failure': 90,
    'general_failure': 60
  };
  
  const baseDelay = baseDelays[failureType] || 60;
  
  // Apply exponential backoff for retries
  const exponentialMultiplier = Math.pow(2, attemptCount);
  const maxDelay = 600; // Maximum 10-minute delay
  
  return Math.min(baseDelay * exponentialMultiplier, maxDelay);
}