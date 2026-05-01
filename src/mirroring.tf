# ==========
# VPC Traffic mirroring
# ==========

# Cible : ENI du NIDS
resource "aws_ec2_traffic_mirror_target" "ar_nids_target" {
  description          = "Cible pour recevoir le trafic copie (Suricata)"
  network_interface_id = aws_instance.ar_ec2_nids.primary_network_interface_id

  tags = {
    Name = "ar-mirror-target-nids"
  }
}

# Filtre (*)
resource "aws_ec2_traffic_mirror_filter" "ar_mirror_filter" {
  description = "Filtre capturant tout le trafic"
  
  tags = {
    Name = "ar-mirror-filter-all"
  }
}

# Règle de filtre : On capture TOUT le trafic en ingress
resource "aws_ec2_traffic_mirror_filter_rule" "ar_rule_in" {
  description              = "Capturer le trafic entrant"
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.ar_mirror_filter.id
  destination_cidr_block   = "0.0.0.0/0"
  source_cidr_block        = "0.0.0.0/0"
  rule_number              = 100
  rule_action              = "accept"
  traffic_direction        = "ingress"
}

# Règle du filtre : On capture TOUT le trafic en egress
resource "aws_ec2_traffic_mirror_filter_rule" "ar_rule_out" {
  description              = "Capture le trafic sortant"
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.ar_mirror_filter.id
  destination_cidr_block   = "0.0.0.0/0"
  source_cidr_block        = "0.0.0.0/0"
  rule_number              = 100
  rule_action              = "accept"
  traffic_direction        = "egress"
}

# Session (connecter victime et NIDS)
resource "aws_ec2_traffic_mirror_session" "ar_mirror_session" {
  description              = "Session de mirroring de la Victime vers le NIDS"
  network_interface_id     = aws_instance.ar_ec2_victim.primary_network_interface_id # source
  traffic_mirror_target_id = aws_ec2_traffic_mirror_target.ar_nids_target.id         # destination
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.ar_mirror_filter.id       # regles
  session_number           = 1

  tags = {
    Name = "ar-mirror-session"
  }
}