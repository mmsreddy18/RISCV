# Minimal schematic symbol library -> SVG string
class S:
    def __init__(s,w,h): s.w,s.h,s.o=w,h,[]
    def a(s,x): s.o.append(x)
    def line(s,pts,bus=False,dash=False,col="#000",arrow=True):
        sw=2.2 if bus else 1
        d=' stroke-dasharray="4 3"' if dash else ''
        s.a(f'<polyline points="{" ".join(f"{x},{y}" for x,y in pts)}" fill="none" stroke="{col}" stroke-width="{sw}"{d}/>')
        if arrow:
            (x0,y0),(x1,y1)=pts[-2],pts[-1]
            import math; t=math.atan2(y1-y0,x1-x0); L=6
            p=[(x1,y1),(x1-L*math.cos(t-.4),y1-L*math.sin(t-.4)),(x1-L*math.cos(t+.4),y1-L*math.sin(t+.4))]
            s.a(f'<polygon points="{" ".join(f"{x:.1f},{y:.1f}" for x,y in p)}" fill="{col}"/>')
    def dot(s,x,y): s.a(f'<circle cx="{x}" cy="{y}" r="2.6" fill="#000"/>')
    def text(s,x,y,t,sz=9,anchor="middle",b=False,it=False,col="#000"):
        s.a(f'<text x="{x}" y="{y}" font-size="{sz}" text-anchor="{anchor}" font-family="Times New Roman,serif"'
            f'{" font-weight=\"bold\"" if b else ""}{" font-style=\"italic\"" if it else ""} fill="{col}">{t}</text>')
    def box(s,x,y,w,h,label="",sub="",fill="#fff",dash=False,sz=10,stroke="#000"):
        d=' stroke-dasharray="6 4"' if dash else ''
        s.a(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" stroke="{stroke}" stroke-width="1.2"{d}/>')
        if label: s.text(x+w/2,y+h/2+(-2 if sub else 4),label,sz,b=True)
        if sub: s.text(x+w/2,y+h/2+10,sub,sz-2,it=True)
    def reg(s,x,y,w,h,label):   # register with clock wedge
        s.a(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#fff" stroke="#000" stroke-width="1.4"/>')
        s.a(f'<polyline points="{x},{y+h-12} {x+8},{y+h-6} {x},{y+h}" fill="none" stroke="#000"/>')
        s.text(x+w/2,y+h/2+3,label,9,b=True)
    def mux(s,x,y,w,h,n,label="",sel=""):  # vertical trapezoid, inputs left, output right
        s.a(f'<polygon points="{x},{y} {x+w},{y+h*.18} {x+w},{y+h*.82} {x},{y+h}" fill="#fff" stroke="#000" stroke-width="1.2"/>')
        if label: s.text(x+w/2,y+h/2+3,label,8,b=True)
        ys=[y+h*(i+1)/(n+1) for i in range(n)]
        if sel: s.text(x+w/2,y+h+10,sel,7,it=True)
        return ys
    def alu(s,x,y,w,h,label):   # V-notch trapezoid, inputs left, out right
        s.a(f'<polygon points="{x},{y} {x+w},{y+h*.25} {x+w},{y+h*.75} {x},{y+h} {x},{y+h*.58} {x+w*.22},{y+h*.5} {x},{y+h*.42}" fill="#fff" stroke="#000" stroke-width="1.2"/>')
        s.text(x+w*.62,y+h/2+3,label,9,b=True)
    def adder(s,x,y,w,h,label="+"):
        s.a(f'<polygon points="{x},{y} {x+w},{y+h*.25} {x+w},{y+h*.75} {x},{y+h} {x},{y+h*.58} {x+w*.22},{y+h*.5} {x},{y+h*.42}" fill="#fff" stroke="#000" stroke-width="1.2"/>')
        s.text(x+w*.62,y+h/2+4,label,12,b=True)
    def cmp(s,x,y,w,h,label):
        s.a(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{h/2}" fill="#fff" stroke="#000" stroke-width="1.2"/>')
        s.text(x+w/2,y+h/2+3,label,8,b=True)
    def gate(s,x,y,kind,w=22,h=16,bub=False):  # AND/OR, inputs left output right
        if kind=="and":
            s.a(f'<path d="M{x},{y} H{x+w*.5} A{w*.5},{h/2} 0 0 1 {x+w*.5},{y+h} H{x} Z" fill="#fff" stroke="#000"/>')
        else:
            s.a(f'<path d="M{x},{y} Q{x+w*.6},{y} {x+w},{y+h/2} Q{x+w*.6},{y+h} {x},{y+h} Q{x+w*.25},{y+h/2} {x},{y} Z" fill="#fff" stroke="#000"/>')
        if bub: s.a(f'<circle cx="{x+w+3}" cy="{y+h/2}" r="3" fill="#fff" stroke="#000"/>')
    def inv(s,x,y):
        s.a(f'<polygon points="{x},{y-6} {x+11},{y} {x},{y+6}" fill="#fff" stroke="#000"/><circle cx="{x+14}" cy="{y}" r="3" fill="#fff" stroke="#000"/>')
    def svg(s):
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{s.w}" height="{s.h}" viewBox="0 0 {s.w} {s.h}">'
                f'<rect width="100%" height="100%" fill="#fff"/>'+"".join(s.o)+'</svg>')
