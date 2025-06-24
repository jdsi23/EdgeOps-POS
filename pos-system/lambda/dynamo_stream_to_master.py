import boto3
import os

dynamodb = boto3.resource('dynamodb')
master_table_name = os.environ['MASTER_TABLE_NAME']
master_table = dynamodb.Table(master_table_name)

def lambda_handler(event, context):
    for record in event['Records']:
        if record['eventName'] in ('INSERT', 'MODIFY'):
            new_image = record['dynamodb']['NewImage']
            item = {k: list(v.values())[0] for k, v in new_image.items()}
            master_table.put_item(Item=item)
        elif record['eventName'] == 'REMOVE':
            old_image = record['dynamodb']['OldImage']
            key = {k: list(v.values())[0] for k, v in old_image.items()}
            master_table.delete_item(Key=key)
    return {'statusCode': 200}
