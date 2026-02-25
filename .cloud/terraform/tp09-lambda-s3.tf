# TP9: Lambda trigger S3, rôles minimaux, logs et gestion d'erreurs

resource "aws_iam_role" "lambda_s3_processor" {
  name = "esgi-lambda-s3-processor-role"

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
    Name = "esgi-lambda-s3-processor-role"
  })
}

resource "aws_iam_policy" "lambda_s3_processor" {
  name = "esgi-lambda-s3-processor-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadInputPrefix"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.main.arn}/input/*"
      },
      {
        Sid    = "WriteOutputPrefix"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.main.arn}/output/*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/esgi-s3-processor:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3_processor" {
  role       = aws_iam_role.lambda_s3_processor.name
  policy_arn = aws_iam_policy.lambda_s3_processor.arn
}

data "archive_file" "lambda_s3_processor" {
  type        = "zip"
  output_path = "${path.module}/lambda_s3_processor.zip"

  source {
    content  = <<-EOF
import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')

ALLOWED_TYPES = ['.txt', '.json', '.csv', '.png', '.jpg', '.jpeg']
MAX_SIZE_MB = 10

def handler(event, context):
    logger.info(f"Event: {json.dumps(event)}")

    for record in event.get('Records', []):
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        size = record['s3']['object'].get('size', 0)

        logger.info(f"Processing: s3://{bucket}/{key}, size: {size}")

        ext = os.path.splitext(key)[1].lower()
        if ext not in ALLOWED_TYPES:
            logger.error(f"REJECTED: Invalid file type {ext}")
            return {'status': 'rejected', 'reason': f'Invalid type: {ext}'}

        size_mb = size / (1024 * 1024)
        if size_mb > MAX_SIZE_MB:
            logger.error(f"REJECTED: File too large {size_mb}MB")
            return {'status': 'rejected', 'reason': f'Too large: {size_mb}MB'}

        output_key = key.replace('input/', 'output/') + '.processed'
        summary = {
            'original_key': key,
            'size_bytes': size,
            'file_type': ext,
            'status': 'processed'
        }

        s3.put_object(
            Bucket=bucket,
            Key=output_key,
            Body=json.dumps(summary),
            ContentType='application/json'
        )

        logger.info(f"SUCCESS: Created {output_key}")

    return {'status': 'success', 'request_id': context.aws_request_id}
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "s3_processor" {
  function_name    = "esgi-s3-processor"
  role             = aws_iam_role.lambda_s3_processor.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_s3_processor.output_path
  source_code_hash = data.archive_file.lambda_s3_processor.output_base64sha256

  timeout     = 30
  memory_size = 128

  tags = merge(local.common_tags, {
    Name = "esgi-s3-processor"
  })
}

resource "aws_lambda_permission" "s3_trigger" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.main.arn
}

resource "aws_s3_bucket_notification" "lambda_trigger" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
  }

  depends_on = [aws_lambda_permission.s3_trigger]
}

resource "aws_cloudwatch_log_group" "lambda_s3_processor" {
  name              = "/aws/lambda/esgi-s3-processor"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "esgi-lambda-s3-processor-logs"
  })
}
