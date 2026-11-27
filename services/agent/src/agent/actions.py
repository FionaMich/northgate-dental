"""Nora's "do" tools, published by n8n's MCP Server Trigger (workflow W14; blueprint sections 21 and 24).

Nora's own MCP server answers "know" questions; n8n owns the actions that reach outside the conversation (an email
with a payment link, a reschedule link, a request in the receptionist inbox), so the clinic can change how those are
delivered without a new release of Nora. Each tool runs as the signed-in patient: this module passes the patient's
session token from the verified session, never anything the model wrote, and the Supabase function decides."""

import asyncio
import json
import os
from concurrent.futures import ThreadPoolExecutor

import httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client


class Unavailable(Exception):
    """n8n could not be reached or answered with something that is not a tool result."""


class Refused(Exception):
    """The database said no; the message is written for patients."""


def configured() -> bool:
    return bool(os.environ.get("N8N_MCP_URL") and os.environ.get("N8N_MCP_TOKEN"))


async def _call(tool: str, args: dict) -> str:
    headers = {"Authorization": f"Bearer {os.environ['N8N_MCP_TOKEN']}"}
    async with httpx.AsyncClient(headers=headers, timeout=15) as http:
        async with streamable_http_client(os.environ["N8N_MCP_URL"], http_client=http) as (read, write, *_):
            async with ClientSession(read, write) as session:
                await session.initialize()
                out = await session.call_tool(tool, args)
    if out.is_error:
        raise Unavailable(f"{tool} failed in n8n")
    return out.content[0].text


def parse(text: str):
    """The HTTP tool's full response ({statusCode, body, ...}, sometimes wrapped in a one-item list) as the function's
    answer, or Refused with the database's own message."""
    data = json.loads(text)
    data = data[0] if isinstance(data, list) else data
    if not isinstance(data, dict) or "statusCode" not in data:
        raise Unavailable("not a tool response")
    if data["statusCode"] >= 300:
        body = data.get("body")
        raise Refused(body.get("message", "refused") if isinstance(body, dict) else "refused")
    return data.get("body")


def call(tool: str, session_token: str, **args):
    """One n8n tool as the patient. Runs in its own thread, so it works whether or not an event loop is running."""
    try:
        with ThreadPoolExecutor(1) as pool:
            text = pool.submit(asyncio.run, _call(tool, {"session_token": session_token, **args})).result(timeout=30)
    except (Refused, Unavailable):
        raise
    except Exception as error:   # connection refused, timeout, protocol error: the caller falls back
        raise Unavailable(type(error).__name__) from None
    return parse(text)
