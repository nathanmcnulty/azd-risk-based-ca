import { app } from '@azure/functions';
import { adminCard, fetchWithRetry, getRiskDetections, planDeliveries, pruneState, recordDeliveryFailure, userCard } from './core.js';

const graphResource='https://graph.microsoft.com';
const storageResource='https://storage.azure.com/';
function setting(name, required=true){ const value=process.env[name]?.trim(); if(required&&!value) throw new Error(`Required application setting ${name} is missing.`); return value??''; }
async function token(resource){
  const endpoint=new URL(setting('IDENTITY_ENDPOINT')); endpoint.searchParams.set('api-version','2019-08-01'); endpoint.searchParams.set('resource',resource);
  const response=await fetchWithRetry(endpoint,{headers:{'X-IDENTITY-HEADER':setting('IDENTITY_HEADER')}},{label:'managed identity token request'});
  return (await response.json()).access_token;
}
function blobUrl(container,name){ return `https://${setting('AZD_CA_STORAGE_ACCOUNT_NAME')}.blob.core.windows.net/${container}/${name}`; }
async function readState(storageToken){
  const response=await fetch(blobUrl(setting('AZD_CA_STATE_CONTAINER'),'risk-notification-state.json'),{headers:{Authorization:`Bearer ${storageToken}`,'x-ms-version':'2023-11-03'}});
  if(response.status===404)return {etag:null,value:{schemaVersion:'1.0',deliveries:{}}};
  if(!response.ok)throw new Error(`State read failed (${response.status}).`);
  return {etag:response.headers.get('etag'),value:await response.json()};
}
async function writeBlob(storageToken,container,name,value,etag){
  const headers={Authorization:`Bearer ${storageToken}`,'x-ms-version':'2023-11-03','x-ms-blob-type':'BlockBlob','Content-Type':'application/json'};
  if(etag)headers['If-Match']=etag; else headers['If-None-Match']='*';
  const response=await fetch(blobUrl(container,name),{method:'PUT',headers,body:JSON.stringify(value)});
  if(!response.ok)throw new Error(`State write failed (${response.status}).`);
}
async function send(workflowUrl,payload,destination){
  await fetchWithRetry(workflowUrl,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)},{label:`Teams ${destination} delivery`});
}

export async function pollRiskDetections(_timer,context){
  const now=new Date(); const since=new Date(now.getTime()-24*60*60*1000);
  const [graphToken,storageToken]=await Promise.all([token(graphResource),token(storageResource)]);
  const stored=await readState(storageToken); const state=stored.value; state.deliveries??={};
  const events=await getRiskDetections(graphToken,since);
  const userUrl=setting('AZD_CA_USER_TEAMS_WORKFLOW_URL',false);
  const {firstRun,deliveries}=planDeliveries(events,state,Boolean(userUrl));
  for(const delivery of deliveries){
    const record=state.deliveries[delivery.key];
    try{
      const url=delivery.destination==='admin'?setting('AZD_CA_ADMIN_TEAMS_WORKFLOW_URL'):userUrl;
      await send(url,delivery.destination==='admin'?adminCard(delivery.event):userCard(delivery.event),delivery.destination);
      record.attempts=(record.attempts??0)+1; record.lastAttemptAt=now.toISOString(); record.status='delivered'; record.deliveredAt=new Date().toISOString();
    }catch(error){
      if(recordDeliveryFailure(record,error,now)){
        await writeBlob(storageToken,setting('AZD_CA_DEAD_LETTER_CONTAINER'),`${delivery.event.eventId}-${delivery.destination}.json`,{schemaVersion:'1.0',destination:delivery.destination,failedAt:new Date().toISOString(),event:delivery.event,error:record.lastError});
      }
      context.warn(`Delivery failed for event ${delivery.event.eventId}, destination ${delivery.destination}, attempt ${record.attempts}.`);
    }
  }
  if(firstRun)state.seededAt=now.toISOString(); state.lastRunAt=now.toISOString(); pruneState(state,new Date(now.getTime()-7*24*60*60*1000));
  await writeBlob(storageToken,setting('AZD_CA_STATE_CONTAINER'),'risk-notification-state.json',state,stored.etag);
  context.log(`Risk poll processed ${events.length} events and attempted ${deliveries.length} destination deliveries${firstRun?' (initial history seeded without delivery)':''}.`);
}

app.timer('pollRiskDetections',{schedule:process.env.AZD_CA_POLLING_SCHEDULE??'0 */5 * * * *',runOnStartup:false,useMonitor:true,handler:pollRiskDetections});
