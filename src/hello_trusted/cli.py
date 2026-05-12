from __future__ import annotations

import sys

from . import __version__


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    name = argv[0] if argv else "world"
    print(f"hello, {name}! (hello-trusted {__version__})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
