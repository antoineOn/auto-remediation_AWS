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