"""七个等距节点的Hermite曲线编辑器，仅编辑配置。"""
from dataclasses import dataclass
import tkinter as tk
from tkinter import ttk
from lfo_v2_protocol import PRESETS, value_q6
MAX_CONTROL_POINTS=7
TABLE_SIZE=384
@dataclass
class LfoPoint:
    time: float
    level: int
class LfoCurve:
    def __init__(self):
        self.points=[LfoPoint(n/6,v) for n,v in enumerate(PRESETS[0])]
        self.stepped=False
        self.link_ends=False
    @property
    def values(self):
        return [max(0,min(127,round(p.level))) for p in self.points]
    def preset(self,index):
        self.points=[LfoPoint(n/6,v) for n,v in enumerate(PRESETS[index])]
        self.stepped=index==2
    def move_point(self,index,_time,level):
        self.points[index].time=index/6
        self.points[index].level=max(0,min(127,round(level)))
        if self.link_ends and index in (0,6): self.points[6-index].level=self.points[index].level
    def evaluate(self,phase):
        return value_q6(self.values,max(0,min(384,int(phase*384))),self.stepped)/64
class LfoCurveEditor(ttk.LabelFrame):
    WIDTH,HEIGHT,MARGIN=650,190,14
    def __init__(self,parent,curve,on_change=None):
        super().__init__(parent,text="LFO V2：7个等距节点，自动Hermite插值",padding=6)
        self.curve,self.on_change=curve,on_change
        self.selected_index=0
        self.stepped=tk.BooleanVar(value=curve.stepped)
        self.link_ends=tk.BooleanVar(value=curve.link_ends)
        self.description=tk.StringVar()
        self.canvas=tk.Canvas(self,width=self.WIDTH,height=self.HEIGHT,background="#15191d",highlightthickness=0)
        self.canvas.grid(row=0,column=0,columnspan=5)
        self.canvas.bind("<Button-1>",self._select)
        self.canvas.bind("<B1-Motion>",self._drag)
        for n,name in enumerate(("三角","上升","方波")):
            ttk.Button(self,text=name,command=lambda n=n:self._preset(n)).grid(row=1,column=n,padx=3,pady=5)
        ttk.Checkbutton(self,text="阶梯",variable=self.stepped,command=self._step).grid(row=1,column=3)
        ttk.Checkbutton(self,text="联动首尾",variable=self.link_ends,command=self._link).grid(row=1,column=4)
        ttk.Label(self,textvariable=self.description).grid(row=2,column=0,columnspan=5,sticky="w")
        self.redraw()
    def _xy(self,time,level):
        return (self.MARGIN+time*(self.WIDTH-2*self.MARGIN),self.HEIGHT-self.MARGIN-level/127*(self.HEIGHT-2*self.MARGIN))
    def _select(self,event):
        self.selected_index=max(0,min(6,round((event.x-self.MARGIN)/(self.WIDTH-2*self.MARGIN)*6)))
        self._drag(event)
    def _drag(self,event):
        level=(self.HEIGHT-self.MARGIN-event.y)/(self.HEIGHT-2*self.MARGIN)*127
        self.curve.move_point(self.selected_index,self.selected_index/6,level)
        self._changed()
    def _preset(self,index):
        self.curve.preset(index)
        self.stepped.set(self.curve.stepped)
        self._changed()
    def _step(self):
        self.curve.stepped=bool(self.stepped.get())
        self._changed()
    def _link(self):
        self.curve.link_ends=bool(self.link_ends.get())
        if self.curve.link_ends: self.curve.points[6].level=self.curve.points[0].level
        self._changed()
    def _changed(self):
        self.redraw()
        if self.on_change is not None: self.on_change()
    def redraw(self):
        self.canvas.delete("all")
        for n in range(7):
            x,_=self._xy(n/6,0)
            self.canvas.create_line(x,self.MARGIN,x,self.HEIGHT-self.MARGIN,fill="#293138")
        coords=[]
        for n in range(385): coords.extend(self._xy(n/384,self.curve.evaluate(n/384)))
        self.canvas.create_line(*coords,fill="#67d8ff",width=2)
        for n,p in enumerate(self.curve.points):
            x,y=self._xy(p.time,p.level)
            self.canvas.create_oval(x-5,y-5,x+5,y+5,fill="#ffcf55" if n==self.selected_index else "white")
        self.description.set(f"节点{self.selected_index+1}  值={self.curve.points[self.selected_index].level}；横坐标固定，首尾不同会产生周期回跳")
