# Resumable planning run on phanteks

phanteks reboots daily at 05:00, so planning a whole book (~4.5–7 min a chapter) runs as a
user service that resumes after each boot.

- `plan-rest.sh` (installed at `/internalmedia/voice-refs-work/`) runs `voicerefs plan` over every
  chapter from 210 without a plan, against the resident Bonsai the gameassets tagger shares.
- `voicerefs-plan.timer` starts the service 15 min after boot and 1 h after a run that left chapters
  unplanned. The script disables the timer when everything is planned or a run makes no progress.

Install: copy the scripts to `/internalmedia/voice-refs-work/`, the units to `~/.config/systemd/user/`,
then `systemctl --user daemon-reload && systemctl --user enable --now voicerefs-plan.timer`.
Log: `/internalmedia/voice-refs-work/plan-run-2.log`.
