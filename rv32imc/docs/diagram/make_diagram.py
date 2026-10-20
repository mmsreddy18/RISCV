#!/usr/bin/env python3
"""Block diagram of the 4-stage RV32IMC core (no branch predictor, FAST_REDIRECT=0).

Writes rv32imc_block_diagram.svg and .drawio (editable in draw.io / diagrams.net) from ONE description,
so both stay identical. Usage: make_diagram.py [outdir] [--color]
"""
import sys, os
from xml.sax.saxutils import escape

W, H = 820, 452
COLOR = "--color" in sys.argv
outdir = next((a for a in sys.argv[1:] if not a.startswith("--")), ".")
tag = "_color" if COLOR else ""

# ---------------------------------------------------------------- palette
if COLOR:
    fills = dict(IF="#DAE8FC", ID="#D5E8D4", EX="#FFF2CC", WB="#F8CECC")
    strokes = dict(IF="#6C8EBF", ID="#82B366", EX="#D6B656", WB="#B85450")
    REG, REGS, MEM = "#E1D5E7", "#9673A6", "#F5F5F5"
else:
    fills = dict(IF="#F0F0F0", ID="#F0F0F0", EX="#F0F0F0", WB="#F0F0F0")
    strokes = dict(IF="#000000", ID="#000000", EX="#000000", WB="#000000")
    REG, REGS, MEM = "#BFBFBF", "#000000", "#FFFFFF"
FONT = "Helvetica, Arial, sans-serif"

nodes, edges, texts, dots = [], [], [], []

def group(x, y, w, h, label):
    nodes.append(dict(kind="group", x=x, y=y, w=w, h=h, text=label))

def block(stage, x, y, w, h, text, fs=10):
    nodes.append(dict(kind="block", stage=stage, x=x, y=y, w=w, h=h, text=text, fs=fs))

def reg(x, y, w, h, text):
    nodes.append(dict(kind="reg", x=x, y=y, w=w, h=h, text=text))

def mem(x, y, w, h, text):
    nodes.append(dict(kind="mem", x=x, y=y, w=w, h=h, text=text))

def arrow(pts, dashed=False):
    edges.append(dict(pts=pts, dashed=dashed))

def label(x, y, text, anchor="start", fs=8):
    texts.append(dict(x=x, y=y, text=text, anchor=anchor, fs=fs))

def dot(x, y):
    dots.append((x, y))

# ---------------------------------------------------------------- stage groups
GY0, GY1 = 40, 392
group(8, GY0, 180, GY1 - GY0, "IF  Instruction Fetch")
group(208, GY0, 238, GY1 - GY0, "ID  Decode / Branch")
group(464, GY0, 184, GY1 - GY0, "EX  Execute")
group(668, GY0, 144, GY1 - GY0, "WB  Write-back")

# pipeline registers
RY0, RH = 76, 316
reg(192, RY0, 12, RH, "IF/ID")
reg(448, RY0, 12, RH, "ID/EX")
reg(652, RY0, 12, RH, "EX/WB")

# external memories
mem(30, 4, 140, 28, "Instruction Memory")
mem(470, 412, 340, 30, "Data Memory")

# ---- IF
block("IF", 14, 80, 78, 48, "Fetch Address\n& Request\nControl", 9.5)
block("IF", 100, 80, 82, 48, "Prefetch\nFIFO\n(4 words)", 9.5)
block("IF", 100, 160, 82, 40, "Halfword\nAligner")
block("IF", 100, 230, 82, 40, "RVC\nExpander")
arrow([(53, 80), (53, 32)]);            label(57, 58, "addr, req")
arrow([(141, 32), (141, 80)]);          label(145, 58, "rdata")
arrow([(141, 128), (141, 160)])
arrow([(141, 200), (141, 230)])
arrow([(182, 180), (192, 180)])
arrow([(182, 250), (192, 250)])

# ---- ID
block("ID", 214, 80, 106, 48, "Instruction\nDecoder")
block("ID", 330, 80, 98, 48, "Register File\n32×32, 2R1W", 9.5)
block("ID", 214, 160, 210, 34, "Forwarding Muxes\n(EX > WB > RF)", 9.5)
block("ID", 214, 228, 100, 44, "Branch Compare\n& Target Adders", 9.5)
block("ID", 324, 228, 100, 44, "Operand\nSelect")
block("ID", 324, 300, 100, 44, "Load-Use\nHazard Detect", 9.5)
arrow([(204, 104), (214, 104)])
arrow([(320, 104), (330, 104)])
arrow([(267, 128), (267, 160)], dashed=True);   label(271, 146, "rs idx")
arrow([(379, 128), (379, 160)]);                label(383, 146, "rs1, rs2")
arrow([(264, 194), (264, 228)])
arrow([(374, 194), (374, 228)])
arrow([(424, 250), (448, 250)]);                label(436, 245, "A, B", "middle")
arrow([(448, 322), (424, 322)], dashed=True)

# ---- EX
block("EX", 470, 80, 80, 32, "Multiplier\n(mul, mulh*)", 9)
block("EX", 470, 122, 80, 32, "Divider\n(radix-2)", 9)
block("EX", 470, 164, 80, 32, "ALU", 10)
block("EX", 572, 80, 70, 116, "Result\nMux")
block("EX", 572, 204, 70, 34, "EX Stall\nControl", 9)
block("EX", 470, 250, 172, 58, "Load/Store Unit\naddr = ALU result,\nbyte enable, wdata", 9)
for y in (96, 138, 180):
    arrow([(460, y), (470, y)])
    arrow([(550, y), (572, y)])
arrow([(510, 196), (510, 250)])
arrow([(642, 138), (652, 138)])
arrow([(642, 279), (652, 279)])
arrow([(572, 221), (460, 221)], dashed=True);  label(566, 216, "ex_stall", "end")
arrow([(580, 308), (580, 412)]);               label(584, 356, "req, addr,\nwe, be, wdata")

# ---- WB
block("WB", 676, 90, 128, 40, "Write-back Mux")
block("WB", 676, 150, 56, 34, "WB Stall\nControl", 9)
block("WB", 676, 200, 128, 46, "Load Data Align\n& Sign Extend", 9.5)
arrow([(664, 110), (676, 110)])
arrow([(664, 223), (676, 223)])
arrow([(775, 200), (775, 130)])
arrow([(775, 412), (775, 246)]);               label(771, 360, "rdata, rvalid", "end")

# ---- feedback / control paths
# register write + forwarding from WB, forwarding from EX, redirect from ID
arrow([(740, 90), (740, 62), (379, 62), (379, 80)]);  label(560, 58, "write-back data (RF write, forward)", "middle")
dot(436, 62)
arrow([(436, 62), (436, 177), (424, 177)])
arrow([(607, 80), (607, 72), (444, 72), (444, 186), (424, 186)]);  label(520, 69, "EX result (forward)", "middle")
arrow([(264, 272), (264, 372), (53, 372), (53, 128)], dashed=True)
label(58, 280, "redirect_pc,", "start"); label(58, 290, "flush", "start")
arrow([(324, 322), (204, 322)], dashed=True);  label(318, 316, "stall", "end")

# legend
L = 14
arrow([(L, 418), (L + 28, 418)]);               label(L + 34, 421, "data path", fs=8.5)
arrow([(L, 432), (L + 28, 432)], dashed=True);  label(L + 34, 435, "control / feedback", fs=8.5)
nodes.append(dict(kind="reg", x=L + 130, y=410, w=10, h=14, text=""))
label(L + 146, 421, "pipeline register", fs=8.5)

# ================================================================= SVG
def svg_text(cx, cy, text, fs, weight="normal", anchor="middle", fill="#000"):
    lines = text.split("\n")
    lh = fs * 1.18
    y0 = cy - (len(lines) - 1) * lh / 2 + fs * 0.35
    out = [f'<text x="{cx}" text-anchor="{anchor}" font-size="{fs}" font-weight="{weight}" fill="{fill}">']
    for i, ln in enumerate(lines):
        out.append(f'<tspan x="{cx}" y="{y0 + i * lh:.1f}">{escape(ln)}</tspan>')
    out.append("</text>")
    return "".join(out)

def build_svg():
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" font-family="{FONT}">',
         '<defs><marker id="ah" markerWidth="7" markerHeight="7" refX="6" refY="3.5" orient="auto" markerUnits="userSpaceOnUse">'
         '<path d="M0,0 L7,3.5 L0,7 z" fill="#000"/></marker></defs>',
         f'<rect width="{W}" height="{H}" fill="#fff"/>']
    stage_of = {}
    for n in nodes:
        if n["kind"] == "group":
            s.append(f'<rect x="{n["x"]}" y="{n["y"]}" width="{n["w"]}" height="{n["h"]}" rx="6" fill="none" stroke="#777" stroke-width="1" stroke-dasharray="5,3"/>')
            s.append(svg_text(n["x"] + 6, n["y"] + n["h"] - 9, n["text"], 10, "bold", "start"))
    for n in nodes:
        if n["kind"] == "block":
            s.append(f'<rect x="{n["x"]}" y="{n["y"]}" width="{n["w"]}" height="{n["h"]}" rx="4" fill="{fills[n["stage"]]}" stroke="{strokes[n["stage"]]}" stroke-width="1.2"/>')
            s.append(svg_text(n["x"] + n["w"] / 2, n["y"] + n["h"] / 2, n["text"], n["fs"]))
        elif n["kind"] == "reg":
            s.append(f'<rect x="{n["x"]}" y="{n["y"]}" width="{n["w"]}" height="{n["h"]}" fill="{REG}" stroke="{REGS}" stroke-width="1.2"/>')
            if n["text"]:
                cx, cy = n["x"] + n["w"] / 2, n["y"] + n["h"] / 2
                s.append(f'<g transform="rotate(-90 {cx} {cy})">' + svg_text(cx, cy, n["text"], 9, "bold") + "</g>")
        elif n["kind"] == "mem":
            s.append(f'<rect x="{n["x"]}" y="{n["y"]}" width="{n["w"]}" height="{n["h"]}" rx="2" fill="{MEM}" stroke="#000" stroke-width="2"/>')
            s.append(svg_text(n["x"] + n["w"] / 2, n["y"] + n["h"] / 2, n["text"], 10.5, "bold"))
    for e in edges:
        pts = " ".join(f"{x},{y}" for x, y in e["pts"])
        d = ' stroke-dasharray="4,3"' if e["dashed"] else ""
        s.append(f'<polyline points="{pts}" fill="none" stroke="#000" stroke-width="1.1"{d} marker-end="url(#ah)"/>')
    for x, y in dots:
        s.append(f'<circle cx="{x}" cy="{y}" r="2.4" fill="#000"/>')
    for t in texts:
        s.append(svg_text(t["x"], t["y"] - t["fs"] * 0.35, t["text"], t["fs"], "normal", t["anchor"], "#222"))
    s.append("</svg>")
    return "\n".join(s)

# ================================================================= draw.io
def build_drawio():
    cells = ['<mxCell id="0"/>', '<mxCell id="1" parent="0"/>']
    nid = [2]
    def nxt():
        nid[0] += 1
        return f"c{nid[0]}"
    def html(t):
        return escape(t, {'"': "&quot;"}).replace("\n", "&lt;br&gt;")
    def vertex(x, y, w, h, value, style):
        cells.append(f'<mxCell id="{nxt()}" value="{value}" style="{escape(style)}" vertex="1" parent="1">'
                     f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
    base = "html=1;whiteSpace=wrap;fontFamily=Helvetica;"
    for n in nodes:
        if n["kind"] == "group":
            vertex(n["x"], n["y"], n["w"], n["h"], html(n["text"]),
                   base + "rounded=1;arcSize=3;dashed=1;fillColor=none;strokeColor=#777777;verticalAlign=bottom;align=left;spacingLeft=4;fontStyle=1;fontSize=10;")
    for n in nodes:
        if n["kind"] == "block":
            vertex(n["x"], n["y"], n["w"], n["h"], html(n["text"]),
                   base + f"rounded=1;arcSize=10;fillColor={fills[n['stage']]};strokeColor={strokes[n['stage']]};strokeWidth=1.2;fontSize={int(round(n['fs']))};")
        elif n["kind"] == "reg":
            vertex(n["x"], n["y"], n["w"], n["h"], html(n["text"]),
                   base + f"fillColor={REG};strokeColor={REGS};strokeWidth=1.2;fontStyle=1;fontSize=9;horizontal=0;")
        elif n["kind"] == "mem":
            vertex(n["x"], n["y"], n["w"], n["h"], html(n["text"]),
                   base + f"fillColor={MEM};strokeColor=#000000;strokeWidth=2;fontStyle=1;fontSize=10;")
    for e in edges:
        p = e["pts"]
        style = "html=1;rounded=0;endArrow=block;endFill=1;strokeColor=#000000;strokeWidth=1.1;" + ("dashed=1;" if e["dashed"] else "")
        mid = "".join(f'<mxPoint x="{x}" y="{y}"/>' for x, y in p[1:-1])
        arr = f'<Array as="points">{mid}</Array>' if mid else ""
        cells.append(f'<mxCell id="{nxt()}" value="" style="{style}" edge="1" parent="1"><mxGeometry relative="1" as="geometry">'
                     f'<mxPoint x="{p[0][0]}" y="{p[0][1]}" as="sourcePoint"/><mxPoint x="{p[-1][0]}" y="{p[-1][1]}" as="targetPoint"/>{arr}</mxGeometry></mxCell>')
    for x, y in dots:
        vertex(x - 2.5, y - 2.5, 5, 5, "", "ellipse;fillColor=#000000;strokeColor=#000000;")
    for t in texts:
        w = 150
        ax = {"start": (t["x"], "left"), "middle": (t["x"] - w / 2, "center"), "end": (t["x"] - w, "right")}[t["anchor"]]
        vertex(ax[0], t["y"] - t["fs"] - 3, w, t["fs"] + 6, html(t["text"]),
               f"text;html=1;strokeColor=none;fillColor=none;fontFamily=Helvetica;fontSize={int(round(t['fs']))};align={ax[1]};verticalAlign=middle;spacing=0;fontColor=#222222;")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<mxfile host="app.diagrams.net"><diagram name="RV32IMC 4-stage core" id="rv32imc">'
            f'<mxGraphModel dx="{W}" dy="{H}" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" '
            f'pageScale="1" pageWidth="{W}" pageHeight="{H}" math="0" shadow="0"><root>' + "".join(cells) + "</root></mxGraphModel></diagram></mxfile>")

os.makedirs(outdir, exist_ok=True)
open(os.path.join(outdir, f"rv32imc_block_diagram{tag}.svg"), "w").write(build_svg())
open(os.path.join(outdir, f"rv32imc_block_diagram{tag}.drawio"), "w").write(build_drawio())
print("written", outdir, tag)
