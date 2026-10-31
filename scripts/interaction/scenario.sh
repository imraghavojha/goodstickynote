#!/bin/zsh
# Requires Accessibility permission for the terminal (it posts real mouse/keyboard events).
# Pinned fixture notes float above other windows for ~40 s; the library is temporary.
set -e
cd "${0:A:h:h:h}"
mkdir -p .build/checks
swiftc -O scripts/interaction/drive.swift -o .build/checks/drive
swiftc -O scripts/interaction/notify.swift -o .build/checks/notify
set +e
# scenario.sh <app-binary> <label>: CPU seconds per user-facing step
BIN=$1; L=$2; D=.build/checks/drive
rm -rf /tmp/gs-sc && mkdir -p /tmp/gs-sc/Attachments
python3 - <<'PY'
import json, uuid
S=str(uuid.UUID(int=99)).upper()
def n(i,text,theme,x,y,stack=None):
    return dict(id=str(uuid.UUID(int=i)).upper(),text=text,themeID=theme,opacity=1.0,x=x,y=y,width=220,height=180,hidden=False,pinned=True,attachments=[],created=750000000,modified=750000000,**({"stackID":S} if stack else {}))
th=["butter","sage","rose","sky","lilac","linen","graphite"]
notes=[n(i+1,f"Note {i}\n"+"Some words on the note. "*6,th[i%7],1240-(i%2)*240,60+(i//2)*200) for i in range(8)]
notes+= [n(20,"Stack one\nfirst","sky",280,300,True),n(21,"Stack two\nsecond","rose",280,300,True)]
notes+= [n(30,"Hidden one","sky",280,300)]; notes[-1]["hidden"]=True
json.dump(dict(notes=notes,preferences=dict(keyCode=45,modifiers=6144,defaultTheme="butter",defaultOpacity=1.0,desktopLayoutVersion=2)),open('/tmp/gs-sc/notes.json','w'))
PY
GOODSTICKY_DATA_DIR=/tmp/gs-sc $BIN >/dev/null 2>&1 &
P=$!
cpu() { ps -o time= -p $P | awk -F: '{print $1*60+$2}'; }
last=0; out="$L"
step() { now=$(cpu); out="$out $1=$(python3 -c "print(round($now-$last,2))")"; last=$now; }
sleep 5; step launch
sleep 10; step idle10s
# notes occupy screen x 1000-1460, cg y from top: note i at cocoa y=60+(i//2)*200 -> cg top=1117-(y+180)
$D move 1100 250 1100 1000 60; $D move 1340 1000 1340 250 60; sleep 1; step hover
$D click 1340 897; sleep 0.3; $D type "The quick brown fox jumps over"; sleep 1; step type30
$D drag 1270 690 700 500; sleep 1; step drag
$D swipe 390 727 -120; $D swipe 390 727 -120; sleep 1; step swipe2
$D click 1340 897; sleep 0.2; $D key 13 c; sleep 1; step hide
.build/checks/notify app.goodsticky.showNotes /tmp/gs-sc; sleep 1.5; step notesList
$D key 43 c; sleep 1.5; step settings
$D key 13 c; sleep 0.5; $D key 53; sleep 1; step closeBoth
sleep 10; step idle10s-after
kill $P; echo $out
