"""
Pydantic-AI agent wired to local LLM.
Usage: python pydantic_agent.py "your task here"
"""
import asyncio
import os
import sys
from pydantic_ai import Agent
from pydantic_ai.models.openai import OpenAIChatModel
from pydantic_ai.providers.openai import OpenAIProvider

LLM_BASE = os.getenv("LLM_BASE_URL", "http://192.168.1.186:6698/v1")
LLM_MODEL = os.getenv("LLM_MODEL", "unsloth/qwen3.5-35b-a3b")
LLM_KEY = os.getenv("LLM_API_KEY", "local")

model = OpenAIChatModel(
    LLM_MODEL,
    provider=OpenAIProvider(base_url=LLM_BASE, api_key=LLM_KEY),
)

agent = Agent(
    model,
    system_prompt=(
        "You are Atlas — the lead AI agent in the iriseye mesh. "
        "You are direct, concise, and technical."
    ),
)

async def main():
    task = " ".join(sys.argv[1:]) or "Say hello and confirm you are running on the local LLM."
    print(f"Task: {task}\n")
    result = await agent.run(task)
    print(result.output)

if __name__ == "__main__":
    asyncio.run(main())
