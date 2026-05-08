import azure.functions as func
import logging
import json
from datetime import datetime
from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import ResourceManagementClient

app = func.FunctionApp()

@app.event_grid_trigger(arg_name="event")
def tag_resource_group(event: func.EventGridEvent):
    """Tag new resource groups with Creator and CreatedDate."""
    event_data = event.get_json()
    
    if 'resourceGroups/write' not in event_data.get('operationName', ''):
        return
    
    resource_uri = event_data.get('resourceUri', '')
    parts = resource_uri.split('/')
    subscription_id, rg_name = parts[2], parts[4]
    
    claims = event_data.get('claims', {})
    creator = claims.get('http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn', 'Unknown')
    created_date = datetime.utcnow().isoformat() + 'Z'
    
    credential = DefaultAzureCredential()
    client = ResourceManagementClient(credential, subscription_id)
    
    rg = client.resource_groups.get(rg_name)
    tags = rg.tags or {}
    tags['Creator'] = creator
    tags['CreatedDate'] = created_date
    
    client.resource_groups.update(rg_name, {'tags': tags})
    logging.info(f"Tagged {rg_name}: Creator={creator}, CreatedDate={created_date}")
