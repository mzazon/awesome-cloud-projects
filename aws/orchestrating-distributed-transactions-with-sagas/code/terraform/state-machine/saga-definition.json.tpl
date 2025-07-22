{
  "Comment": "Saga Pattern Orchestrator for E-commerce Transactions",
  "StartAt": "PlaceOrder",
  "States": {
    "PlaceOrder": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${order_function_arn}",
        "Payload": {
          "tableName": "${order_table_name}",
          "customerId.$": "$.customerId",
          "productId.$": "$.productId",
          "quantity.$": "$.quantity"
        }
      },
      "ResultPath": "$.orderResult",
      "Next": "CheckOrderStatus",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "OrderFailed",
          "ResultPath": "$.error"
        }
      ]
    },
    "CheckOrderStatus": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.orderResult.Payload.status",
          "StringEquals": "ORDER_PLACED",
          "Next": "ReserveInventory"
        }
      ],
      "Default": "OrderFailed"
    },
    "ReserveInventory": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${inventory_function_arn}",
        "Payload": {
          "tableName": "${inventory_table_name}",
          "productId.$": "$.productId",
          "quantity.$": "$.quantity"
        }
      },
      "ResultPath": "$.inventoryResult",
      "Next": "CheckInventoryStatus",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "CancelOrder",
          "ResultPath": "$.error"
        }
      ]
    },
    "CheckInventoryStatus": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.inventoryResult.Payload.status",
          "StringEquals": "INVENTORY_RESERVED",
          "Next": "ProcessPayment"
        }
      ],
      "Default": "CancelOrder"
    },
    "ProcessPayment": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${payment_function_arn}",
        "Payload": {
          "tableName": "${payment_table_name}",
          "orderId.$": "$.orderResult.Payload.orderId",
          "customerId.$": "$.customerId",
          "amount.$": "$.amount"
        }
      },
      "ResultPath": "$.paymentResult",
      "Next": "CheckPaymentStatus",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "RevertInventory",
          "ResultPath": "$.error"
        }
      ]
    },
    "CheckPaymentStatus": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.paymentResult.Payload.status",
          "StringEquals": "PAYMENT_COMPLETED",
          "Next": "SendSuccessNotification"
        }
      ],
      "Default": "RevertInventory"
    },
    "SendSuccessNotification": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${notification_function_arn}",
        "Payload": {
          "topicArn": "${sns_topic_arn}",
          "subject": "Order Completed Successfully",
          "message": {
            "orderId.$": "$.orderResult.Payload.orderId",
            "customerId.$": "$.customerId",
            "status": "SUCCESS",
            "details": "Your order has been processed successfully"
          }
        }
      },
      "ResultPath": "$.notificationResult",
      "Next": "Success"
    },
    "Success": {
      "Type": "Pass",
      "Result": {
        "status": "SUCCESS",
        "message": "Transaction completed successfully"
      },
      "End": true
    },
    "RevertInventory": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${revert_inventory_arn}",
        "Payload": {
          "tableName": "${inventory_table_name}",
          "productId.$": "$.productId",
          "quantity.$": "$.quantity"
        }
      },
      "ResultPath": "$.revertResult",
      "Next": "CancelOrder",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "CompensationFailed",
          "ResultPath": "$.compensationError"
        }
      ]
    },
    "CancelOrder": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${cancel_order_arn}",
        "Payload": {
          "tableName": "${order_table_name}",
          "orderId.$": "$.orderResult.Payload.orderId"
        }
      },
      "ResultPath": "$.cancelResult",
      "Next": "RefundPayment",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "CompensationFailed",
          "ResultPath": "$.compensationError"
        }
      ]
    },
    "RefundPayment": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${refund_payment_arn}",
        "Payload": {
          "tableName": "${payment_table_name}",
          "paymentId.$": "$.paymentResult.Payload.paymentId",
          "orderId.$": "$.orderResult.Payload.orderId",
          "customerId.$": "$.customerId",
          "amount.$": "$.amount"
        }
      },
      "ResultPath": "$.refundResult",
      "Next": "SendFailureNotification",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "CompensationFailed",
          "ResultPath": "$.compensationError"
        }
      ]
    },
    "SendFailureNotification": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${notification_function_arn}",
        "Payload": {
          "topicArn": "${sns_topic_arn}",
          "subject": "Order Processing Failed",
          "message": {
            "orderId.$": "$.orderResult.Payload.orderId",
            "customerId.$": "$.customerId",
            "status": "FAILED",
            "details": "Your order could not be processed and has been cancelled"
          }
        }
      },
      "ResultPath": "$.notificationResult",
      "Next": "TransactionFailed"
    },
    "OrderFailed": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${notification_function_arn}",
        "Payload": {
          "topicArn": "${sns_topic_arn}",
          "subject": "Order Creation Failed",
          "message": {
            "customerId.$": "$.customerId",
            "status": "FAILED",
            "details": "Order creation failed"
          }
        }
      },
      "ResultPath": "$.notificationResult",
      "Next": "TransactionFailed"
    },
    "TransactionFailed": {
      "Type": "Pass",
      "Result": {
        "status": "FAILED",
        "message": "Transaction failed and compensations completed"
      },
      "End": true
    },
    "CompensationFailed": {
      "Type": "Pass",
      "Result": {
        "status": "COMPENSATION_FAILED",
        "message": "Transaction failed and compensation actions also failed"
      },
      "End": true
    }
  }
}