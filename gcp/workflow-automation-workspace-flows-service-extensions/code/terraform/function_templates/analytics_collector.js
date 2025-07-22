/**
 * Analytics Collector Cloud Function
 * 
 * This function collects workflow analytics and creates custom metrics for monitoring
 * and performance optimization. It processes Pub/Sub messages and generates insights.
 * 
 * Environment Variables:
 * - GCP_PROJECT: Google Cloud Project ID
 * - ENVIRONMENT: Deployment environment (dev, staging, prod)
 */

const {PubSub} = require('@google-cloud/pubsub');
const monitoring = require('@google-cloud/monitoring');

// Initialize Google Cloud clients
const client = new monitoring.MetricServiceClient();
const pubsub = new PubSub();

/**
 * Pub/Sub triggered Cloud Function that collects workflow analytics
 * 
 * @param {Object} pubsubMessage - Pub/Sub message object
 * @param {Object} context - Function context
 */
exports.collectAnalytics = async (pubsubMessage, context) => {
  try {
    // Decode and parse the Pub/Sub message
    let messageData;
    try {
      const messageString = Buffer.from(pubsubMessage.data, 'base64').toString();
      messageData = JSON.parse(messageString);
    } catch (error) {
      console.error('Error parsing Pub/Sub message:', error);
      return; // Skip invalid messages
    }

    console.log(`Processing analytics for workflow: ${messageData.workflowId || 'unknown'}`);

    // Extract analytics data from the message
    const analyticsData = extractAnalyticsData(messageData);
    
    // Create custom metrics for workflow analysis
    await Promise.all([
      createProcessingTimeMetric(analyticsData),
      createDocumentTypeMetric(analyticsData),
      createWorkflowStageMetric(analyticsData),
      createErrorRateMetric(analyticsData)
    ]);

    // Store detailed analytics in structured logging
    await logDetailedAnalytics(analyticsData);

    console.log(`Analytics data recorded for workflow: ${analyticsData.workflowId}`);

  } catch (error) {
    console.error('Error in analytics collection:', error);
    // Don't throw error to avoid infinite retry loops
  }
};

/**
 * Extracts relevant analytics data from workflow messages
 * 
 * @param {Object} messageData - Raw message data from Pub/Sub
 * @returns {Object} Structured analytics data
 */
function extractAnalyticsData(messageData) {
  const now = Date.now();
  const messageTimestamp = messageData.timestamp ? new Date(messageData.timestamp).getTime() : now;
  
  return {
    workflowId: messageData.workflowId || 'unknown',
    processingStage: messageData.processingStage || 'unknown',
    documentType: messageData.metadata?.document_type || 'unknown',
    department: messageData.metadata?.department || 'unknown',
    priority: messageData.metadata?.priority || 'normal',
    source: messageData.source || 'unknown',
    timestamp: messageTimestamp,
    processingTime: now - messageTimestamp,
    fileSize: messageData.metadata?.size || 0,
    contentType: messageData.metadata?.contentType || 'unknown',
    success: !messageData.error,
    errorType: messageData.error?.type || null,
    version: messageData.version || '1.0'
  };
}

/**
 * Creates processing time metric for monitoring
 * 
 * @param {Object} analyticsData - Analytics data object
 */
async function createProcessingTimeMetric(analyticsData) {
  try {
    const projectId = process.env.GCP_PROJECT;
    const projectPath = client.projectPath(projectId);

    const timeSeriesData = {
      metric: {
        type: 'custom.googleapis.com/workflow/processing_time',
        labels: {
          document_type: analyticsData.documentType,
          processing_stage: analyticsData.processingStage,
          department: analyticsData.department,
          priority: analyticsData.priority,
          environment: process.env.ENVIRONMENT || 'dev'
        }
      },
      resource: {
        type: 'global',
        labels: {
          project_id: projectId
        }
      },
      points: [{
        interval: {
          endTime: {
            seconds: Math.floor(Date.now() / 1000)
          }
        },
        value: {
          doubleValue: analyticsData.processingTime
        }
      }]
    };

    await client.createTimeSeries({
      name: projectPath,
      timeSeries: [timeSeriesData]
    });

  } catch (error) {
    console.error('Error creating processing time metric:', error);
  }
}

/**
 * Creates document type distribution metric
 * 
 * @param {Object} analyticsData - Analytics data object
 */
async function createDocumentTypeMetric(analyticsData) {
  try {
    const projectId = process.env.GCP_PROJECT;
    const projectPath = client.projectPath(projectId);

    const timeSeriesData = {
      metric: {
        type: 'custom.googleapis.com/workflow/document_count',
        labels: {
          document_type: analyticsData.documentType,
          department: analyticsData.department,
          content_type: analyticsData.contentType,
          environment: process.env.ENVIRONMENT || 'dev'
        }
      },
      resource: {
        type: 'global',
        labels: {
          project_id: projectId
        }
      },
      points: [{
        interval: {
          endTime: {
            seconds: Math.floor(Date.now() / 1000)
          }
        },
        value: {
          int64Value: 1 // Count of documents
        }
      }]
    };

    await client.createTimeSeries({
      name: projectPath,
      timeSeries: [timeSeriesData]
    });

  } catch (error) {
    console.error('Error creating document type metric:', error);
  }
}

/**
 * Creates workflow stage progression metric
 * 
 * @param {Object} analyticsData - Analytics data object
 */
async function createWorkflowStageMetric(analyticsData) {
  try {
    const projectId = process.env.GCP_PROJECT;
    const projectPath = client.projectPath(projectId);

    const timeSeriesData = {
      metric: {
        type: 'custom.googleapis.com/workflow/stage_progression',
        labels: {
          processing_stage: analyticsData.processingStage,
          source: analyticsData.source,
          priority: analyticsData.priority,
          environment: process.env.ENVIRONMENT || 'dev'
        }
      },
      resource: {
        type: 'global',
        labels: {
          project_id: projectId
        }
      },
      points: [{
        interval: {
          endTime: {
            seconds: Math.floor(Date.now() / 1000)
          }
        },
        value: {
          int64Value: 1 // Count of stage transitions
        }
      }]
    };

    await client.createTimeSeries({
      name: projectPath,
      timeSeries: [timeSeriesData]
    });

  } catch (error) {
    console.error('Error creating workflow stage metric:', error);
  }
}

/**
 * Creates error rate metric for monitoring failures
 * 
 * @param {Object} analyticsData - Analytics data object
 */
async function createErrorRateMetric(analyticsData) {
  try {
    const projectId = process.env.GCP_PROJECT;
    const projectPath = client.projectPath(projectId);

    const timeSeriesData = {
      metric: {
        type: 'custom.googleapis.com/workflow/error_rate',
        labels: {
          success: analyticsData.success.toString(),
          error_type: analyticsData.errorType || 'none',
          processing_stage: analyticsData.processingStage,
          environment: process.env.ENVIRONMENT || 'dev'
        }
      },
      resource: {
        type: 'global',
        labels: {
          project_id: projectId
        }
      },
      points: [{
        interval: {
          endTime: {
            seconds: Math.floor(Date.now() / 1000)
          }
        },
        value: {
          int64Value: 1 // Count of operations
        }
      }]
    };

    await client.createTimeSeries({
      name: projectPath,
      timeSeries: [timeSeriesData]
    });

  } catch (error) {
    console.error('Error creating error rate metric:', error);
  }
}

/**
 * Logs detailed analytics data for further analysis
 * 
 * @param {Object} analyticsData - Analytics data object
 */
async function logDetailedAnalytics(analyticsData) {
  try {
    // Structure detailed analytics log entry
    const logEntry = {
      severity: 'INFO',
      timestamp: new Date().toISOString(),
      labels: {
        component: 'workflow-analytics',
        version: analyticsData.version,
        environment: process.env.ENVIRONMENT || 'dev'
      },
      jsonPayload: {
        workflowId: analyticsData.workflowId,
        processingStage: analyticsData.processingStage,
        documentMetrics: {
          type: analyticsData.documentType,
          size: analyticsData.fileSize,
          contentType: analyticsData.contentType
        },
        performance: {
          processingTime: analyticsData.processingTime,
          timestamp: analyticsData.timestamp
        },
        business: {
          department: analyticsData.department,
          priority: analyticsData.priority
        },
        technical: {
          source: analyticsData.source,
          success: analyticsData.success,
          errorType: analyticsData.errorType
        }
      }
    };

    // Use structured logging for Cloud Logging
    console.log(JSON.stringify(logEntry));

  } catch (error) {
    console.error('Error logging detailed analytics:', error);
  }
}