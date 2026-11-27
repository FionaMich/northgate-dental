import { workflow, trigger, tool, newCredential, expr } from '@n8n/workflow-sdk';

// W14: Nora's "do" tools, published over MCP (blueprint sections 21 and 24). Nora's own MCP server answers "know"
// questions; these three act. Each calls a Supabase function on the staging project with the patient's own session
// token, so row level security and the function's checks decide who may do what: n8n holds no business rule and no
// patient data. Nora's code fills session_token from the verified session; the model never sees or sets it.

const sendPaymentLink = tool({
  type: 'n8n-nodes-base.httpRequestTool', version: 4.5,
  config: {
    name: 'send_payment_link',
    parameters: {
      toolDescription: 'Email the patient a secure payment link for one of their visits and return a single-use pay token for the chat. The amount comes from the price list.',
      method: 'POST',
      url: 'https://dxkfsslymzqbgtoijuut.supabase.co/rest/v1/rpc/send_my_payment_link',
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      sendHeaders: true,
      headerParameters: { parameters: [
        { name: 'Authorization', value: expr("{{ 'Bearer ' + $fromAI('session_token', 'Set by the caller from the verified session', 'string') }}") },
      ] },
      sendBody: true,
      contentType: 'json',
      specifyBody: 'json',
      jsonBody: expr("{{ JSON.stringify({ appointment: $fromAI('visit_ref', 'The id of one of the patient visits', 'string') }) }}"),
      options: { timeout: 10000, response: { response: { neverError: true, fullResponse: true } } },
    },
    credentials: { httpHeaderAuth: newCredential('Northgate Supabase publishable key') },
    position: [0, 240],
  },
});

const rescheduleLink = tool({
  type: 'n8n-nodes-base.httpRequestTool', version: 4.5,
  config: {
    name: 'reschedule_link',
    parameters: {
      toolDescription: 'Email the patient a single-use link to choose a new time for one of their booked visits. The visit stays booked until they choose.',
      method: 'POST',
      url: 'https://dxkfsslymzqbgtoijuut.supabase.co/rest/v1/rpc/send_my_reschedule_link',
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      sendHeaders: true,
      headerParameters: { parameters: [
        { name: 'Authorization', value: expr("{{ 'Bearer ' + $fromAI('session_token', 'Set by the caller from the verified session', 'string') }}") },
      ] },
      sendBody: true,
      contentType: 'json',
      specifyBody: 'json',
      jsonBody: expr("{{ JSON.stringify({ appointment: $fromAI('visit_ref', 'The id of one of the patient visits', 'string') }) }}"),
      options: { timeout: 10000, response: { response: { neverError: true, fullResponse: true } } },
    },
    credentials: { httpHeaderAuth: newCredential('Northgate Supabase publishable key') },
    position: [240, 240],
  },
});

const askReceptionist = tool({
  type: 'n8n-nodes-base.httpRequestTool', version: 4.5,
  config: {
    name: 'ask_receptionist',
    parameters: {
      toolDescription: 'Put a request in the receptionist inbox for the clinic team to reply to the patient.',
      method: 'POST',
      url: 'https://dxkfsslymzqbgtoijuut.supabase.co/rest/v1/rpc/request_handover',
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      sendHeaders: true,
      headerParameters: { parameters: [
        { name: 'Authorization', value: expr("{{ 'Bearer ' + $fromAI('session_token', 'Set by the caller from the verified session', 'string') }}") },
      ] },
      sendBody: true,
      contentType: 'json',
      specifyBody: 'json',
      jsonBody: expr("{{ JSON.stringify({ category: $fromAI('category', 'booking, billing, clinical_question, shop or other', 'string'), language: $fromAI('language', 'The patient language code', 'string'), summary: $fromAI('summary', 'What the patient needs, in English, without diagnosing', 'string').slice(0, 600) }) }}"),
      options: { timeout: 10000, response: { response: { neverError: true, fullResponse: true } } },
    },
    credentials: { httpHeaderAuth: newCredential('Northgate Supabase publishable key') },
    position: [480, 240],
  },
});

const server = trigger({
  type: '@n8n/n8n-nodes-langchain.mcpTrigger', version: 2.1,
  config: {
    name: 'Nora action tools',
    parameters: {
      path: 'nora-tools',
      authentication: 'bearerAuth',
      instructions: 'Action tools for the Northgate Dental assistant. Every call acts as the signed-in patient whose session token is passed; nothing here works without one.',
    },
    credentials: { httpBearerAuth: newCredential('Nora MCP token') },
    subnodes: { tools: [sendPaymentLink, rescheduleLink, askReceptionist] },
    position: [240, 0],
  },
});

export default workflow('northgate-w14', 'W14 Nora action tools (MCP)').add(server);
