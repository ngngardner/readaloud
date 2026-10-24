#!/bin/bash
# Hands GPU 1 back to the gameassets tagger after a voicerefs plan run, however it ended.
systemctl --user stop bonsai-text
systemctl --user start gameassets-tagger-gpu0.timer gameassets-tagger-gpu1.timer
