# TP10: API Gateway, SQS, DLQ pipeline asynchrone robuste

resource "aws_sqs_queue" "dlq" {
  name = "esgi-dlq"

  message_retention_seconds = 1209600

  tags = merge(local.common_tags, {
    Name = "esgi-dlq"
  })
}

resource "aws_sqs_queue" "main" {
  name = "esgi-queue"

  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(local.common_tags, {
    Name = "esgi-queue"
  })
}

resource "aws_iam_role" "lambda_api" {
  name = "esgi-lambda-api-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "esgi-lambda-api-role"
  })
}

resource "aws_iam_policy" "lambda_api" {
  name = "esgi-lambda-api-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSSend"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.main.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/esgi-api-handler:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_api" {
  role       = aws_iam_role.lambda_api.name
  policy_arn = aws_iam_policy.lambda_api.arn
}

data "archive_file" "lambda_api" {
  type        = "zip"
  output_path = "${path.module}/lambda_api.zip"

  source {
    content  = <<-EOF
import json
import boto3
import os
import logging
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs = boto3.client('sqs')
QUEUE_URL = os.environ.get('QUEUE_URL')

def handler(event, context):
    logger.info(f"Request ID: {context.aws_request_id}")
    logger.info(f"Event: {json.dumps(event)}")

    try:
        body = json.loads(event.get('body', '{}'))
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid JSON'})
        }

    if 'name' not in body:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Missing required field: name'})
        }

    item_id = str(uuid.uuid4())
    message = {
        'id': item_id,
        'name': body['name'],
        'data': body.get('data', {})
    }

    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(message),
        MessageAttributes={
            'RequestId': {
                'DataType': 'String',
                'StringValue': context.aws_request_id
            }
        }
    )

    logger.info(f"Message sent: {item_id}")

    return {
        'statusCode': 202,
        'body': json.dumps({'id': item_id, 'status': 'queued'})
    }
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "api_handler" {
  function_name    = "esgi-api-handler"
  role             = aws_iam_role.lambda_api.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_api.output_path
  source_code_hash = data.archive_file.lambda_api.output_base64sha256

  timeout     = 10
  memory_size = 128

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.main.url
    }
  }

  tags = merge(local.common_tags, {
    Name = "esgi-api-handler"
  })
}

resource "aws_cloudwatch_log_group" "lambda_api" {
  name              = "/aws/lambda/esgi-api-handler"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "esgi-lambda-api-logs"
  })
}

resource "aws_iam_role" "lambda_consumer" {
  name = "esgi-lambda-consumer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "esgi-lambda-consumer-role"
  })
}

resource "aws_iam_policy" "lambda_consumer" {
  name = "esgi-lambda-consumer-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSReceive"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.main.arn
      },
      {
        Sid    = "DynamoDBWrite"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.orders.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/esgi-queue-consumer:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_consumer" {
  role       = aws_iam_role.lambda_consumer.name
  policy_arn = aws_iam_policy.lambda_consumer.arn
}

data "archive_file" "lambda_consumer" {
  type        = "zip"
  output_path = "${path.module}/lambda_consumer.zip"

  source {
    content  = <<-EOF
import json
import boto3
import os
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
TABLE_NAME = os.environ.get('TABLE_NAME')

def handler(event, context):
    logger.info(f"Request ID: {context.aws_request_id}")
    table = dynamodb.Table(TABLE_NAME)

    for record in event.get('Records', []):
        logger.info(f"Processing message: {record['messageId']}")

        try:
            body = json.loads(record['body'])

            item = {
                'PK': f"ORDER#{body['id']}",
                'SK': f"CREATED#{datetime.utcnow().isoformat()}",
                'GSI1PK': 'STATUS#PENDING',
                'GSI1SK': datetime.utcnow().isoformat(),
                'name': body['name'],
                'data': body.get('data', {}),
                'created_at': datetime.utcnow().isoformat()
            }

            table.put_item(Item=item)
            logger.info(f"SUCCESS: Saved order {body['id']}")

        except Exception as e:
            logger.error(f"ERROR: {str(e)}")
            raise

    return {'status': 'processed', 'count': len(event.get('Records', []))}
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "queue_consumer" {
  function_name    = "esgi-queue-consumer"
  role             = aws_iam_role.lambda_consumer.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_consumer.output_path
  source_code_hash = data.archive_file.lambda_consumer.output_base64sha256

  timeout     = 30
  memory_size = 128

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.orders.name
    }
  }

  tags = merge(local.common_tags, {
    Name = "esgi-queue-consumer"
  })
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.queue_consumer.arn
  batch_size       = 10
}

resource "aws_cloudwatch_log_group" "lambda_consumer" {
  name              = "/aws/lambda/esgi-queue-consumer"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "esgi-lambda-consumer-logs"
  })
}

resource "aws_apigatewayv2_api" "main" {
  name          = "esgi-api"
  protocol_type = "HTTP"

  tags = merge(local.common_tags, {
    Name = "esgi-api"
  })
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api_handler.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_items" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /items"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  tags = merge(local.common_tags, {
    Name = "esgi-api-stage"
  })
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

output "api_endpoint" {
  value       = aws_apigatewayv2_api.main.api_endpoint
  description = "API Gateway endpoint"
}
