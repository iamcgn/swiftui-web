# Lets the laptop-sweep Mac's job-start hook take pull requests from claude/ branches of
# iamcgn/swiftui-web itself (never a fork's), as Corey asked on 2026-11-26. Backs up the hook,
# changes only the event check, and writes nothing unless every expected line matches.
import os, shutil, subprocess, sys
p = os.path.expanduser("~/actions-runner/hooks/job-started.sh")
s = open(p).read()
old_comment = """# 1. Only Corey's own runs of this one repository. Pull-request events are never accepted, so a
#    fork PR (which can rewrite a workflow to ask for this runner) cannot execute here even if
#    someone approves its run by mistake.
"""
new_comment = """# 1. Only Corey's own runs of this one repository. A pull request is accepted only when its head
#    is a claude/ branch of this repository itself, so a fork PR (which can rewrite a workflow to
#    ask for this runner) cannot execute here even if someone approves its run by mistake.
"""
old_case = """  push|workflow_dispatch|schedule) ;;
  *) deny "event '${GITHUB_EVENT_NAME:-}' is not allowed (only push, workflow_dispatch, schedule)" ;;
"""
new_case = """  push|workflow_dispatch|schedule) ;;
  pull_request)
    head=$(/usr/bin/python3 -c 'import json,os; h=json.load(open(os.environ["GITHUB_EVENT_PATH"]))["pull_request"]["head"]; print(h["repo"]["full_name"] + " " + h["ref"])')
    [ "${head%% *}" = "$REPO" ] || deny "pull request head repository '${head%% *}' is not $REPO"
    case "${head#* }" in
      claude/*) ;;
      *) deny "pull request branch '${head#* }' is not a claude/ branch" ;;
    esac
    ;;
  *) deny "event '${GITHUB_EVENT_NAME:-}' is not allowed (only push, workflow_dispatch, schedule, and claude/ pull requests)" ;;
"""
if new_case in s:
    print("already patched"); sys.exit(0)
if s.count(old_comment) != 1 or s.count(old_case) != 1:
    sys.exit("hook text differs from what was read; nothing changed")
t = s.replace(old_comment, new_comment).replace(old_case, new_case)
tmp = p + ".new"
open(tmp, "w").write(t)
subprocess.run(["bash", "-n", tmp], check=True)
shutil.copy2(p, p + ".bak-2026-11-26")
os.chmod(tmp, os.stat(p).st_mode)
os.replace(tmp, p)
print("patched; backup at", p + ".bak-2026-11-26")
