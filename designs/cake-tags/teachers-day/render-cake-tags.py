#!/usr/bin/env python3
"""Typeset two reusable cake tags on one A6 landscape sheet (requires Pillow)."""

import argparse
import json
from pathlib import Path
import unicodedata

from PIL import Image, ImageDraw, ImageFont, PngImagePlugin

ROOT = Path(__file__).resolve().parent
DPI = 300
PAGE_SIZE = (1748, 1240)
TAG_SIZE = (1630, 537)
TAG_POSITIONS = ((59, 59), (59, 644))
SCALE = 2
INK = '#60251d'
HIGHLIGHT = '#cf224e'


def load_tags(path):
    tags = json.loads(path.read_text(encoding='utf-8'))['tags']
    if len(tags) != 2:
        raise ValueError('The A6 template requires exactly two tags.')
    for tag in tags:
        if len(tag['lines']) not in (2, 3):
            raise ValueError('Each tag must have two or three lines.')
        tag['lines'] = [unicodedata.normalize('NFC', line) for line in tag['lines']]
        if not all(line.strip() and '\n' not in line for line in tag['lines']):
            raise ValueError('Message lines must be nonempty single lines.')
        tag['highlight'] = unicodedata.normalize('NFC', tag.get('highlight', ''))
    return tags


def draw_line(draw, text, center, maximum_size, highlight):
    font_path = ROOT / 'fonts' / 'DancingScript-Bold.ttf'
    for size in range(maximum_size, 59, -1):
        font = ImageFont.truetype(str(font_path), size * SCALE)
        bounds = font.getbbox(text, anchor='ls')
        if bounds[2] - bounds[0] <= 710 * SCALE:
            break
    else:
        raise ValueError(f'Text is too long for the tag: {text}')

    missing = bytes(font.getmask('\U0010ffff'))
    if any(bytes(font.getmask(char)) == missing for char in set(text) - {' '}):
        raise ValueError(f'The bundled font does not support a character in: {text}')
    x = center[0] * SCALE - (bounds[0] + bounds[2]) / 2
    baseline = center[1] * SCALE - (bounds[1] + bounds[3]) / 2
    draw.text((x, baseline), text, font=font, anchor='ls', fill=INK)
    if highlight and highlight in text:
        prefix = text.split(highlight, 1)[0]
        draw.text(
            (x + font.getlength(prefix), baseline),
            highlight,
            font=font,
            anchor='ls',
            fill=HIGHLIGHT,
        )


def render(tags, output_dir, output_name, template_path):
    template = Image.open(template_path).convert('RGB')
    if template.size != (1536, 1024):
        raise ValueError('The blank template must be 1536 x 1024 pixels.')
    page = Image.new('RGB', PAGE_SIZE, 'white')
    for index, tag in enumerate(tags):
        artwork = template.crop((0, index * 512, 1536, (index + 1) * 512))
        artwork = artwork.resize((1536 * SCALE, 512 * SCALE), Image.Resampling.LANCZOS)
        draw = ImageDraw.Draw(artwork)
        if len(tag['lines']) == 2:
            centers, sizes = ((830, 205), (830, 347)), (108, 118)
        else:
            centers, sizes = ((815, 135), (815, 247), (815, 359)), (128, 110, 108)
        for line, center, size in zip(tag['lines'], centers, sizes):
            draw_line(draw, line, center, size, tag['highlight'])
        artwork = artwork.resize(TAG_SIZE, Image.Resampling.LANCZOS)
        page.paste(artwork, TAG_POSITIONS[index])

    metadata = PngImagePlugin.PngInfo()
    metadata.add_itxt('Title', 'Cake decoration tags / A6 landscape / 20-11')
    metadata.add_itxt('Description', '\n'.join(' '.join(tag['lines']) for tag in tags))
    metadata.add_itxt(
        'Print instructions',
        'A6 landscape, 148 x 105 mm, 300 DPI. Print at 100% / Actual size. '
        'Cut around each pink scalloped outline.',
    )
    output_dir.mkdir(parents=True, exist_ok=True)
    png = output_dir / f'{output_name}.png'
    pdf = output_dir / f'{output_name}.pdf'
    page.save(png, dpi=(DPI, DPI), pnginfo=metadata, optimize=True)
    page.save(pdf, 'PDF', resolution=DPI, quality=100, subsampling=0, title='Cake tags - A6 landscape')
    return png, pdf


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--messages', type=Path, default=ROOT / 'messages.json')
    parser.add_argument('--template', type=Path, default=ROOT / 'templates' / 'teacher-chibi-blank.png')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'exports')
    parser.add_argument('--output-name', default='cake-tags-teacher-chibi-20-11-a6')
    args = parser.parse_args()
    if not args.output_name or Path(args.output_name).name != args.output_name:
        parser.error('--output-name must be a filename stem, not a path.')
    tags = load_tags(args.messages)
    for path in render(tags, args.output_dir, args.output_name, args.template):
        print(path)


if __name__ == '__main__':
    main()
