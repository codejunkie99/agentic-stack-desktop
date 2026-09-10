"""Minimal example: build context, show what would be sent, then (optionally) call the model."""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, os.path.join(ROOT, ".agent", "harness"))
sys.path.insert(0, os.path.join(ROOT, ".agent", "tools"))

from context_budget import build_context


def main():
    prompt = "commit the staged changes after running tests"
    ctx, used = build_context(prompt, budget=80000)
    print(f"--- context preview ---\n{ctx[:2000]}\n...")
    print(f"\ntokens used (approx): {used}")

    if os.getenv("RUN_MODEL") == "1":
        from conductor import run
        print("\n--- model output ---")
        print(run(prompt))
    else:
        print("\n(set RUN_MODEL=1 to actually call the model)")


if __name__ == "__main__":
    main()
