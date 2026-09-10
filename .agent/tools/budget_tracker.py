"""Quick token accounting for the context budget. Naive but useful."""
import os, sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "harness"))
from context_budget import build_context

CHARS_PER_TOKEN = 4


def estimate_context(user_input: str, budget: int = 88000):
    ctx, used = build_context(user_input, budget=budget)
    return {
        "tokens_used": used,
        "chars": len(ctx),
        "budget": budget,
        "headroom": max(0, budget - used),
    }


if __name__ == "__main__":
    prompt = " ".join(sys.argv[1:]) or "status check"
    for k, v in estimate_context(prompt).items():
        print(f"{k}: {v}")
