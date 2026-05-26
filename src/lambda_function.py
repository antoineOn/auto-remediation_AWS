import json
import base64
import gzip
import boto3
import os
from botocore.exceptions import ClientError

ec2 = boto3.client('ec2')
# Récupération de l'ID de la NACL
NACL_ID = os.environ.get('NACL_ID')

def get_next_rule_number(nacl_id):
    """Trouve le prochain numéro de règle disponible entre 1 et 99 pour le blocage."""
    response = ec2.describe_network_acls(NetworkAclIds=[nacl_id])
    entries = response['NetworkAcls'][0]['Entries']
    
    # On cherche les regles < 100
    used_numbers = [e['RuleNumber'] for e in entries if not e['Egress'] and e['RuleNumber'] < 100]
    
    if not used_numbers:
        return 1  # Première règle de blocage
    
    next_rule = max(used_numbers) + 1
    if next_rule >= 100:
        print("AVERTISSEMENT : Plus de place dans la NACL (1-99).")
        return None
    return next_rule

def block_ip(ip_attacker):
    try:
        rule_num = get_next_rule_number(NACL_ID)
        if not rule_num:
            return

        # Création de la règle
        ec2.create_network_acl_entry(
            NetworkAclId=NACL_ID,
            RuleNumber=rule_num,
            Protocol='-1', # Tous les protocoles
            RuleAction='deny',
            Egress=False,  # Ingres
            CidrBlock=f"{ip_attacker}/32"
        )
        print(f"SOAR : L'IP {ip_attacker} a été bloquée (Règle #{rule_num}) !")
        
    except ClientError as e:
        if 'already exists' in str(e) or 'already been reached' in str(e):
            print(f"SOAR : Info : L'IP {ip_attacker} est peut-être déjà bloquée ou le numéro est pris.")
        else:
            print(f"Erreur API AWS : {e}")

def lambda_handler(event, context):
    cw_data = event['awslogs']['data']
    compressed_payload = base64.b64decode(cw_data)
    uncompressed_payload = gzip.decompress(compressed_payload)
    
    log_events = json.loads(uncompressed_payload)
    
    for log_event in log_events['logEvents']:
        raw_message = log_event['message']
        
        try:
            suricata_alert = json.loads(raw_message)
            
            # Extraction des infos
            attaquant_ip = suricata_alert.get('src_ip', 'Inconnue')
            cible_ip = suricata_alert.get('dest_ip', 'Inconnue')
            
            # On vérifie que c'est bien une alerte
            if suricata_alert.get('event_type') == 'alert':
                signature = suricata_alert.get('alert', {}).get('signature', 'Inconnue')
                print(f"Alerte suricata levée. Attaquant : {attaquant_ip} | Cible : {cible_ip} | Attaque : {signature}")
            else:
                print(f"Flux normal depuis : {attaquant_ip}")
                
        except json.JSONDecodeError:
            # Pour l'onglet test
            print(f"Test manuel ou Log non-JSON reçu : {raw_message}")

    return {
        'statusCode': 200,
        'body': json.dumps('Traitement terminé')
    }