# react-icons v5 — verified icon pipeline for pptxgenjs

Tested with react-icons 5.7.0, sharp 0.35.x, react 19 (npmmirror install). The old
documentation pattern (`import { Brain } from 'react-icons/lucide'`) is BROKEN in v5.

## Breaking changes

- `react-icons/lucide` subpath no longer exists → `ERR_PACKAGE_PATH_NOT_EXPORTED`.
- Lucide set now lives in `react-icons/lu`; every export is `Lu`-prefixed:
  `import { LuBrain, LuWorkflow, LuShieldCheck } from 'react-icons/lu';`
- Some names were renamed or dropped entirely (e.g. `LuLineChart` does not exist;
  `Sparkles` became `LuWandSparkles`). ALWAYS enumerate before importing:
  `node -e "console.log(Object.keys(require('react-icons/lu')).length)"` then grep.
- Other sets renamed too (fa6, hi2, lia, lu, …). v5 exports map only allows the set
  subpaths listed in package.json `exports` — check it before assuming a subpath exists.

## Icon → PNG recipe (white icon for colored circles)

```js
// render-icons.mjs
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { LuBrain } from 'react-icons/lu';
import sharp from 'sharp';

const inner = renderToStaticMarkup(React.createElement(LuBrain, { size: 24, color: 'white' }));
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 24 24">${inner.replace(/<svg[^>]*>|<\/svg>/g, '')}</svg>`;
await sharp(Buffer.from(svg)).resize(256, 256).png().toFile('assets/icons/brain.png');
```

Then in the deck script: `slide.addImage({ path: 'assets/icons/brain.png', x, y, w, h })`
layered on top of an `ellipse` shape for the colored circle. White-stroke icons read
best on dark/gradient fills. sharp ships prebuilt binaries from npmmirror (no compile).

## The other verified half of the deck recipe

- Deck script: `require('pptxgenjs')`, `p.layout = 'LAYOUT_WIDE'` (13.3×7.5), fresh
  options object per shape (pptxgenjs mutates in place), hex without `#`.
- Validation: `<powerpoint-skill>/scripts/office/validate.py deck.pptx` needs
  defusedxml; on this machine use `/Users/xiebojun/Hermes/.venv/bin/python`.
- Both a qoderwork-ppt deck and a pptxgenjs deck passed `validate.py` + `unzip -t` —
  schema-valid ≠ visually good; the pptxgenjs path still needs human/visual judgment
  because no renderer is available locally (see SKILL.md QA section).
