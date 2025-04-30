resource "aws_iam_role" "lambda_role" {
  name = "lambda_execution_role_join"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "lambda_logging_policy" {
  name        = "LambdaLoggingPolicy"
  description = "Permissões para Lambda enviar logs ao CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_vpc_access" {
  name        = "LambdaVPCAccessPolicy"
  description = "Policy para permitir que a Lambda acesse a VPC"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ssm:DescribeInstanceInformation",
          "ssm:GetParameter",
          "ssm:ListCommandInvocations",
          "ssm:ListCommands",
          "ssm:SendCommand"
        ]
        Resource = "*"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "lambda_logging_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_logging_policy.arn
}

resource "aws_iam_policy_attachment" "lambda_policy_execution" {
  name       = "lambda_policy_attachment"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access_attach" {
  policy_arn = aws_iam_policy.lambda_vpc_access.arn
  role       = aws_iam_role.lambda_role.name
}

resource "aws_cloudwatch_log_group" "log_group_lambda" {
  name              = "/aws/lambda/auto_join_linux_function"
  retention_in_days = 5
}

resource "aws_lambda_function" "auto_join_linux_function" {
  filename         = "../scripts/lambda_function.zip"
  function_name = "auto_join_linux_function"
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn
  vpc_config {
    subnet_ids         = var.subnet_lambda
    security_group_ids = var.security_group_lambda
  }
  logging_config {
    log_format = "Text"
  }
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  source_code_hash = filebase64sha256("../scripts/lambda_function.zip")

}

