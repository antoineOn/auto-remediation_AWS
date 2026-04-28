# Variables

variable "aws_region" {
  description = "La région AWS de déploiement"
  type        = string
  default     = "eu-west-3"
}

# VPC Principal
resource "aws_vpc" "ar_vpc_main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "ar-vpc-secops"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "ar_igw_main" {
  vpc_id = aws_vpc.ar_vpc_main.id

  tags = {
    Name = "ar-igw"
  }
}

# ==========
# SUBNETS
# ==========

# Public
resource "aws_subnet" "ar_subnet_public" {
  vpc_id                  = aws_vpc.ar_vpc_main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "ar-subnet-public-victim"
  }
}

# Prive
resource "aws_subnet" "ar_subnet_private" {
  vpc_id                  = aws_vpc.ar_vpc_main.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "ar-subnet-private-nids"
  }
}

# ==========
# Routage
# ==========

# Table de routage du subnet Public : lien IGW
resource "aws_route_table" "ar_rt_public" {
  vpc_id = aws_vpc.ar_vpc_main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ar_igw_main.id
  }

  tags = {
    Name = "ar-rt-public"
  }
}

# Association
resource "aws_route_table_association" "ar_rt_assoc_public" {
  subnet_id      = aws_subnet.ar_subnet_public.id
  route_table_id = aws_route_table.ar_rt_public.id
}

# ==========
# NACL
# ==========

# NACL attachée au Subnet Public

resource "aws_network_acl" "ar_nacl_public" {
  vpc_id     = aws_vpc.ar_vpc_main.id
  subnet_ids = [aws_subnet.ar_subnet_public.id]

  # Autoriser tout le trafic entrant
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  # Autoriser tout le trafic sortant
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "ar-nacl-public"
  }
}


# =========
# Instances EC2
# =========

# setup connexion SSH - on utilise la meme cle ssh pour les deux instances EC2
resource "aws_key_pair" "ar_key_pair" {
  key_name   = "ar-ssh-key"
  public_key = file("/home/ubuntu/.ssh/id_ed25519.pub") 
}

# Victime (Ubuntu 24)
# ==========

# Recherche d'AMI
data "aws_ami" "ubuntu_24" {
  most_recent = true
  owners      = ["099720109477"] # ID Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "ar_ec2_victim" {
  ami           = data.aws_ami.ubuntu_24.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.ar_key_pair.key_name

  # Chiffrement du disque au repos
  root_block_device { encrypted = true }

  # Protection SSRF (IMDSv2)
  metadata_options { http_tokens = "required" }
  
  # subnet PUBLIC
  subnet_id                   = aws_subnet.ar_subnet_public.id
  vpc_security_group_ids      = [aws_security_group.ar_sg_victim.id]
  associate_public_ip_address = true # car subnet public

  tags = {
    Name = "ar-ec2-victim"
  }
}

# NIDS (Suricata)
# ==========

resource "aws_instance" "ar_ec2_nids" {
  ami           = data.aws_ami.ubuntu_24.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.ar_key_pair.key_name

  root_block_device { encrypted = true }
  metadata_options { http_tokens = "required" }
  
  # subnet PRIVE
  subnet_id                   = aws_subnet.ar_subnet_private.id
  vpc_security_group_ids      = [aws_security_group.ar_sg_nids.id]
  associate_public_ip_address = false # On cache le NIDS d'Internet

  tags = {
    Name = "ar-ec2-nids"
  }
}

# Outputs
# =========

# affichage ip publique victime
output "victim_public_ip" {
  description = "IPv4 publique de victime"
  value       = aws_instance.ar_ec2_victim.public_ip
}

# affichage ip privee NIDS
output "nids_private_ip" {
  description = "IPv4 privee de NIDS"
  value       = aws_instance.ar_ec2_nids.private_ip
}