"""Writes the parity fixture readaloud's Elixir planner is tested against (planner_parity.json).

  uv run python explore/parity_fixture.py ../../apps/readaloud_audiobook/test/fixtures/planner_parity.json
"""

import json
import sys

from voicerefs import names, textunits
from voicerefs.config import WORK_DIR

learned = json.loads((WORK_DIR / "plans" / "book-12" / "names.json").read_text())
curated = json.loads(open("names/reverend-insanity.json").read())
extra = ["Long", "Men Ke", "Gu Yue Bo", "Xyzzy", "Spirit Spring", "Lü Bu", "Nüwa", "Zhang San", "Er Gou", "Shi Ren"]
name_list = sorted(set(learned) | set(curated) | set(extra))

htmls = [
    "<p>Chapter 946</p><p>Translator: Atlas Studios</p><p>Hei Lou Lan&rsquo;s eyes</p>",
    "<p>Fang Yuan laughed.</p><script>window.h12_autoplaced=1;</script><style>.x{}</style><iframe src='x'>t</iframe><p>Then he left.</p>",
    "<h3>Chapter 1 &amp; More</h3><div>Line one<br/>Line two</div><p>&ldquo;Leave,&rdquo; she said. &ldquo;Now!&rdquo;</p><p>&#8220;Numeric&#8221; &#x2014; dash &hellip; &nbsp;end</p>",
    "<p>Hei Lou Lan said: “Father… you abandoned me—again.” She smiled.</p><p>“The quote continues</p><p>\"Straight quotes,\" he said.</p>",
    "<p><strong>Bold</strong> and <i>italic</i> text.</p><p>Editor: Someone</p><p>Proofreader: X</p>",
]
fixture = {
    "respell": {n: names.respell(n) for n in name_list},
    "apply_names": [
        {"text": t, "map": m, "out": names.apply_names(t, m)}
        for t, m in [
            ("Feng Jiu Ge smiled at Feng Jiu.", {"Feng Jiu Ge": "Fung Jyo Guhh", "Feng Jiu": "Fung Jyo"}),
            ("The feathermen and Feathermen came.", {"feathermen": "feather men"}),
            ("Peopleir, Hei Cheng's son.", {"Peopleir": "People", "Hei Cheng": "Hay Chung"}),
            ("Long ago, Long Hu waited.", {"Long Hu": "Long Hoo"}),
        ]
    ],
    "html": [
        {"html": h, "paragraphs": (ps := textunits.html_to_paragraphs(h)),
         "units": [{"para": u.para, "text": u.text, "quoted": u.quoted} for u in textunits.split_units(ps)]}
        for h in htmls
    ],
}
open(sys.argv[1], "w").write(json.dumps(fixture, ensure_ascii=False, indent=1) + "\n")
print(len(name_list), "names,", len(htmls), "html samples")
