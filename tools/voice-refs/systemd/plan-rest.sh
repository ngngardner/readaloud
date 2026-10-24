#!/bin/bash
# Plans every Reverend Insanity chapter from readaloud number 210 that has no voice plan yet, then exits.
# Resumable: started by voicerefs-plan.timer after each boot and an hour after a run that left chapters unplanned.
# bonsai-text and the gameassets tagger can't share GPU 1, so the tagger is paused while this runs;
# the service's ExecStopPost always hands the GPU back (voicerefs-plan-release).
set -u
LOG=/internalmedia/voice-refs-work/plan-run-2.log
API=http://pylon:4000/api/books/12/chapters
remaining() {
  curl -sf "$API" | python3 -c 'import json,sys; print(sum(1 for c in json.load(sys.stdin)["chapters"] if c["number"] >= 210 and not c["voice_plan"]))'
}
before=$(remaining) || { echo "$(date -Is) readaloud unreachable; retrying later" >> "$LOG"; exit 0; }
echo "$(date -Is) start: $before chapters without a plan" >> "$LOG"
if [ "$before" = 0 ]; then systemctl --user disable --now voicerefs-plan.timer; exit 0; fi

systemctl --user stop gameassets-tagger-gpu0.timer gameassets-tagger-gpu1.timer
# Let a tagger run that is already going finish rather than kill its Bonsai.
while systemctl --user is-active -q gameassets-tagger-gpu0.service gameassets-tagger-gpu1.service; do sleep 60; done
systemctl --user start bonsai-text
for _ in $(seq 1 100); do curl -sf http://127.0.0.1:18120/health >/dev/null && break; sleep 3; done

cd /home/noah/projects/readaloud/tools/voice-refs
# No GPU for this process: laya on GPU 0 starves LocalAI's Breeze, and GPU 1 is bonsai's.
CUDA_VISIBLE_DEVICES="" /home/noah/.local/bin/uv run voicerefs plan --start 210 --count 5000 2>&1 \
  | grep --line-buffered -v -E "Warning|warn\(|Fetching|return Agent" >> "$LOG"

after=$(remaining) || after=$before
echo "$(date -Is) end: $after chapters without a plan" >> "$LOG"
if [ "$after" = 0 ]; then
  echo "$(date -Is) all chapters planned; timer disabled" >> "$LOG"
  systemctl --user disable voicerefs-plan.timer
elif [ "$after" -ge "$before" ]; then
  echo "$(date -Is) no progress this run; timer disabled, needs a look" >> "$LOG"
  systemctl --user disable voicerefs-plan.timer
fi
