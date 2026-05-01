# ==========
# Security Group
# ==========

resource "aws_security_group" "ar_sg_victim" {
  name        = "ar-sg-victim"
  description = "SSH autorise en entree pour la victime"
  vpc_id      = aws_vpc.ar_vpc_main.id
  
  # trivy:ignore:AVD-AWS-0107 - Risque accepte : Honeypot expose pour le NIDS
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


resource "aws_security_group" "ar_sg_nids" {
  name        = "ar-sg-nids"
  description = "Autorise la reception du trafic miroir (VXLAN) pour Suricata"
  vpc_id      = aws_vpc.ar_vpc_main.id

  # Autorise le tunnel depuis le subnet de la victime
  ingress {
    description = "VPC Traffic Mirroring (VXLAN)"
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = [aws_subnet.ar_subnet_public.cidr_block]
  }

  # administration ssh depuis la victime (bastion)
  ingress {
    description = "SSH depuis EC2 instance connect"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.ar_subnet_public.cidr_block]
  }

  # ingress {
  #   description = "Ping"
  #   from_port   = -1
  #   to_port     = -1
  #   protocol    = "icmp"
  #   cidr_blocks = [aws_subnet.ar_subnet_public.cidr_block]
  # }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ar-sg-nids"
  }
}