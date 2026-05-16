# IAM
# ==========

# Droits CloudWatch pour le NIDS

# autorise l'EC2 a assumer ce role
resource "aws_iam_role" "ar_nids_cw_role" {
  name = "ar-nids-cw-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

# Attachement de la policy CW
resource "aws_iam_role_policy_attachment" "ar_nids_cw_policy" {
  role       = aws_iam_role.ar_nids_cw_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# profil d'Instance (pour attacher le role au nIDS)
resource "aws_iam_instance_profile" "ar_nids_profile" {
  name = "ar-nids-profile"
  role = aws_iam_role.ar_nids_cw_role.name
}