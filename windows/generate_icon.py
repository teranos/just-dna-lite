"""Generate Windows .ico file from the project logo.

Run in CI: uv run --with Pillow python windows/generate_icon.py
"""
from pathlib import Path

from PIL import Image


def generate_ico(source: Path, output: Path) -> None:
    img = Image.open(source)
    img = img.convert("RGBA")

    sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    img.save(output, format="ICO", sizes=sizes)
    print(f"Generated {output} with sizes {sizes}")


if __name__ == "__main__":
    repo_root = Path(__file__).resolve().parent.parent
    source = repo_root / "images" / "just_dna_seq.jpg"
    output = Path(__file__).resolve().parent / "icon.ico"
    generate_ico(source, output)
