"""Standalone harness entrypoint. Use when you want full ownership of the loop."""
import sys, os

# find project root — works whether run.py is at repo root or installed elsewhere
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
for _ in range(3):
    if os.path.isdir(os.path.join(ROOT, ".agent")):
        break
    ROOT = os.path.dirname(ROOT)
else:
    print("error: .agent/ not found. Run from your project root.", file=sys.stderr)
    sys.exit(1)

sys.path.insert(0, os.path.join(ROOT, ".agent", "harness"))
sys.path.insert(0, os.path.join(ROOT, ".agent", "tools"))

from conductor import run


def main():
    if len(sys.argv) < 2:
        print("usage: python run.py '<your prompt>'", file=sys.stderr)
        sys.exit(2)
    prompt = " ".join(sys.argv[1:])
    print(run(prompt))


if __name__ == "__main__":
    main()
