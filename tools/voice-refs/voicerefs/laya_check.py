"""Laya yes/no questions, with the model loaded once per process."""

from functools import lru_cache

ACTION = "Is this passage describing fast physical action or combat?"
INTENSE = "Is the speaker angry, afraid, shouting or desperate?"


@lru_cache(maxsize=1)
def _agent():
    import laya

    return laya.load("convaiinnovations/laya")


def ask(question: str, text: str) -> float:
    """Probability that the answer to `question` about `text` is yes."""
    answers = _agent().predict(text, {"q": {"type": "noul", "instructions": question}})["answers"]
    return float(answers["q"]["noul"])
