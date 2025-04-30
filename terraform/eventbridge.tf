resource "aws_cloudwatch_event_rule" "ec2_running_rule" {
  name        = "EC2InstanceRunningRule"
  description = "Regra para capturar instancias EC2 que entram no estado 'running'"
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
    detail = {
      state         = ["running"]
      "instance-id" = [{ "exists" : true }]
      platform      = [{ "exists" : false }]
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule = aws_cloudwatch_event_rule.ec2_running_rule.name
  arn  = aws_lambda_function.auto_join_linux_function.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_join_linux_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_running_rule.arn
}