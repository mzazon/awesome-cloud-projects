/**
 * Approval Webhook Cloud Function
 * 
 * This function handles approval decisions from stakeholders and updates workflow state.
 * It processes approval responses and triggers appropriate follow-up actions.
 * 
 * Environment Variables:
 * - TOPIC_NAME: Pub/Sub topic for publishing approval events
 * - PROJECT_ID: Google Cloud Project ID
 */

const {PubSub} = require('@google-cloud/pubsub');
const {google} = require('googleapis');

// Initialize Google Cloud clients
const pubsub = new PubSub();

/**
 * HTTP Cloud Function that handles approval decisions
 * 
 * @param {Object} req - Express request object
 * @param {Object} res - Express response object
 */
exports.handleApproval = async (req, res) => {
  try {
    // Validate request body
    const {workflowId, approverEmail, decision, comments, metadata} = req.body;
    
    if (!workflowId || !approverEmail || !decision) {
      return res.status(400).json({
        error: 'Missing required parameters: workflowId, approverEmail, and decision'
      });
    }

    // Validate approval decision
    const validDecisions = ['approved', 'rejected', 'needs_revision', 'escalated'];
    if (!validDecisions.includes(decision)) {
      return res.status(400).json({
        error: `Invalid decision value. Must be one of: $${validDecisions.join(', ')}`
      });
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(approverEmail)) {
      return res.status(400).json({
        error: 'Invalid email format for approverEmail'
      });
    }

    console.log(`Processing approval decision: $${decision} for workflow: $${workflowId} by $${approverEmail}`);

    // Create comprehensive approval event
    const approvalEvent = {
      workflowId: workflowId,
      approver: {
        email: approverEmail,
        timestamp: new Date().toISOString(),
        ipAddress: req.ip || 'unknown',
        userAgent: req.get('User-Agent') || 'unknown'
      },
      decision: {
        value: decision,
        comments: comments || '',
        timestamp: new Date().toISOString(),
        confidence: metadata?.confidence || 'high'
      },
      processingStage: 'approval_decision',
      source: 'approval-webhook',
      version: '1.0',
      metadata: {
        priority: metadata?.priority || 'normal',
        escalationLevel: metadata?.escalationLevel || 0,
        ...metadata
      }
    };

    // Determine next action based on decision
    let nextAction = 'completed';
    switch (decision) {
      case 'approved':
        nextAction = 'finalize_approval';
        break;
      case 'rejected':
        nextAction = 'handle_rejection';
        break;
      case 'needs_revision':
        nextAction = 'request_revision';
        break;
      case 'escalated':
        nextAction = 'escalate_approval';
        break;
    }
    
    approvalEvent.nextAction = nextAction;

    // Publish approval decision to Pub/Sub
    const topicName = '${topic_name}';
    const dataBuffer = Buffer.from(JSON.stringify(approvalEvent));
    
    try {
      const messageId = await pubsub.topic(topicName).publish(dataBuffer, {
        source: 'approval-webhook',
        workflowId: workflowId,
        decision: decision,
        approver: approverEmail,
        nextAction: nextAction
      });
      
      console.log(`Published approval message $${messageId} to topic $${topicName}`);
    } catch (error) {
      console.error('Error publishing approval to Pub/Sub:', error);
      return res.status(500).json({
        error: 'Failed to publish approval event',
        details: error.message
      });
    }

    // Optional: Update Google Sheets tracking (if configured)
    try {
      await updateSheetTracking(approvalEvent);
    } catch (error) {
      console.warn('Failed to update sheet tracking:', error);
      // Don't fail the request if sheet update fails
    }

    // Log successful approval processing
    console.log(`Approval $${decision} recorded successfully for workflow: $${workflowId}`);

    // Return success response
    res.status(200).json({
      success: true,
      workflowId: workflowId,
      decision: decision,
      nextAction: nextAction,
      message: `Approval decision '$${decision}' recorded successfully`,
      timestamp: approvalEvent.approver.timestamp
    });

  } catch (error) {
    console.error('Unexpected error in approval processing:', error);
    res.status(500).json({
      error: 'Internal server error during approval processing',
      details: error.message,
      timestamp: new Date().toISOString()
    });
  }
};

/**
 * Updates Google Sheets with approval tracking data
 * 
 * @param {Object} approvalEvent - The approval event data
 */
async function updateSheetTracking(approvalEvent) {
  try {
    // Initialize Google Sheets API client
    const auth = new google.auth.GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/spreadsheets']
    });

    const sheets = google.sheets({version: 'v4', auth});
    
    // Configuration for tracking sheet (would be configurable via environment variables)
    const spreadsheetId = process.env.TRACKING_SHEET_ID;
    if (!spreadsheetId) {
      console.warn('TRACKING_SHEET_ID not configured, skipping sheet update');
      return;
    }

    // Prepare row data for sheet append
    const rowData = [
      approvalEvent.workflowId,
      approvalEvent.approver.email,
      approvalEvent.decision.value,
      approvalEvent.decision.comments,
      approvalEvent.approver.timestamp,
      approvalEvent.nextAction,
      approvalEvent.metadata.priority || 'normal'
    ];

    // Append data to tracking sheet
    const range = process.env.TRACKING_SHEET_RANGE || 'Approvals!A:G';
    await sheets.spreadsheets.values.append({
      spreadsheetId: spreadsheetId,
      range: range,
      valueInputOption: 'USER_ENTERED',
      requestBody: {
        values: [rowData]
      }
    });

    console.log(`Updated tracking sheet for workflow: $${approvalEvent.workflowId}`);

  } catch (error) {
    console.error('Error updating tracking sheet:', error);
    throw error;
  }
}