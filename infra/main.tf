resource "aws_s3_bucket" "bucket" {
  bucket = "iankyslytsya.com"
  acl    = null
  force_destroy                = null

  grant {
    id          = "2232876dfa25bfe142b8d9c04ef853053b60e7dcc75a84e2d280b50c39a19f67"
    permissions = ["FULL_CONTROL"]
    type        = "CanonicalUser"
    uri         = ""
  }
  logging {
    target_bucket = "logs.iankyslytsya.com"
    target_prefix = "logs/"
  }

  object_lock_enabled        = false
  policy = <<POLICY
{
  "Statement": [
    {
      "Action": "s3:GetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Resource": "arn:aws:s3:::iankyslytsya.com/*",
      "Sid": "MakeItPublic"
    }
  ],
  "Version": "2012-10-17"
}
POLICY

  request_payer              = "BucketOwner"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id   = ""
        sse_algorithm = "AES256"
      }
      bucket_key_enabled  = true
    }
  }

  tags      = {}
  tags_all  = {}

  versioning {
    enabled    = false
    mfa_delete = false
  }

  website {
    index_document                 = "resume.html"
  }
}

resource "aws_s3_bucket_ownership_controls" "bucket_ownership" {
  bucket = "iankyslytsya.com"

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "bucket_public_access_block" {
  bucket = "iankyslytsya.com"

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "bucket_website_configuration" {
  bucket                = "iankyslytsya.com"
  index_document {
    suffix = "resume.html"
  }
}

resource "aws_s3_bucket" "www_bucket" {
  bucket = "www.iankyslytsya.com"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "AES256"
        kms_master_key_id = ""
      }
      bucket_key_enabled = true
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "www_bucket_ownership_controls" {
  bucket = "www.iankyslytsya.com"

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_dynamodb_table" "table" {
  name           = "VisitorCounterTable"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "visitor_id"

  attribute {
    name = "visitor_id"
    type = "S"
  }

}

resource "aws_apigatewayv2_api" "api" {
  name          = "CloudResumeFunction-API"
  protocol_type = "HTTP"
  description   = "API as trigger for CloudResume Lambda"

  cors_configuration {
    allow_credentials = false
    allow_origins     = ["*"]
  }
}

resource "aws_apigatewayv2_stage" "stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "beta"
  auto_deploy = true
  stage_variables = {
    lambda_arn = aws_lambda_function.CloudResumeFunctionTF.arn
  }
}

resource "aws_apigatewayv2_route" "route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id          = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.CloudResumeFunctionTF.invoke_arn
  integration_method = "POST"
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "CloudResumeFunction-role-tf"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "lambda_execution_policy" {
  name        = "CloudResumeFunction-policy"
  description = "Policy for Lambda execution role"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:BatchGetItem",
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:BatchWriteItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem"
      ],
      "Resource": "arn:aws:dynamodb:eu-west-1:916840092047:table/VisitorCounterTable"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_execution_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_execution_policy.arn
}

resource "aws_lambda_function" "CloudResumeFunctionTF" {
  filename         = data.archive_file.zip.output_path
  source_code_hash = data.archive_file.zip.output_base64sha256
  function_name    = "CloudResumeFunctionTF"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "func.lambda_handler"
  runtime          = "python3.8"
}


data "archive_file" "zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/"
  output_path = "${path.module}/packedlambda.zip"
}
