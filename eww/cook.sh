#!/usr/bin/env bash
# Cook mode (ws3) for the deck. Two states, driven imperatively (eww update), album-grid style:
#   * NO meal planned for today  -> PICKER: a paginated grid of recipe tiles (photo or placeholder);
#     tapping one creates today's Tandoor meal-plan entry (remembered) and drops into Cook view.
#   * meal planned (or just picked) -> COOK view: step-by-step, tick ingredients, prev/next.
# So the deck remembers your pick across reloads, and shows a chooser when you haven't decided.
#
# PAGINATED, not scrolled. Recipe photos come from Tandoor's recipe.image (backfilled from source
# og:image); resolved/cached locally per recipe, graceful placeholder when absent.
#
# Config: ~/.config/eww/tandoor-url + tandoor-token (read-write). HTTP only. Subcommands:
#   load|refresh | pick <id> <name> | change | pickpage <prev|next> | step <prev|next> | check <i>
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
EWW="$HOME/.local/bin/eww"
CFG="$HOME/.config/eww"
CACHE="$HOME/.cache/cook"; IMGDIR="$CACHE/img"; mkdir -p "$IMGDIR"
RECIPE="$CACHE/recipe.json"; STEPF="$CACHE/step"; CHECKF="$CACHE/checked"
PICKS="$CACHE/picks-all.json"; PICKPAGE="$CACHE/pick_page"; MOODF="$CACHE/mood"
COLS=4; PICK_PSIZE=8

URL=$(cat "$CFG/tandoor-url" 2>/dev/null || echo "http://localhost:8090")
TOK=$(cat "$CFG/tandoor-token" 2>/dev/null)
auth=(-H "Authorization: Bearer $TOK")
api(){ curl -s --max-time 12 "${auth[@]}" "$URL$1"; }

# ---- recipe image: download Tandoor's recipe.image to the cache, echo local path (or "") ----
resolve_img(){   # $1=id  $2=image(url-or-relative-or-empty) -> echoes local cached path or ""
  local id="$1" img="${2:-}" out="$IMGDIR/$1.jpg" u
  [ -s "$out" ] && { echo "$out"; return; }
  case "$img" in ""|None|null) echo ""; return;; esac
  case "$img" in http*) u="$img";; /*) u="$URL$img";; *) u="$URL/$img";; esac
  if curl -s --max-time 10 "${auth[@]}" "$u" -o "$out.tmp" 2>/dev/null && [ -s "$out.tmp" ]; then
    mv "$out.tmp" "$out"; echo "$out"
  else rm -f "$out.tmp"; echo ""; fi
}

# ============================ PICKER ============================
load_picks(){   # cache the full recipe list as [{id,name,role,image}]
  api "/api/recipe/?page_size=200" | python3 -c '
import sys,json
out=[]
for r in json.load(sys.stdin).get("results",[]):
    kws=[(k.get("label") or k.get("name") or "").lower() for k in r.get("keywords",[])]
    role="BATCH" if "batch" in kws else ("QUICK" if "quick" in kws else "")
    out.append({"id":r["id"],"name":r["name"],"role":role,"image":r.get("image") or ""})
out.sort(key=lambda x:x["name"].lower())
print(json.dumps(out))' > "$PICKS"
}

# filter the cached recipe list by mood (all|quick|batch). Echoed as JSON on stdout.
_mood_filter='
import os,json
data=json.load(open(os.environ["PICKS"])); mood=os.environ.get("MOOD","all")
if mood=="quick": data=[d for d in data if d.get("role")=="QUICK"]
elif mood=="batch": data=[d for d in data if d.get("role")=="BATCH"]
'

push_picks(){
  local page mood; page=$(cat "$PICKPAGE" 2>/dev/null || echo 0); mood=$(cat "$MOODF" 2>/dev/null || echo all)
  # slice current page (after mood filter), resolve each tile image, build rows
  local rows; rows=$(PICKS="$PICKS" COLS="$COLS" PSIZE="$PICK_PSIZE" PAGE="$page" MOOD="$mood" IMGDIR="$IMGDIR" python3 -c "
$_mood_filter
cols=int(os.environ['COLS']); psize=int(os.environ['PSIZE']); page=int(os.environ['PAGE']); imgdir=os.environ['IMGDIR']
import math
pages=max(1,math.ceil(len(data)/psize)) if data else 1; page=max(0,min(page,pages-1))
sl=data[page*psize:(page+1)*psize]
for it in sl:
    p=os.path.join(imgdir,str(it['id'])+'.jpg')
    it['img']=p if os.path.exists(p) and os.path.getsize(p)>0 else ''
rows=[sl[i:i+cols] for i in range(0,len(sl),cols)]
print(json.dumps({'pages':pages,'page':page,'rows':rows,'mood':mood}))")
  echo "$page" > "$PICKPAGE"
  PYJSON="$rows" python3 -c '
import os,json,subprocess
d=json.loads(os.environ["PYJSON"]); eww=os.path.expanduser("~/.local/bin/eww")
subprocess.run([eww,"update","cook_view=pick","cook_loaded=true","cook_mood="+d["mood"],
  "cook_picks="+json.dumps(d["rows"]),"cook_pick_page="+str(d["page"]),"cook_pick_pages="+str(d["pages"])],check=False)'
}

show_picker(){
  load_picks; echo 0 > "$PICKPAGE"; push_picks
  ( "$0" _resolve_imgs >/dev/null 2>&1 & )   # fill missing thumbnails in the background, re-push as they land
}

resolve_imgs(){   # background: resolve images for the CURRENT (mood-filtered) page, re-push after each
  local page mood; page=$(cat "$PICKPAGE" 2>/dev/null || echo 0); mood=$(cat "$MOODF" 2>/dev/null || echo all)
  PICKS="$PICKS" PSIZE="$PICK_PSIZE" PAGE="$page" MOOD="$mood" python3 -c "
$_mood_filter
psize=int(os.environ['PSIZE']); page=int(os.environ['PAGE'])
for it in data[page*psize:(page+1)*psize]: print(it['id'],it.get('image') or '')" | while read -r id img; do
    [ -s "$IMGDIR/$id.jpg" ] && continue
    [ -n "$img" ] && { resolve_img "$id" "$img" >/dev/null; push_picks; }
  done
}

plan_today(){   # create today's meal-plan entry -> remembers the pick
  local id="$1" name="${2:-Dinner}" today mt
  today=$(date +%F)
  mt=$(api "/api/meal-type/" | python3 -c 'import sys,json;r=json.load(sys.stdin).get("results",[]);print(r[0]["id"] if r else "")')
  [ -z "$mt" ] && mt=$(curl -s "${auth[@]}" -H "Content-Type: application/json" -X POST "$URL/api/meal-type/" -d '{"name":"Dinner"}' | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))')
  curl -s "${auth[@]}" -H "Content-Type: application/json" -X POST "$URL/api/meal-plan/" \
    -d "$(python3 -c 'import json,sys;print(json.dumps({"recipe":{"id":int(sys.argv[1]),"name":sys.argv[2]},"servings":4,"from_date":sys.argv[3],"to_date":sys.argv[3],"meal_type":int(sys.argv[4])}))' "$id" "$name" "$today" "$mt")" >/dev/null 2>&1
}

clear_today(){   # delete today's meal-plan entries (so the picker shows again)
  local today; today=$(date +%F)
  api "/api/meal-plan/?from_date=$today&to_date=$today" | python3 -c 'import sys,json;[print(e["id"]) for e in (json.load(sys.stdin).get("results",[]))]' \
    | while read -r mid; do curl -s "${auth[@]}" -X DELETE "$URL/api/meal-plan/$mid/" >/dev/null 2>&1; done
}

# ============================ COOK VIEW ============================
resolve_plan(){   # today's planned recipe id, or empty
  local today; today=$(date +%F)
  api "/api/meal-plan/?from_date=$today&to_date=$today" | python3 -c '
import sys,json
try:
    for e in json.load(sys.stdin).get("results",[]):
        r=e.get("recipe")
        if isinstance(r,dict) and r.get("id"): print(r["id"]); break
        if isinstance(r,int): print(r); break
except Exception: pass'
}

fetch_recipe(){   # $1=id -> normalized RECIPE json
  api "/api/recipe/$1/" | python3 -c '
import sys,json
d=json.load(sys.stdin)
def amt(a):
    if a in (None,"",0,0.0): return ""
    return str(int(a)) if float(a)==int(a) else ("%g"%a)
ings=[]
for st in d.get("steps",[]):
    for ing in st.get("ingredients",[]):
        f=(ing.get("food") or {}).get("name",""); u=(ing.get("unit") or {}).get("name","")
        t=" ".join(x for x in (amt(ing.get("amount")),u,f) if x).strip() or (ing.get("original_text") or ing.get("note") or "").strip()
        if t: ings.append(t)
import re
def split_step(s,maxlen=300):
    s=s.strip()
    if len(s)<=maxlen: return [s]
    parts=re.split(r"(?<=[.!?])\s+",s); out=[]; cur=""
    for p in parts:
        if cur and len(cur)+len(p)+1>maxlen: out.append(cur.strip()); cur=p
        else: cur=(cur+" "+p).strip()
    if cur: out.append(cur.strip())
    return out or [s]
steps=[]
for st in d.get("steps",[]):
    t=(st.get("instruction") or "").strip().strip("*").strip()
    if t: steps.extend(split_step(t))   # split giant steps so no single one overflows the screen
steps=steps or ["(no instructions were captured for this recipe)"]
kws=[(k.get("label") or k.get("name") or "").lower() for k in d.get("keywords",[])]
role="BATCH" if "batch" in kws else ("QUICK" if "quick" in kws else "")
total=int(d.get("working_time") or 0)+int(d.get("waiting_time") or 0); serv=d.get("servings") or 1
sub=" / ".join(x for x in ([f"{serv} SERVINGS",(f"{total} MIN" if total else "")]) if x)
print(json.dumps({"title":(d.get("name") or "Untitled").upper(),"sub":sub,"role":role,"ings":ings,"steps":steps}))'
}

load_cook(){   # $1=id
  local out; out=$(fetch_recipe "$1")
  [ -z "$out" ] && { "$EWW" update cook_view=pick >/dev/null 2>&1; show_picker; return; }
  printf '%s' "$out" > "$RECIPE"; echo 0 > "$STEPF"; : > "$CHECKF"
  push_cook
}

push_cook(){
  [ -s "$RECIPE" ] || { "$EWW" update cook_loaded=false >/dev/null 2>&1; return 0; }
  RECIPE="$RECIPE" STEPF="$STEPF" CHECKF="$CHECKF" EWW="$EWW" python3 -c '
import os,json,subprocess
data=json.load(open(os.environ["RECIPE"]))
try: step=int(open(os.environ["STEPF"]).read().strip() or 0)
except Exception: step=0
try: checked=set(open(os.environ["CHECKF"]).read().split())
except Exception: checked=set()
steps=data["steps"]; n=max(1,len(steps)); step=max(0,min(step,n-1))
open(os.environ["STEPF"],"w").write(str(step))
ings=[{"i":i,"text":t,"checked":(str(i) in checked)} for i,t in enumerate(data["ings"])]
cols=3 if len(ings)>16 else 2   # 3 columns for long lists so the grid never overflows the screen
rows=[ings[k:k+cols] for k in range(0,len(ings),cols)]
subprocess.run([os.environ["EWW"],"update","cook_view=cook","cook_loaded=true",
  "cook_title="+data["title"],"cook_sub="+data["sub"],"cook_role="+data["role"],
  "cook_step="+str(step),"cook_nsteps="+str(n),"cook_step_text="+steps[step],
  "cook_ning="+str(len(ings)),"cook_ings="+json.dumps(rows)],check=False)'
}

step(){ local cur; cur=$(cat "$STEPF" 2>/dev/null || echo 0)
  case "${1:-}" in prev) cur=$((cur-1));; next) cur=$((cur+1));; *) cur=${1:-0};; esac
  [ "$cur" -lt 0 ] && cur=0; echo "$cur" > "$STEPF"; push_cook; }

check(){ local i="${1:-}"; [ -z "$i" ] && return 0; touch "$CHECKF"
  if grep -qxF "$i" "$CHECKF"; then grep -vxF "$i" "$CHECKF" > "$CHECKF.tmp" || true; mv "$CHECKF.tmp" "$CHECKF"
  else echo "$i" >> "$CHECKF"; fi; push_cook; }

# ============================ dispatch ============================
case "${1:-load}" in
  load|refresh) id=$(resolve_plan); if [ -n "$id" ]; then load_cook "$id"; else show_picker; fi ;;
  pick)     plan_today "${2:-}" "${3:-Dinner}"; load_cook "${2:-}" ;;
  change)   clear_today; show_picker ;;
  mood)     echo "${2:-all}" > "$MOODF"; echo 0 > "$PICKPAGE"; push_picks
            ( "$0" _resolve_imgs >/dev/null 2>&1 & ) ;;
  pickpage) cur=$(cat "$PICKPAGE" 2>/dev/null || echo 0)
            case "${2:-}" in prev) cur=$((cur-1));; next) cur=$((cur+1));; esac
            [ "$cur" -lt 0 ] && cur=0; echo "$cur" > "$PICKPAGE"; push_picks
            ( "$0" _resolve_imgs >/dev/null 2>&1 & ) ;;
  step)     step "${2:-}" ;;
  check)    check "${2:-}" ;;
  _resolve_imgs) resolve_imgs ;;
  *) echo "usage: cook load|refresh|pick <id> <name>|change|pickpage <prev|next>|step <prev|next>|check <i>" >&2; exit 1 ;;
esac
