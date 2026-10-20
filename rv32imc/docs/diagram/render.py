import sys, asyncio
from playwright.sync_api import sync_playwright
svg, png, pdf = sys.argv[1:4]
W=int(sys.argv[4]) if len(sys.argv)>4 else 820; H=int(sys.argv[5]) if len(sys.argv)>5 else 452
html = f"<html><body style='margin:0'>{open(svg).read()}</body></html>"
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={"width":W,"height":H}, device_scale_factor=3.5)
    pg.set_content(html); pg.screenshot(path=png, clip={"x":0,"y":0,"width":W,"height":H})
    pg.pdf(path=pdf, width=f"{W}px", height=f"{H}px", print_background=True, page_ranges="1")
    b.close()
