"""Turn a tagged chapter into passages: one passage per speaker turn, calm narration merged."""

from dataclasses import dataclass

from .bonsai import Tag
from .library import category_of
from .textunits import Unit

MAX_NARRATION = 800


@dataclass
class Passage:
    idx: int
    text: str
    tag: Tag
    category: str | None


def build_passages(units: list[Unit], tags: list[Tag]) -> list[Passage]:
    passages: list[Passage] = []
    last_para = None
    for unit, tag in zip(units, tags):
        prev = passages[-1] if passages else None
        if prev and prev.tag == tag:
            if unit.para == last_para:
                prev.text += unit.text
                last_para = unit.para
                continue
            if tag.kind == "narration" and len(prev.text) + len(unit.text) + 1 <= MAX_NARRATION:
                prev.text += "\n" + unit.text
                last_para = unit.para
                continue
        passages.append(Passage(len(passages), unit.text, tag, category_of(tag)))
        last_para = unit.para
    return passages
