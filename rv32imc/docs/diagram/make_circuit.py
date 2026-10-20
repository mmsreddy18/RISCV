import sys
from circuit_lib import S
s=S(1500,620)
def net_in(x,y,t,L=22,sz=7):   # label stub arriving at (x,y) from left
    s.line([(x-L,y),(x,y)],arrow=True); s.text(x-L-2,y+3,t,sz,"end",it=True)
def net_out(x,y,t,L=22,sz=7):  # stub leaving (x,y) to right
    s.line([(x,y),(x+L,y)],arrow=True); s.text(x+L+2,y+3,t,sz,"start",it=True)
def frame(x,w,title):
    s.box(x,28,w,582,dash=True,fill="none",stroke="#666"); s.text(x+8,43,title,12,"start",b=True)
frame(15,295,"IF  –  Instruction Fetch"); frame(318,500,"ID  –  Decode / Register Read / Branch Resolve")
frame(826,370,"EX  –  Execute"); frame(1204,285,"WB  –  Write-back")
exec(open("part_if_id.py").read())
exec(open("part_ex_wb.py").read()) if __import__("os").path.exists("part_ex_wb.py") else None
open("rv32imc_circuit_diagram.svg","w").write(s.svg())
