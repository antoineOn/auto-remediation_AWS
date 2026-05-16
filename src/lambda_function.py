import json
import base64
import gzip

def lambda_handler(event, context):
    # recuperation
    cw_data = event['awslogs']['data']
    compressed_payload = base64.b64decode(cw_data)
    uncompressed_payload = gzip.decompress(compressed_payload)
    log_events = json.loads(uncompressed_payload)
    
    # Traitement de chaque alerte
    for log_event in log_events['logEvents']:
        # chaque message est lui-même une chaîne JSON venant de Suricata (eve.json)
        suricata_alert = json.loads(log_event['message'])
        
        attaquant_ip = suricata_alert.get('src_ip', 'Inconnue')
        cible_ip = suricata_alert.get('dest_ip', 'Inconnue')
        signature = suricata_alert.get('alert', {}).get('signature', 'Inconnue')
        
        # TODO: bloquer l'IP dans la NACL
        print(f"Attaquant : {attaquant_ip} | Cible : {cible_ip} | Attaque : {signature}")

    return {
        'statusCode': 200,
        'body': json.dumps('Alertes traitées avec succès')
    }