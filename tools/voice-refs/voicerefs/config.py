"""Endpoints, paths and fixed values for the voice-refs pipeline."""

import os
from pathlib import Path

WORK_DIR = Path(os.environ.get("VOICEREFS_WORK", "/internalmedia/voice-refs-work"))
VOICES_DIR = Path("/internalmedia/localai-models/voices")
CONTAINER_VOICES = "/models/voices"

BREEZE_URL = "http://phanteks:8090/v1/audio/speech"
LITELLM_URL = "http://pylon:4100/v1/audio/transcriptions"
# The resident Bonsai shared with the gameassets tagger (configs: gameassets bonsai.resident).
BONSAI_URL = os.environ.get("VOICEREFS_BONSAI_URL", "http://127.0.0.1:18111") + "/v1/chat/completions"

MAX_CHARS = 400
TARGET_DBFS = -20.0
# Lower than Breeze's default 0.9: steadier delivery from chunk to chunk (Oct 2026 seam tests).
MATCHED_TEMPERATURE = 0.6
SAMPLE_RATE = 24000

SOURCE_BOOK = Path(
    "/mnt/gardnerstorage/Media/Audiobooks/Shirtaloon/He Who Fights with Monsters/"
    "Shirtaloon - He Who Fights with Monsters.m4b"
)

CATEGORIES = [
    "female_calm",
    "female_intense",
    "male_casual",
    "male_intense",
    "narration_action",
    "narration_calm",
]

FALLBACK_REF = (
    "heath-miller.wav",
    "The walls were black, like some long, dormant magma chamber. But even starting "
    "from a natural cavern, it would have been a monumental labor to bring it to its "
    "current state.",
)
