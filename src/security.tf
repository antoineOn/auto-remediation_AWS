# ==========
# Security Group
# ==========

resource "aws_security_group" "ar_sg_victim" {
  name        = "ar-sg-victim"
  description = "SSH autorise en entree pour la victime"
  vpc_id      = aws_vpc.ar_vpc_main.id

  ingress {
    description = "SSH depuis Internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ar-sg-victim"
  }
}