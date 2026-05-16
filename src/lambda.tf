# Logs de Lambda
resource "aws_cloudwatch_log_group" "ar_cw_suricata" {
  name              = "/secops/suricata/alerts"
  
  # inutile de garder plus dans notre cas de figure
  retention_in_days = 14 

  tags = {
    Name = "ar-suricata-logs"
  }
}

# Code de la fonction
data "archive_file" "ar_lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

# Roles
resource "aws_iam_role" "ar_lambda_exec_role" {
  name = "ar-lambda-secops-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ar_lambda_logs" {
  role       = aws_iam_role.ar_lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Fonction Lambda
resource "aws_lambda_function" "ar_secops_lambda" {
  filename      = data.archive_file.ar_lambda_zip.output_path
  function_name = "ar-secops-alert-processor"
  role          = aws_iam_role.ar_lambda_exec_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 10 # secondes

  source_code_hash = data.archive_file.ar_lambda_zip.output_base64sha256
}

# Bridge de CW -> Lambda
resource "aws_lambda_permission" "ar_allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatchLogs"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ar_secops_lambda.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.ar_cw_suricata.arn}:*"
}

# Filtre
resource "aws_cloudwatch_log_subscription_filter" "ar_cw_to_lambda" {
  name            = "ar-suricata-alert-filter"
  log_group_name  = aws_cloudwatch_log_group.ar_cw_suricata.name
  destination_arn = aws_lambda_function.ar_secops_lambda.arn
  
  # Déclenchement uniquement pour les alertes
  filter_pattern  = "{ $.event_type = \"alert\" }"

  depends_on = [aws_lambda_permission.ar_allow_cloudwatch]
}