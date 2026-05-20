# Variables

variable "aws_region" {
  description = "La région AWS de déploiement"
  type        = string
  default     = "eu-west-3"
}

# VPC Principal
# trivy:ignore:AVD-AWS-0178 - Flow logs non requis pour l'architecture NIDS actuelle
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
# trivy:ignore:AVD-AWS-0164 - Risque accepté : Le Honeypot doit être exposé sur Internet
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

# 
# NAT GATEWAY & ROUTAGE PRIVÉ
# ==========

# Elastic IP pour le NAT Gateway
resource "aws_eip" "ar_eip_nat" {
  domain = "vpc"
  
  tags = {
    Name = "ar-eip-nat"
  }
}

# NAT Gateway (subnet public)
resource "aws_nat_gateway" "ar_nat_gw" {
  allocation_id = aws_eip.ar_eip_nat.id
  subnet_id     = aws_subnet.ar_subnet_public.id

  tags = {
    Name = "ar-nat-gateway"
  }

  # Internet Gateway doit d'abord exister
  depends_on = [aws_internet_gateway.ar_igw_main]
}

# Table de routage pour le subnet prive
resource "aws_route_table" "ar_rt_private" {
  vpc_id = aws_vpc.ar_vpc_main.id

  # On envoie tout vers le NAT Gateway
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ar_nat_gw.id
  }

  tags = {
    Name = "ar-rt-private"
  }
}

# On lie cette table au subnet PRIVE
resource "aws_route_table_association" "ar_rt_assoc_private" {
  subnet_id      = aws_subnet.ar_subnet_private.id
  route_table_id = aws_route_table.ar_rt_private.id
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

  # Protection SSRF
  metadata_options { 
    http_tokens                 = "required" 
    http_put_response_hop_limit = 2
  }

  # attachement du role a l'instance
  iam_instance_profile = aws_iam_instance_profile.ar_nids_profile.name

  # subnet PRIVE
  subnet_id                   = aws_subnet.ar_subnet_private.id
  vpc_security_group_ids      = [aws_security_group.ar_sg_nids.id]
  associate_public_ip_address = false # On cache le NIDS d'Internet

  # Provisioning
  user_data = <<-EOF
              #!/bin/bash

              # log
              touch /home/ubuntu/startup_log.txt
              chown ubuntu:ubuntu /home/ubuntu/startup_log.txt
              
              echo "Welcome to the NIDS (Suricata)" > /home/ubuntu/hello.txt
              chown ubuntu:ubuntu /home/ubuntu/hello.txt

              # desactiver pop-ups interactifs
              export DEBIAN_FRONTEND=noninteractive >> /home/ubuntu/startup_log.txt
              sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf || true >> /home/ubuntu/startup_log.txt
              while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done

              echo "Pop-ups desactives" >> /home/ubuntu/hello.txt

              # Creation de 2 Go en SWAP
              fallocate -l 2G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab
              echo "Swap de 2 Go active" >> /home/ubuntu/hello.txt

              # Attendre qu'Internet soit vraiment disponible
              until ping -c1 8.8.8.8 &>/dev/null; do
                sleep 5
              done

              echo "Connexion OK" >> /home/ubuntu/hello.txt

              apt-get update -y >> /home/ubuntu/startup_log.txt
              apt-get install -yq \
                -o Dpkg::Options::="--force-confdef" \
                -o Dpkg::Options::="--force-confold" \
                suricata jq >> /home/ubuntu/startup_log.txt
              
              echo "Suricata installé" >> /home/ubuntu/hello.txt

              # chercher l'interface reseau de la machine
              MAIN_IFACE=$(ls /sys/class/net | grep -v lo | head -n 1)
              
              # ignorer les faux checksums du Traffic Mirroring AWS
              sed -i 's/checksum-validation: yes/checksum-validation: no/g' /etc/suricata/suricata.yaml
              sed -i 's/checksum-checks: yes/checksum-checks: no/g' /etc/suricata/suricata.yaml
              
              # Forcer a ecouter sur la bonne interface reseau
              mkdir -p /etc/systemd/system/suricata.service.d
              echo "[Service]" > /etc/systemd/system/suricata.service.d/override.conf
              echo "ExecStart=" >> /etc/systemd/system/suricata.service.d/override.conf
              echo "ExecStart=/usr/bin/suricata -D --af-packet=$${MAIN_IFACE} -c /etc/suricata/suricata.yaml --pidfile /run/suricata.pid" >> /etc/systemd/system/suricata.service.d/override.conf
              
              # On indique à Linux de prendre en compte cette nouvelle configuration
              systemctl daemon-reload
              
              # Activation du service au demarrage
              suricata-update >> /home/ubuntu/startup_log.txt
              systemctl enable suricata >> /home/ubuntu/startup_log.txt
              systemctl restart suricata >> /home/ubuntu/startup_log.txt

              echo "Suricata activé" >> /home/ubuntu/hello.txt 
              
              # CW

              # Telechargement et installation de CW agent
              wget https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
              dpkg -i -E ./amazon-cloudwatch-agent.deb

              # fichier configuration CW
              cat << 'CWEOF' > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
              {
                "agent": {
                  "run_as_user": "root"
                },
                "logs": {
                  "logs_collected": {
                    "files": {
                      "collect_list": [
                        {
                          "file_path": "/var/log/suricata/eve.json",
                          "log_group_name": "/secops/suricata/eve",
                          "log_stream_name": "{instance_id}",
                          "timezone": "UTC"
                        }
                      ]
                    }
                  }
                }
              }
              CWEOF

              # demarrage du CW agent
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
              
              echo "Agent CloudWatch active" >> /home/ubuntu/hello.txt
              EOF

  user_data_replace_on_change = true

  tags = {
    Name = "ar-ec2-nids"
  }
}