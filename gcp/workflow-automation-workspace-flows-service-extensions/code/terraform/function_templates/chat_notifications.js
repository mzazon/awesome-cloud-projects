/**
 * Chat Notifications Cloud Function
 * 
 * This function sends real-time notifications via Google Chat to keep stakeholders
 * informed about workflow progress and status updates.
 * 
 * Environment Variables:
 * - PROJECT_ID: Google Cloud Project ID
 * - ENVIRONMENT: Deployment environment (dev, staging, prod)
 */

const {google} = require('googleapis');

/**
 * HTTP Cloud Function that sends notifications to Google Chat
 * 
 * @param {Object} req - Express request object
 * @param {Object} res - Express response object
 */
exports.sendChatNotification = async (req, res) => {
  try {
    // Validate request body
    const {message, spaceId, threadKey, cardData, priority} = req.body;
    
    if (!message || !spaceId) {
      return res.status(400).json({
        error: 'Missing required parameters: message and spaceId'
      });
    }

    console.log(`Sending Chat notification to space: ${spaceId}`);

    // Initialize Google Chat API client
    const auth = new google.auth.GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/chat.bot']
    });

    const chat = google.chat({version: 'v1', auth});

    // Determine message styling based on priority
    const messageStyle = getMessageStyle(priority);
    
    // Create rich Chat message with cards
    const chatMessage = {
      text: message,
      cards: [{
        header: {
          title: 'Document Workflow Update',
          subtitle: 'Intelligent Processing System',
          imageUrl: 'https://developers.google.com/chat/images/chat-product-icon.png',
          imageStyle: 'IMAGE'
        },
        sections: [{
          widgets: [
            {
              textParagraph: {
                text: `<b>${message}</b>`
              }
            }
          ]
        }]
      }]
    };

    // Add additional card sections if cardData is provided
    if (cardData) {
      const additionalWidgets = [];
      
      // Add workflow details
      if (cardData.workflowId) {
        additionalWidgets.push({
          keyValue: {
            topLabel: 'Workflow ID',
            content: cardData.workflowId,
            contentMultiline: false
          }
        });
      }

      // Add document information
      if (cardData.documentName) {
        additionalWidgets.push({
          keyValue: {
            topLabel: 'Document',
            content: cardData.documentName,
            contentMultiline: false
          }
        });
      }

      // Add status information
      if (cardData.status) {
        additionalWidgets.push({
          keyValue: {
            topLabel: 'Status',
            content: cardData.status,
            contentMultiline: false,
            icon: getStatusIcon(cardData.status)
          }
        });
      }

      // Add timestamp
      additionalWidgets.push({
        keyValue: {
          topLabel: 'Timestamp',
          content: new Date().toLocaleString(),
          contentMultiline: false,
          icon: 'CLOCK'
        }
      });

      // Add action buttons if provided
      if (cardData.actions && cardData.actions.length > 0) {
        const buttons = cardData.actions.map(action => ({
          textButton: {
            text: action.text,
            onClick: {
              openLink: {
                url: action.url
              }
            }
          }
        }));

        additionalWidgets.push({
          buttons: buttons
        });
      }

      // Add additional section with details
      if (additionalWidgets.length > 0) {
        chatMessage.cards[0].sections.push({
          header: 'Details',
          widgets: additionalWidgets
        });
      }
    }

    // Apply message styling
    if (messageStyle.color) {
      chatMessage.cards[0].header.imageStyle = 'AVATAR';
      // Note: Color styling would be applied through card formatting
    }

    // Send message to Google Chat
    const requestParams = {
      parent: `spaces/${spaceId}`,
      requestBody: chatMessage
    };

    // Add thread key if provided for threaded conversations
    if (threadKey) {
      requestParams.threadKey = threadKey;
    }

    let response;
    try {
      response = await chat.spaces.messages.create(requestParams);
      console.log(`Message sent successfully with ID: ${response.data.name}`);
    } catch (error) {
      console.error('Error sending Chat message:', error);
      
      // Handle specific Chat API errors
      if (error.code === 404) {
        return res.status(404).json({
          error: 'Chat space not found or bot not added to space',
          details: error.message
        });
      } else if (error.code === 403) {
        return res.status(403).json({
          error: 'Insufficient permissions to send message to space',
          details: error.message
        });
      }
      
      throw error;
    }

    // Return success response
    res.status(200).json({
      success: true,
      messageId: response.data.name,
      spaceName: response.data.space?.name,
      thread: response.data.thread?.name,
      timestamp: response.data.createTime
    });

  } catch (error) {
    console.error('Unexpected error in chat notification:', error);
    res.status(500).json({
      error: 'Internal server error during chat notification',
      details: error.message,
      timestamp: new Date().toISOString()
    });
  }
};

/**
 * Gets message styling based on priority
 * 
 * @param {string} priority - Message priority (low, normal, high, urgent)
 * @returns {Object} Style configuration object
 */
function getMessageStyle(priority) {
  const styles = {
    urgent: {
      color: '#FF4444',
      icon: 'ERROR'
    },
    high: {
      color: '#FF8800',
      icon: 'WARNING'
    },
    normal: {
      color: '#4285F4',
      icon: 'INFO'
    },
    low: {
      color: '#34A853',
      icon: 'CHECK_CIRCLE'
    }
  };

  return styles[priority] || styles.normal;
}

/**
 * Gets appropriate icon for status
 * 
 * @param {string} status - Status value
 * @returns {string} Icon name
 */
function getStatusIcon(status) {
  const iconMap = {
    'pending': 'CLOCK',
    'processing': 'REFRESH',
    'approved': 'CHECK_CIRCLE',
    'rejected': 'CLOSE',
    'completed': 'DONE',
    'failed': 'ERROR',
    'escalated': 'WARNING'
  };

  return iconMap[status.toLowerCase()] || 'INFO';
}