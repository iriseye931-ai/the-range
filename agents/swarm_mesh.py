"""
Swarm multi-agent demo wired to local LLM.
Coordinates Atlas (lead), Researcher, and Coder agents.
Usage: python swarm_mesh.py "your task here"
"""
import os
import sys
from openai import OpenAI
from Swarm import Swarm, Agent

LLM_BASE = os.getenv("LLM_BASE_URL", "http://192.168.1.186:6698/v1")
LLM_MODEL = os.getenv("LLM_MODEL", "unsloth/qwen3.5-35b-a3b")
LLM_KEY = os.getenv("LLM_API_KEY", "local")

client = Swarm(client=OpenAI(base_url=LLM_BASE, api_key=LLM_KEY))


def handoff_to_researcher():
    return researcher

def handoff_to_coder():
    return coder

def handoff_to_atlas():
    return atlas


atlas = Agent(
    name="Atlas",
    model=LLM_MODEL,
    instructions=(
        "You are Atlas — lead agent in the iriseye AI mesh. "
        "Route research tasks to the Researcher and coding tasks to the Coder. "
        "Synthesize results and deliver the final answer."
    ),
    functions=[handoff_to_researcher, handoff_to_coder],
)

researcher = Agent(
    name="Researcher",
    model=LLM_MODEL,
    instructions=(
        "You are a research agent. Analyze topics thoroughly and return structured findings. "
        "Hand back to Atlas when done."
    ),
    functions=[handoff_to_atlas],
)

coder = Agent(
    name="Coder",
    model=LLM_MODEL,
    instructions=(
        "You are a coding agent. Write clean, working code. "
        "Hand back to Atlas when done."
    ),
    functions=[handoff_to_atlas],
)


def run(task: str):
    print(f"Task: {task}\n")
    response = client.run(
        agent=atlas,
        messages=[{"role": "user", "content": task}],
    )
    print(f"[{response.agent.name}]: {response.messages[-1]['content']}")


if __name__ == "__main__":
    task = " ".join(sys.argv[1:]) or "What is the iriseye mesh and what agents are in it?"
    run(task)
