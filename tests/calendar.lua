-- Shared calendar date cases, isolated from services and the desktop.
package.path="shell/?.luau;"..package.path
local Calendar=require("calendar")
local count=0
local function check(value,message) assert(value,message);count=count+1 end
local function month(year,month,day,shift) return Calendar.month(shift or 0,{year=year,month=month,day=day}) end
local nov=month(2026,11,14)
check(#nov.cells==42 and nov.cells[1].d=="26" and nov.cells[1].kind==1,"Monday-first November starts with October 26")
check(nov.cells[7].d=="1" and nov.cells[7].kind==0,"Sunday November 1 is in the final weekday column")
check(nov.cells[20].d=="14" and nov.cells[20].kind==2,"Today is highlighted at its correct grid position")
check(nov.cells[42].d=="6" and nov.cells[42].kind==1,"Trailing dates continue into December")
local highlights=0;for _,cell in ipairs(nov.cells) do if cell.kind==2 then highlights=highlights+1 end end
check(highlights==1,"A calendar contains exactly one today marker")
local feb=month(2024,2,29)
check(feb.days==29 and feb.cells[32].d=="29" and feb.cells[32].kind==2,"Leap day is present and can be today")
check(month(2000,2,1).days==29 and month(2100,2,1).days==28,"Gregorian century leap-year rules")
local monday=month(2021,2,1)
check(monday.lead==0 and monday.cells[1].d=="1" and monday.rows==4,"A Monday-start four-week month has no leading dates")
check(monday.cells[29].d=="1" and monday.cells[29].kind==1,"Fixed six-week display dims the extra rows")
local next=month(2025,12,31,1)
check(next.year==2026 and next.month==1 and next.previous==31,"Month navigation crosses the year boundary")
for _,cell in ipairs(next.cells) do check(cell.kind~=2,"Another month must not highlight today's day number") end
local past=month(2026,1,14,-13)
check(past.year==2024 and past.month==12,"Negative multi-year month shifts normalize correctly")
check(month(2024,3,31).cells[42].d=="7","Date generation remains continuous across a DST-transition month")
print("Calendar: "..count.." focused checks passed")
